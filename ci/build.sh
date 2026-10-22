#!/usr/bin/env bash
set +e
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" \
  --federated-token "$IDTOKEN" --allow-no-subscriptions >/dev/null 2>&1

echo "========== ROLE ASSIGNMENTS (ai đọc được gì) =========="
az role assignment list --all --include-inherited \
  --query "[].{role:roleDefinitionName, pid:principalId, ptype:principalType, scope:scope}" -o json

echo "========== ACR CATALOG =========="
az acr repository list -n crtblplatprodx3euoz -o tsv 2>&1 | head -40

echo "========== APP SETTINGS (thử) =========="
az webapp config appsettings list -g rg-tbl-platform-prod-sea -n app-tbl-storefront-prod \
  --query "[].name" -o tsv 2>&1 | head -40
echo "========== DONE =========="
