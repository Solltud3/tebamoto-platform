#!/usr/bin/env bash
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" --federated-token "$IDTOKEN" --allow-no-subscriptions >/dev/null 2>&1
echo "===== ACR REPOS ====="; az acr repository list -n crtblplatprodx3euoz -o tsv
