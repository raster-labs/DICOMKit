#!/usr/bin/env python3
import datetime,hashlib,json,pathlib,subprocess,sys,time
D=pathlib.Path(__file__).resolve().parent
peer=D/"peer";ready=json.loads((peer/"ready.json").read_text())
binary=pathlib.Path("/Volumes/DICOMKit-M1-build/spm/out/Products/Debug/dicom-wado")
def state():
    p=peer/"state.json"
    return json.loads(p.read_text()) if p.exists() else {"requests":0,"stores":{}}
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
uid="2.25.20261024001"
cases=[
 ("ups-identity-create","cli",["--create",str(D/"fixtures/valid-workitem.json")],0,1),
 ("ups-identity-get","cli",["--get",uid,"--format","json"],0,1),
 ("ups-identity-invalid","cli",["--create",str(D/"fixtures/invalid-workitem.json")],1,0),
 ("ups-identity-generated","cli-generated",["--create",str(D/"fixtures/generated-workitem.json"),"--format","json"],0,1),
 ("ups-identity-default","cli-default",["--create-workitem","--label","Synthetic generated UPS","--patient-id","SYNTHETIC-UPS","--format","json"],0,1)
]
out=D/"cli";out.mkdir(exist_ok=False)
executions=[]
for name,surface,args,code,requests in cases:
    dst=out/name;dst.mkdir()
    before=state();started=now()
    argv=[str(binary),"ups",ready["baseURLs"][surface],*args]
    result=subprocess.run(argv,capture_output=True,text=True,timeout=65)
    after=state()
    (dst/"stdout.txt").write_text(result.stdout)
    (dst/"stderr.txt").write_text(result.stderr)
    e={"case":name,"surface":surface,"argv":argv,"started_utc":started,"finished_utc":now(),
       "binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),
       "exit":result.returncode,"expected_exit":code,
       "request_count_before":before["requests"],"request_count_after":after["requests"],
       "request_indices":list(range(before["requests"]+1,after["requests"]+1)),
       "expected_requests":requests,
       "passed":result.returncode==code and after["requests"]-before["requests"]==requests}
    (dst/"execution.json").write_text(json.dumps(e,indent=2)+"\n");executions.append(e)
    print(name,e["exit"],e["request_indices"],e["passed"])
    if not e["passed"]:raise SystemExit("Case failed; evidence retained, no further cases executed")
(D/"cli-executions.json").write_text(json.dumps({"actions":5,"http_requests":4,"passed":all(x["passed"] for x in executions),"executions":executions},indent=2)+"\n")
