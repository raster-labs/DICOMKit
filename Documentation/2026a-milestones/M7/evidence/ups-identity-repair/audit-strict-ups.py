#!/usr/bin/env python3
"""Decode strict-peer records independently; never ask production code to verify itself."""
import datetime,hashlib,json,pathlib,re,sys
D=pathlib.Path(__file__).resolve().parent
checks=[]
def ck(name,passed,detail=None):
    checks.append({"name":name,"passed":bool(passed),**({"detail":detail} if detail is not None else {})})
def valid_uid(s):
    # Independent grammar: ASCII decimal components; no leading zero except "0".
    return isinstance(s,str) and 0<len(s.encode())<=64 and all(
        p and all("0"<=c<="9" for c in p) and (len(p)==1 or p[0]!="0") for p in s.split("."))
def read(p):return json.loads(p.read_text())
native_peer=D/sys.argv[sys.argv.index("--native-peer")+1] if "--native-peer" in sys.argv else D/"peer"
records=[read(p) for p in sorted((D/"peer").glob("request-*.json"))]
if native_peer != D/"peer":
    records += [read(p) for p in sorted(native_peer.glob("request-*.json"))]
cli=read(D/"cli-executions.json")
fixture=read(D/"fixtures/valid-workitem.json");uid=fixture["00080018"]["Value"][0];dt=fixture["00404005"]["Value"][0]
ck("original synthetic fixture hash retained",hashlib.sha256((D/"fixtures/valid-workitem.json").read_bytes()).hexdigest()=="596f4b4a2dbbd9a12811283dd9441fdc56cdf8e245177c2fe40ddd4de55c59dd")
ck("five CLI actions pass expected status/count",cli["actions"]==5 and cli["http_requests"]==4 and cli["passed"])
ck("single actual repaired binary used",len({e["binary_sha256"] for e in cli["executions"]})==1)
for e in cli["executions"]:
    ck(e["case"]+" expected exit",e["exit"]==e["expected_exit"])
    ck(e["case"]+" exact HTTP count",e["request_count_after"]-e["request_count_before"]==e["expected_requests"])
cr=[r for r in records if r.get("surface","").startswith("cli")]
ck("four CLI requests exactly",len(cr)==4)
for i,r in enumerate(cr):
    ck("CLI request "+str(i+1)+" unauthenticated intentionally",not any(k.lower()=="authorization" for k in r["headers"]))
    ck("CLI request "+str(i+1)+" successful strict status",r["response"]["status"]==(200 if r["method"]=="GET" else 201))
r1,r2,r3,r4=cr
ck("supplied collection route exact",r1["target"]=="/cli/dicom-web/workitems")
ck("entire supplied body exactly preserved including UID",json.loads(r1["body"])==fixture)
ck("supplied UID response Location exact",r1["response"]["headers"]["Location"].endswith("/cli/dicom-web/workitems/"+uid))
ck("GET targets exact supplied UID",r2["target"]=="/cli/dicom-web/workitems/"+uid)
ck("GET entire returned Data Set exactly preserved",json.loads(r2["response"]["body"])==fixture)
summary=json.loads((D/"cli/ups-identity-get/stdout.txt").read_text())
ck("CLI get summary exact UID DT and state",len(summary)==1 and summary[0]["workitemUID"]==uid and summary[0]["scheduledStartDateTime"]==dt and summary[0]["state"]=="SCHEDULED")
err=(D/"cli/ups-identity-invalid/stderr.txt").read_text().strip()
ck("malformed body UID specific local refusal","Invalid workitem data: SOP Instance UID (0008,0018) must be one valid DICOM UID with VR UI" in err)
generated=json.loads(r3["body"]);guid=generated["00080018"]["Value"][0]
ck("absent identity generates valid UI VM1",generated["00080018"]=={"vr":"UI","Value":[guid]} and valid_uid(guid))
ck("generated collection body preserves all other input attributes",{k:v for k,v in generated.items() if k!="00080018"}==read(D/"fixtures/generated-workitem.json"))
ck("generated create uses collection route",r3["target"]=="/cli-generated/dicom-web/workitems")
ck("generated identity response and CLI agree",r3["response"]["headers"]["Location"].endswith("/"+guid) and "UID: "+guid in (D/"cli/ups-identity-generated/stdout.txt").read_text())
default=json.loads(r4["body"]);duid=r4["uid"]
ck("default create query carries valid generated identity",valid_uid(duid) and r4["target"]=="/cli-default/dicom-web/workitems?workitem="+duid and "00080018" not in default)
ck("default create intended values and SCHEDULED retained",default["00100020"]["Value"]==["SYNTHETIC-UPS"] and default["00741204"]["Value"]==["Synthetic generated UPS"] and default["00741000"]["Value"]==["SCHEDULED"])
ck("default response and CLI agree",r4["response"]["headers"]["Location"].endswith("/"+duid) and "UID: "+duid in (D/"cli/ups-identity-default/stdout.txt").read_text())
ck("three separately created client identities distinct",len({uid,guid,duid})==3)
ck("compact DT independent UTC interpretation",datetime.datetime.strptime(dt,"%Y%m%d%H%M%S.%f%z").astimezone(datetime.timezone.utc).isoformat()=="2026-10-24T05:00:00.123456+00:00")
limits=["Identity, body preservation, duplicate handling and DT are scoped; this peer is not a complete UPS IOD/server.",
"CLI has no UPS --timeout flag; it uses configuration defaults30/60/300s. Native timeout60 was selected. Successful cases make no timeout-equivalence claim.",
"Initial recipe supplied unsupported --timeout and failed exit64 before HTTP; preserved separately, not counted among five corrected cases.",
"Native Basic and unauthenticated CLI intentionally differ; no credential-enforcement claim.",
"Earlier UPS permissive-peer acceptance is superseded only for these repaired identity cases; earlier failure/parity records remain."]
native_actions=0
if "--native" in sys.argv:
    ui=D/"ui"
    def native(name):
        t=(ui/(name+".txt")).read_text()
        content=t.split("Complete console:\n",1)[1] if "Complete console:\n" in t else t
        return t,content
    native_records=[r for r in records if r.get("surface")=="native"]
    ck("three native actions produce exactly two HTTP requests",len(native_records)==2)
    n1,n2=native_records
    basic="Basic bTctbmF0aXZlOm9ubHktdGVzdDpwYXNz"
    for i,r in enumerate(native_records,1):
        ck("native request "+str(i)+" exact synthetic Basic header",{k.lower():v for k,v in r["headers"].items()}.get("authorization")==basic)
    ck("native collection route exact",n1["target"]=="/native/dicom-web/workitems")
    ck("native entire supplied body including UID exact",json.loads(n1["body"])==fixture)
    ck("native strict create201 and exact Location",n1["response"]["status"]==201 and n1["response"]["headers"]["Location"].endswith("/native/dicom-web/workitems/"+uid))
    ck("native get exact UID and status",n2["target"]=="/native/dicom-web/workitems/"+uid and n2["response"]["status"]==200)
    ck("native get entire Data Set identical",json.loads(n2["response"]["body"])==fixture)
    for name,status in [("ups-identity-create","SUCCESS"),("ups-identity-get","SUCCESS"),("ups-identity-invalid","ERROR")]:
        t,c=native(name);ck(name+" native "+status,"text Console "+status in t)
        if name.endswith("create"):ck("native creation console exact supplied UID","UID: "+uid in c)
        if name.endswith("invalid"):ck("native malformed local refusal matches CLI",err in c)
        if name.endswith("get"):
            # Capture is AX console text, with optional Executing line preceding the JSON.
            start=c.find("["); end=c.rfind("]")
            nsummary=json.loads(c[start:end+1])
            ck("native and CLI complete get summary identical",nsummary==summary)
    ck("native and CLI strict stores independently retain same UID",read(native_peer/"state.json")["stores"]["native"][uid]==read(D/"peer/state.json")["stores"]["cli"][uid]==fixture)
    native_actions=3
    ck("six total recorded HTTP requests",len(records)==6)
out={"passed":all(c["passed"] for c in checks),"verified_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
"native_actions":native_actions,"CLI_actions":5,"paired_native_CLI_actions":3 if native_actions else 0,"extra_CLI_actions":2,
"assertions":len(checks),"checks":checks,"limits":limits,
"supersedes":"Earlier native-final-network/native-ups-verification.json established parity while omitting required body UID. It remains historical and open in that original epoch.",
"binary_sha256":cli["executions"][0]["binary_sha256"]}
dest=D/("strict-ups-final-verification.json" if native_actions else "strict-ups-cli-verification.json")
dest.write_text(json.dumps(out,indent=2)+"\n")
print(json.dumps({"passed":out["passed"],"assertions":len(checks),"failures":[c for c in checks if not c["passed"]]},indent=2))
