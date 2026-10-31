#!/usr/bin/env python3
"""Opt-in actual DICOMNetwork TLS client qualification against independent peers.
Run with the pinned OpenSSL-backed peer venv. Generates only ephemeral test PKI;
never changes system/keychain trust and never connects outside loopback.
"""
import argparse, hashlib, json, os, pathlib, socket, ssl, subprocess, sys, threading
import pydicom, pynetdicom
from pynetdicom import AE, evt
from pynetdicom.sop_class import Verification

def save(path,value): path.write_text(json.dumps(value,indent=2)+'\n')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--test-bundle',type=pathlib.Path,required=True);p.add_argument('--output-dir',type=pathlib.Path,required=True);p.add_argument('--openssl',default='/opt/homebrew/opt/openssl@3/bin/openssl');a=p.parse_args()
 root=a.output_dir.resolve();root.mkdir(parents=True,exist_ok=True)
 if list(root.iterdir()):p.error('Use an empty output directory')
 assert pydicom.__version__=='3.0.1' and pynetdicom.__version__=='3.0.4','Use pinned peer packages'
 versions={'python':sys.version,'ssl':ssl.OPENSSL_VERSION,'TLS13_available':ssl.HAS_TLSv1_3,'pydicom':pydicom.__version__,'pynetdicom':pynetdicom.__version__}
 save(root/'versions.json',versions)
 if not ssl.HAS_TLSv1_3:
  save(root/'results.json',{'result':'Blocked','reason':'Independent Python/OpenSSL peer lacks TLS1.3','passed':0});return 2
 def openssl(*args):
  r=subprocess.run([a.openssl,*map(str,args)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
  with (root/'pki-generation.log').open('ab') as f:f.write(r.stdout+r.stderr)
  assert r.returncode==0,r.stderr.decode(errors='replace')
 def ca(name):
  openssl('req','-x509','-newkey','rsa:2048','-nodes','-sha256','-days','1','-subj','/CN=M7-'+name,
   '-keyout',root/(name+'.key'),'-out',root/(name+'.pem'),'-addext','basicConstraints=critical,CA:TRUE')
  openssl('x509','-in',root/(name+'.pem'),'-outform','DER','-out',root/(name+'.der'))
 def leaf(name,san):
  openssl('req','-new','-newkey','rsa:2048','-nodes','-sha256','-subj','/CN='+name,'-keyout',root/(name+'.key'),'-out',root/(name+'.csr'))
  ext=root/(name+'.ext');ext.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName='+san+'\n')
  openssl('x509','-req','-in',root/(name+'.csr'),'-CA',root/'ca.pem','-CAkey',root/'ca.key','-CAcreateserial','-sha256','-days','1','-extfile',ext,'-out',root/(name+'.pem'))
 ca('ca');ca('wrong-ca');leaf('localhost','DNS:localhost,IP:127.0.0.1');leaf('wrong-host','DNS:wrong-host.invalid')
 peers=[];rows=[];handshakes=[];controls=[];lock=threading.Lock();cases=[]
 # OpenSSL names for the nine suites currently exposed by TLSCipherSuite.modifiedBCP195.
 # This checks the configured subset, not the full PS3.15 profile requirements.
 allowed_modified={'TLS_AES_256_GCM_SHA384','TLS_CHACHA20_POLY1305_SHA256','TLS_AES_128_GCM_SHA256','ECDHE-ECDSA-AES256-GCM-SHA384','ECDHE-RSA-AES256-GCM-SHA384','ECDHE-ECDSA-CHACHA20-POLY1305','ECDHE-RSA-CHACHA20-POLY1305','ECDHE-RSA-AES128-GCM-SHA256','ECDHE-ECDSA-AES128-GCM-SHA256'}
 class RecordingContext(ssl.SSLContext):
  def wrap_socket(self,*args,**kwargs):
   # Bound a peer handshake independently of the client deadline.
   args[0].settimeout(8)
   try:
    transport=super().wrap_socket(*args,**kwargs)
    with lock:handshakes.append({'name':self.case_name,'phase':self.phase,'success':True,'version':transport.version(),'cipher':transport.cipher()})
    if self.phase=='control':self.control_completed.set()
    return transport
   except ssl.SSLError as error:
    with lock:handshakes.append({'name':self.case_name,'phase':self.phase,'success':False,'reason':error.reason,'error':str(error)})
    raise
 def endpoint(name,version,cert='localhost'):
  context=RecordingContext(ssl.PROTOCOL_TLS_SERVER);context.case_name=name;context.phase='control';context.control_completed=threading.Event();context.minimum_version=version;context.maximum_version=version
  context.load_cert_chain(str(root/(cert+'.pem')),str(root/(cert+'.key')))
  ae=AE(ae_title='M7TLSPEER');ae.add_supported_context(Verification);ae.acse_timeout=5;ae.dimse_timeout=5
  def echo(event):
   transport=event.assoc.dul.socket.socket
   row={'name':name,'version':transport.version(),'cipher':transport.cipher(),'status':0,'calling_aet':event.assoc.requestor.ae_title}
   with lock:rows.append(row)
   return 0
  server=ae.start_server(('127.0.0.1',0),block=False,ssl_context=context,evt_handlers=[(evt.EVT_C_ECHO,echo)])
  peers.append(server);port=server.server_address[1]
  # Prove each exact endpoint/certificate can negotiate with the valid root and
  # matching hostname before the Swift negative case; refusal/timeout alone is insufficient.
  control=ssl.create_default_context(cafile=str(root/'ca.pem'));control.minimum_version=version;control.maximum_version=version
  hostname='wrong-host.invalid' if cert=='wrong-host' else 'localhost'
  with socket.create_connection(('127.0.0.1',port),timeout=5) as raw:
   with control.wrap_socket(raw,server_hostname=hostname) as transport:
    controls.append({'name':name,'version':transport.version(),'cipher':transport.cipher(),'certificate_hostname':hostname,'success':True})
  assert context.control_completed.wait(5),'Peer control handshake did not complete'
  context.phase='client';return port
 def case(name,version,expected=True,trust='custom',root_name='ca',cert='localhost',minimum=None,modified=False):
  port=endpoint(name,version,cert);v='TLS 1.3' if version==ssl.TLSVersion.TLSv1_3 else 'TLS 1.2'
  cases.append({'name':name,'host':'localhost','port':port,'trust':trust,'rootDER':str(root/(root_name+'.der')),'minimum':minimum or v,'maximum':minimum or v,'expectedSuccess':expected,'modifiedProfile':modified})
 try:
  case('TLS12-custom-trust',ssl.TLSVersion.TLSv1_2)
  case('TLS12-modified-cipher-subset',ssl.TLSVersion.TLSv1_2,modified=True)
  case('TLS13-custom-trust',ssl.TLSVersion.TLSv1_3)
  case('TLS13-modified-cipher-subset',ssl.TLSVersion.TLSv1_3,modified=True)
  case('untrusted-system-root-refused',ssl.TLSVersion.TLSv1_2,False,trust='system')
  case('wrong-custom-root-refused',ssl.TLSVersion.TLSv1_2,False,root_name='wrong-ca')
  case('wrong-hostname-refused',ssl.TLSVersion.TLSv1_2,False,cert='wrong-host')
  case('TLS13-only-client-refuses-TLS12-peer',ssl.TLSVersion.TLSv1_2,False,minimum='TLS 1.3')
  save(root/'cases.json',cases);save(root/'peer-controls.json',controls)
  env=dict(os.environ,DICOMKIT_M7_TLS_CASES=str(root/'cases.json'),DICOMKIT_M7_TLS_RESULTS=str(root/'client-results.json'))
  r=subprocess.run(['xcrun','xctest','-XCTest','DICOMNetworkTests.M7TLSRuntimeHarnessTests/testIndependentTLSPeers',str(a.test_bundle)],env=env,capture_output=True,text=True,timeout=120)
  (root/'client-harness.log').write_text(r.stdout+r.stderr)
  assert r.returncode==0,r.stdout+r.stderr
  client=json.loads((root/'client-results.json').read_text());assert len(client)==len(cases)==8
  for expected,actual in zip(cases,client):
   assert expected['name']==actual['name'] and actual['success']==expected['expectedSuccess'],actual
   wire=[x for x in rows if x['name']==expected['name']]
   assert len(wire)==int(expected['expectedSuccess']),(expected,wire)
   if wire:
    assert wire[0]['version']==('TLSv1.3' if expected['minimum']=='TLS 1.3' else 'TLSv1.2'),wire
    if expected['modifiedProfile']:assert wire[0]['cipher'][0] in allowed_modified,wire
   else:
    refused=[x for x in handshakes if x['name']==expected['name'] and x['phase']=='client' and not x['success']]
    assert refused,('No independently recorded TLS handshake refusal',expected,actual,handshakes)
    reasons={'UNSUPPORTED_PROTOCOL','TLSV1_ALERT_PROTOCOL_VERSION'} if expected['name'].startswith('TLS13-only') else {'TLSV1_ALERT_UNKNOWN_CA','SSLV3_ALERT_BAD_CERTIFICATE','SSLV3_ALERT_CERTIFICATE_UNKNOWN','TLSV1_ALERT_ACCESS_DENIED'}
    assert any(x['reason'] in reasons for x in refused),('Unexpected failure cannot qualify TLS policy refusal',refused,actual)
  save(root/'peer-echo-records.json',rows);save(root/'peer-handshakes.json',handshakes)
  save(root/'results.json',{'result':'Passed','cases':8,'positive':4,'negative':4,'versions':versions,'scope':'Actual DICOMNetwork library C-ECHO over independently terminated TLS; no system trust mutation. CLI/server TLS, full PS3.15 B.12/B.13 cipher/certificate rules, revocation, and mutual TLS are not qualified by these cases.','public_certificate_hashes':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in root.glob('*.der')}})
  print('M7 TLS:8 independent cases passed');return 0
 except Exception as error:
  save(root/'peer-echo-records.json',rows);save(root/'peer-handshakes.json',handshakes);save(root/'results.json',{'result':'Failed','error':str(error),'versions':versions});raise
 finally:
  for server in peers:server.shutdown();server.server_close()
if __name__=='__main__':sys.exit(main())
