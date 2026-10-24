#!/usr/bin/env python3
"""Real process store/restart/FIND/GET/MOVE gates using independent Part 10 bytes.

All data is synthetic. The storage guarantee tested is completed C-STORE across
process termination/restart, not power-loss recovery or a database implementation.
"""
import argparse, hashlib, json, os, pathlib, shutil, signal, socket, struct, subprocess, sys, time
sys.dont_write_bytecode = True
from verify_m3_queries import make_fixtures, STUDIES, INSTANCES


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def dataset_bytes(file):
    data = pathlib.Path(file).read_bytes()
    assert data[128:132] == b'DICM' and data[132:140] == b'\x02\0\0\0UL\x04\0'
    offset = 144 + struct.unpack_from('<I', data, 140)[0]
    assert offset < len(data)
    return data[offset:]


def digest(file):
    return hashlib.sha256(dataset_bytes(file)).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin-dir', type=pathlib.Path, required=True)
    parser.add_argument('--test-bundle', type=pathlib.Path, required=True)
    parser.add_argument('--output-dir', type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=False)
    fixtures = root / 'fixtures'; make_fixtures(fixtures)
    original = fixtures / 'synthetic-0.dcm'
    expected = digest(original)
    processes, records = [], []

    def run(name, argv, expected_exit=0, text=None):
        result = subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=45)
        (root / (name + '.stdout.txt')).write_text(result.stdout)
        (root / (name + '.stderr.txt')).write_text(result.stderr)
        assert result.returncode == expected_exit, (name, result.returncode, result.stdout, result.stderr)
        if text: assert text.lower() in (result.stdout + result.stderr).lower(), (name, result.stdout, result.stderr)
        records.append({'name': name, 'exit': result.returncode, 'argv': list(map(str, argv))})
        return result

    def server_args(directory, target_port, *extra):
        return [args.bin_dir/'dicom-server', 'start', '--data-dir', directory, '--port', str(target_port),
                '--aet', 'M4SCP', *extra]

    def start(name, directory, target_port, *extra):
        log = (root / (name + '.log')).open('w')
        process = subprocess.Popen(list(map(str, server_args(directory, target_port, *extra))), stdout=log, stderr=subprocess.STDOUT)
        processes.append((process, log))
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            assert process.poll() is None, (name, (root / (name + '.log')).read_text())
            try:
                with socket.create_connection(('127.0.0.1', target_port), timeout=.2): return process
            except OSError: time.sleep(.05)
        raise AssertionError('Server failed to listen: ' + name)

    def stop(process, abrupt=False):
        process.send_signal(signal.SIGKILL if abrupt else signal.SIGTERM)
        process.wait(timeout=10)

    def client(binary, target_port):
        return [args.bin_dir/binary, '127.0.0.1', '--port', str(target_port), '--aet', 'M4CLIENT',
                '--called-aet', 'M4SCP', '--timeout', '5']

    def check_files(directory, count=1):
        files = list(directory.rglob('*.dcm'))
        assert len(files) == count, (str(directory), files)
        assert all(digest(file) == expected for file in files), ('Dataset differs', str(directory))
        return files

    def query(name, target_port):
        result = run(name, client('dicom-query', target_port) + ['--level', 'study', '--study-uid', STUDIES[0], '--format', 'json'])
        rows = json.loads(result.stdout)
        assert len(rows) == 1 and rows[0]['(0020,000D)'] == STUDIES[0], rows

    try:
        data, receiver_data = root/'store', root/'move-store'
        source_port, receiver_port = port(), port()
        receiver = start('receiver', receiver_data, receiver_port)
        options = ['--move-destination', f'M4DEST=127.0.0.1:{receiver_port}']
        source = start('initial', data, source_port, *options)
        run('store', client('dicom-send', source_port) + [original], text='All files sent successfully')
        check_files(data)
        query('find-before-restart', source_port)
        run('identical-retransmission', client('dicom-send', source_port) + [original], text='All files sent successfully')
        check_files(data)
        conflict = root/'conflict.dcm'
        content = original.read_bytes(); assert b'Chest synthetic' in content
        conflict.write_bytes(content.replace(b'Chest synthetic', b'Other synthetic'))
        run('conflicting-retransmission', client('dicom-send', source_port) + [conflict], expected_exit=1, text='not stored')
        check_files(data)
        run('exclusive-process-lock', server_args(data, port()), expected_exit=1, text='already in use')
        stop(source)
        source = start('restart', data, source_port, *options)
        query('find-after-restart', source_port)
        run('get-after-restart', client('dicom-retrieve', source_port) + ['--method', 'c-get', '--study-uid', STUDIES[0], '--output', root/'get'], text='1 file(s) received')
        check_files(root/'get')
        run('move-after-restart', client('dicom-retrieve', source_port) + ['--method', 'c-move', '--study-uid', STUDIES[0], '--move-dest', 'M4DEST', '--output', root/'unused'], text='Completed')
        check_files(receiver_data)
        # Process kill after a completed store must also leave a discoverable object.
        stop(source, abrupt=True)
        source = start('restart-after-kill', data, source_port, *options)
        query('find-after-kill', source_port)
        env = dict(os.environ, DICOMKIT_M4_DURABLE_PORT=str(source_port), DICOMKIT_M4_DURABLE_OUTPUT=str(root), DICOMKIT_M4_DURABLE_STUDY=STUDIES[0])
        result = subprocess.run(['xcrun','xctest','-XCTest','DICOMStudioTests.M4ClientOutcomeHarnessTests/testRestartedServerClients',str(args.test_bundle)],env=env,capture_output=True,text=True,timeout=90)
        (root/'workshop.log').write_text(result.stdout+result.stderr)
        assert result.returncode == 0, result.stdout+result.stderr
        check_files(root/'workshop-get')
        app = json.loads((root/'workshop-durability.json').read_text()); assert len(app)==3 and all(row['exit']==0 for row in app), app
        check_files(receiver_data)
        stop(source); stop(receiver)
        # Each failure is tested by starting a fresh executable. It must exit,
        # rather than listen with an incomplete/ambiguous index.
        for name, prepare, diagnostic in [
            ('duplicate-uid', lambda d: [shutil.copyfile(original,d/'a.dcm'),shutil.copyfile(original,d/'b.dcm')], 'duplicate SOP Instance UID'),
            ('corrupt-file', lambda d: (d/'bad.dcm').write_bytes(b'not DICOM'), 'Reindex rejected'),
            ('truncated-file', lambda d: (d/'bad.dcm').write_bytes(original.read_bytes()[:-3]), 'Reindex rejected'),
            ('trailing-garbage', lambda d: (d/'bad.dcm').write_bytes(original.read_bytes()+b'X'), 'Reindex rejected'),
            ('symbolic-link', lambda d: (d/'linked.dcm').symlink_to(original), 'symbolic link'),
            ('unreadable-file', lambda d: [shutil.copyfile(original,d/'bad.dcm'),os.chmod(d/'bad.dcm',0)], 'unreadable'),
        ]:
            directory = root/name; directory.mkdir(); prepare(directory)
            try: run(name, server_args(directory,port()), expected_exit=1, text=diagnostic)
            finally:
                if name=='unreadable-file': os.chmod(directory/'bad.dcm',0o600)
        for backend in ['sqlite','postgres','postgresql']:
            run('refuse-'+backend, server_args(root/('backend-'+backend),port(),'--database',backend), expected_exit=1,text='not implemented')
        for backend in ['sqlite:///tmp/m4.db','postgres://localhost/m4']:
            run('refuse-url-'+backend.split(':')[0],server_args(root/'url-test',port(),'--database-url',backend),expected_exit=1,text='not implemented' if backend.startswith('sqlite') else 'not supported')
        (root/'results.json').write_text(json.dumps({'passed':True,'process_cases':len(records),'workshop_cases':3,
            'sop_instance_uid':INSTANCES[0],'dataset_sha256':expected,'records':records,
            'scope':'Completed store persists across SIGTERM and SIGKILL; no power-loss qualification',
            'binaries':{name:hashlib.sha256((args.bin_dir/name).read_bytes()).hexdigest() for name in ['dicom-server','dicom-send','dicom-query','dicom-retrieve']}},indent=2)+'\n')
        print(f'M4 durability: {len(records)} process cases + 3 Workshop clients passed; dataset SHA256 {expected}')
    finally:
        for process, log in processes:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
            log.close()


if __name__ == '__main__': main()
