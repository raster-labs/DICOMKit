#!/usr/bin/env python3
"""M5 real CLI/Workshop actions with synthetic files and a local filesystem SCP."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from verify_m2_attributes import encode, scalar
from verify_m5_toolbox import fixture
from verify_m4_durability import dataset_bytes, port


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bin-dir', type=Path, required=True)
    p.add_argument('--test-bundle', type=Path, required=True)
    p.add_argument('--output-dir', type=Path, required=True)
    a = p.parse_args()
    root = a.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=False)
    source = root / 'synthetic.dcm'
    original = fixture()
    source.write_bytes(original)
    pixel = root / 'burned-in-synthetic.dcm'
    pixel.write_bytes(original + b''.join([
        encode((0x28, 2), 'US', b'\1\0'), encode((0x28, 4), 'CS', b'MONOCHROME2'),
        encode((0x28, 0x10), 'US', b'\1\0'), encode((0x28, 0x11), 'US', b'\2\0'),
        encode((0x28, 0x100), 'US', b'\10\0'), encode((0x28, 0x101), 'US', b'\10\0'),
        encode((0x28, 0x102), 'US', b'\7\0'), encode((0x28, 0x103), 'US', b'\0\0'),
        encode((0x28, 0x301), 'CS', b'YES'), encode((0x7fe0, 0x10), 'OB', b'\0\xff')]))
    valid = root / 'valid.dcmscript'
    valid.write_text('dicom-info ' + json.dumps(str(source)) + ' --format json\n')
    bad = {
        'unknown-root': 'dicom-not-a-tool input.dcm\n',
        'unknown-pipeline': 'dicom-info input.dcm | dicom-not-a-tool input.dcm\n',
        'unknown-conditional': 'if exists absent.dcm\ndicom-not-a-tool input.dcm\nendif\n',
        'unknown-option-equals': 'dicom-not-a-tool --value=1\n',
        'conditional-pipeline': 'if exists absent.dcm\ndicom-info input.dcm | dicom-not-a-tool input.dcm\nendif\n',
    }
    for name, text in bad.items(): (root / (name + '.dcmscript')).write_text(text)
    requests, records, cli_text = [], [], {}
    passed = False
    server = None
    server_log = None

    def run(name, tool, argv, success=True):
        env = dict(os.environ, PATH=str(a.bin_dir) + os.pathsep + os.environ.get('PATH', ''))
        command = [str(a.bin_dir / tool), *map(str, argv)]
        result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=60)
        (root / (name + '.stdout.txt')).write_text(result.stdout)
        (root / (name + '.stderr.txt')).write_text(result.stderr)
        records.append({'name': name, 'argv': command, 'exit': result.returncode, 'expected_success': success})
        assert (result.returncode == 0) == success, (name, result.returncode, result.stdout, result.stderr)
        cli_text[name] = result.stdout + result.stderr
        return result

    def request(name, tool, values, success=True, exit_code=None):
        item = {'name': name, 'tool': tool, 'values': {k: str(v) for k, v in values.items()},
                'expectedStatus': 'SUCCESS' if success else 'ERROR'}
        if exit_code is not None: item['expectedExit'] = exit_code
        requests.append(item)

    try:
        for name in ['workflow', 'pipeline', 'query', 'archive', 'anonymize']:
            case = 'template-' + name
            run(case, 'dicom-script', ['template', name])
            request(case, 'dicom-script', {'operation': 'template', 'templateName': name}, exit_code=0)
        for operation in ['validate', 'dry-run']:
            args = ['validate', valid] if operation == 'validate' else ['run', valid, '--dry-run']
            run(operation, 'dicom-script', args)
            request(operation, 'dicom-script', {'operation': 'validate' if operation == 'validate' else 'run',
                    'scriptPath': valid, 'dryRun': 'true'}, exit_code=0)
        run('cli-live', 'dicom-script', ['run', valid, '--verbose'])
        assert 'M5^SYNTHETIC' in cli_text['cli-live']
        request('workshop-live-refused', 'dicom-script', {'scriptPath': valid, 'dryRun': 'false',
                'log': root / 'must-not-start/run.log'}, success=False)
        for name in bad:
            script = root / (name + '.dcmscript')
            run(name, 'dicom-script', ['run', script, '--dry-run', '--log', root / (name + '-cli.log')], success=False)
            run(name + '-validate', 'dicom-script', ['validate', script], success=False)
            assert not (root / (name + '-cli.log')).exists()
            request(name, 'dicom-script', {'scriptPath': script, 'dryRun': 'true',
                    'log': root / 'must-not-start' / (name + '.log')}, success=False, exit_code=1)
            request(name + '-validate', 'dicom-script', {'operation': 'validate', 'scriptPath': script}, success=False, exit_code=1)
        for allow in [False, True]:
            name = 'phi-' + str(allow).lower()
            argv = [pixel, '--output', root / (name + '-cli.dcm'), '--no-clean-pixel-data']
            if allow: argv.append('--allow-burned-in-phi')
            run(name, 'dicom-anon', argv, success=allow)
            request(name, 'dicom-anon', {'inputPath': pixel, 'output': root / (name + '-workshop.dcm'),
                    'clean-pixel-data': 'false', 'allow-burned-in-phi': str(allow).lower()}, success=allow, exit_code=0 if allow else 1)

        storage = root / 'storage'
        storage.mkdir()
        (storage / 'synthetic.dcm').write_bytes(original)
        target_port = port()
        server_log = (root / 'server.log').open('w')
        server = subprocess.Popen([str(a.bin_dir / 'dicom-server'), 'start', '--data-dir', str(storage),
            '--port', str(target_port), '--aet', 'M5SCP', '--database', 'filesystem'], stdout=server_log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 15
        while True:
            assert server.poll() is None and time.monotonic() < deadline, 'Synthetic SCP startup failed'
            try:
                with socket.create_connection(('127.0.0.1', target_port), timeout=.2): break
            except OSError: time.sleep(.05)
        (root / 'server-ready.json').write_text(json.dumps({'port': target_port, 'aet': 'M5SCP', 'study_uid': '2.25.505'}))
        for mode in ['review', 'auto']:
            name = 'qr-' + mode
            run(name, 'dicom-qr', ['query', '127.0.0.1', '--port', target_port, '--aet', 'M5CLIENT',
                '--called-aet', 'M5SCP', '--method', 'c-get', '--' + mode, '--study-uid', '2.25.505',
                '--timeout', '5', '--output', root / (name + '-cli')])
            request(name, 'dicom-qr', {'host': '127.0.0.1', 'port': target_port, 'aet': 'M5CLIENT',
                'called-aet': 'M5SCP', 'method': 'c-get', 'mode': mode, 'study-uid': '2.25.505',
                'timeout': 5, 'output': root / (name + '-workshop')}, exit_code=0)
        request('stale-interactive', 'dicom-qr', {'host': '127.0.0.1', 'port': target_port, 'mode': 'interactive',
            'method': 'c-get', 'output': root / 'must-not-start/interactive'}, success=False)
        (root / 'requests.json').write_text(json.dumps(requests, indent=2) + '\n')
        env = dict(os.environ, DICOMKIT_M5_WORKSHOP_REQUESTS=str(root / 'requests.json'),
                   DICOMKIT_M5_WORKSHOP_OUTPUT=str(root / 'workshop.json'))
        result = subprocess.run(['xcrun', 'xctest', '-XCTest',
            'DICOMStudioTests.M5WorkshopActionHarnessTests/testConfiguredWorkshopActions', str(a.test_bundle)],
            cwd=root, env=env, capture_output=True, text=True, timeout=180)
        (root / 'workshop.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stdout + result.stderr
        app = {item['name']: item for item in json.loads((root / 'workshop.json').read_text())}
        assert len(app) == len(requests)
        for name in ['template-' + n for n in ['workflow', 'pipeline', 'query', 'archive', 'anonymize']] + ['validate', 'dry-run']:
            body = app[name]['console'].split('\n\n', 1)[-1]
            assert body.strip() == cli_text[name].strip(), (name, body, cli_text[name])
        for name in ['workshop-live-refused', 'stale-interactive']:
            assert app[name]['historyCount'] == 0 and not app[name]['validBeforeRun']
        assert not (root / 'must-not-start').exists()
        for suffix in ['cli', 'workshop']:
            assert not (root / ('phi-false-' + suffix + '.dcm')).exists()
            assert scalar((root / ('phi-true-' + suffix + '.dcm')).read_bytes(), (0x12, 0x62)) == 'NO'
            assert not list((root / ('qr-review-' + suffix)).rglob('*.dcm'))
            files = list((root / ('qr-auto-' + suffix)).rglob('*.dcm'))
            assert len(files) == 1 and dataset_bytes(files[0]) == dataset_bytes(source), files
        for name in ['phi-false', 'phi-true']:
            assert app[name]['visibleParameterIDs'].count('allow-burned-in-phi') == 1
            assert app[name]['preview'].count('--allow-burned-in-phi') == (1 if name == 'phi-true' else 0)
        assert source.read_bytes() == original
        passed = True
        print(f'M5 Workshop: {len(records)} CLI cases + {len(requests)} ViewModel actions passed')
    finally:
        if server is not None and server.poll() is None:
            server.send_signal(signal.SIGTERM)
            try: server.wait(timeout=10)
            except subprocess.TimeoutExpired: server.kill(); server.wait(timeout=5)
        if server_log is not None: server_log.close()
        (root / 'results.json').write_text(json.dumps({'passed': passed, 'cli_cases': len(records),
            'workshop_cases': len(requests), 'records': records, 'fixture_sha256': hashlib.sha256(original).hexdigest(),
            'scope': 'Actual CLI and ViewModel runtime; synthetic loopback only. Packaged GUI is separately recorded.'}, indent=2) + '\n')


if __name__ == '__main__': main()
