#!/usr/bin/env python3
"""Read-only audit of captured repaired print controls and registry actions."""
import datetime,json,re,shlex
from pathlib import Path
from verify_print_native_outputs import copied_console,digest
from verify_print_cli_replays import console_body
R=Path(__file__).resolve().parent;U=R/'ui-repaired';checks=[]
def check(name,ok,detail):checks.append({'check':name,'status':'Passed' if ok else 'Failed','detail':detail})
base=json.loads((R/'config/baseline-scp.json').read_text());captures={}
for name,flag,color in [('inherited-status',None,False),('enabled','--accept-color',True),('disabled','--no-accept-color',False)]:
 p=U/('scp-repaired-'+name+'-granted-console.txt');c=copied_console(p);expected=dict(base,supportsColor=color);check(name+' full configuration',c['values']==[expected],{'argv':c['argv'],'payload':c['values'],'expected':expected,'source':str(p),'sha256':digest(p.read_bytes())})
 check(name+' matching argv',('--accept-color' in c['argv'])==(flag=='--accept-color') and ('--no-accept-color'in c['argv'])==(flag=='--no-accept-color'),'Omitted, positive and inverted flags agree with full resolved settings')
 captures[name]=c
for state,flag in [('enabled','--accept-color'),('disabled','--no-accept-color'),('return-inherit',None)]:
 p=U/('scp-tristate-'+state+'.txt');text=p.read_text();m=re.search(r'Description: Accept Color,.*?\n((?:\s*\d+ radio button[^\n]*\n){3})',text)
 expected='inherit' if flag is None else state;check(state+' visible radio selection',bool(m) and bool(re.search(r'Description: '+expected+r', Value: 1',m.group(1))),{'source':str(p),'selected':expected})
 p=U/('scp-tristate-'+state+'-command.txt');text=p.read_text();first=text.split('Description: Print command to import, Value: ',1)[1].split('\n',1)[0];argv=shlex.split(first);check(state+' copied command',('--accept-color'in argv)==(flag=='--accept-color') and ('--no-accept-color'in argv)==(flag=='--no-accept-color'),{'source':str(p),'argv':argv})
prior=copied_console(R/'ui/print-list-populated-console.txt');persist=copied_console(U/'printer-persistence-console.txt');check('registry survives native relaunch',persist['values']==prior['values'],{'nativePrior':prior['values'],'nativeRelaunched':persist['values'],'scope':'Actual app relaunch identity is parent-owned; captured records compare exactly'})
empty=copied_console(U/'printer-empty-json-console.txt');check('repaired empty JSON array',empty['values']==[[]] and console_body(U/'printer-empty-json-console.txt').strip().startswith('['),'Actual repaired native JSON is [] rather than text guidance')
check('empty text guidance retained','No printers configured.' in console_body(U/'printer-empty-text-console.txt'),'Actual text contract remains explanatory')
check('native synthetic remove succeeds',"Printer 'Native; O'Neil 雪' removed successfully" in console_body(U/'printer-remove-console.txt'),'Exact literal synthetic profile removed')
check('native missing remove refused',"Error: Printer with name 'Native; O'Neil 雪' not found"==console_body(U/'printer-remove-missing-console.txt'),'Second removal refuses with exact name')
old=copied_console(U/'scp-repaired-inherited-status-console.txt');old_name=old['values'][0].get('PrinterName');gaps=['Latest checkbox layout repair still needs final package identity and bounded native control validation.','No native case group completed by this file; parent reconciles preserved source equivalence and remaining distinct run-card cases.']
out={'recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Passed recorded checks; overall native acceptance partial','checks':checks,'failures':[x['check'] for x in checks if x['status']=='Failed'],'earlierUngrantCapture':{'source':old['source'],'reportedPrinterName':old_name,'expectedConfigPrinterName':base['printerName'],'classification':'Captured default fallback; not config inheritance success. Root subsequent Browse-granted verbose trio establishes exact configuration use. No permissions bypass.','sourceMechanism':['CLIWorkshopPrintExecution.importPrintCommand clears grants','SCPConfigOptions.load / PrintSCPSettingsFile.read fall back when inaccessible/unreadable']},'pending':gaps,'capturedSourceIdentity':'Post-first-repair packaged app; final checkbox layout repair pending parent freeze','productsInvoked':0}
(R/'repaired-print-controls-review.json').write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n');print(json.dumps({'passed':sum(c['status']=='Passed' for c in checks),'failed':out['failures']},indent=2))
