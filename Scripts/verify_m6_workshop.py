#!/usr/bin/env python3
"""M6 existing-binary CLI/Workshop loopback campaign. No build or GUI claim.

Run using the prepared peer-venv Python (Pillow is required for raster checks).
The corpus is materialized separately for isolated CLI and Workshop stores.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import time
import traceback
from PIL import Image

VOLATILE_JSON_KEYS = {'printJobUID', 'printJobUIDs', 'filmSessionUID', 'filmBoxUID', 'filmBoxUIDs', 'receivedAt'}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def wait_ready(process, number, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        assert process.poll() is None, 'Listener exited before readiness'
        try:
            with socket.create_connection(('127.0.0.1', number), timeout=.15): return
        except OSError: time.sleep(.03)
    raise AssertionError('Listener did not become ready within deadline')


def stop(process):
    if process is not None and process.poll() is None:
        process.send_signal(signal.SIGINT)
        try: process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)


def json_values(text):
    decoder = json.JSONDecoder(); result = []; offset = 0
    while offset < len(text):
        starts = [x for x in [text.find('{', offset), text.find('[', offset)] if x >= 0]
        if not starts: break
        offset = min(starts)
        try: value, length = decoder.raw_decode(text[offset:])
        except ValueError: offset += 1; continue
        result.append(value); offset += length
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin-dir', type=Path, required=True)
    parser.add_argument('--test-bundle', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--requests', type=Path, default=Path(__file__).with_name('m6-workshop-requests.json'))
    args = parser.parse_args()
    root = args.output_dir.resolve(); root.mkdir(parents=True, exist_ok=False)
    binary = args.bin_dir.resolve(); fixtures = args.fixtures.resolve()
    sources = {n: fixtures / (n + '.dcm') for n in ['gray8', 'gray12', 'rgb8']}
    assert all(p.is_file() for p in sources.values()), 'Run the independent fixture generator first'
    source_hashes = {n: sha(p) for n, p in sources.items()}
    corpus = json.loads(args.requests.read_text())
    records = []; comparisons = []; passed = False; failure = None
    processes = []; logs = []
    for side in ['cli', 'workshop']:
        (root / side).mkdir(); (root / (side + '-settings')).mkdir()
    environment = dict(os.environ)

    def env(side):
        return dict(environment, DICOMKIT_PRINT_TEST_SETTINGS_DIRECTORY=str(root / (side + '-settings')))

    def run(name, argv, expected=0, side='cli', timeout=45):
        actual = [str(binary / argv[0])] + argv[1:]
        completed = subprocess.run(actual, cwd=root, env=env(side), text=True, capture_output=True, timeout=timeout)
        (root / (name + '.stdout.txt')).write_text(completed.stdout)
        (root / (name + '.stderr.txt')).write_text(completed.stderr)
        record = {'name': name, 'argv': actual, 'exit': completed.returncode, 'expectedExit': expected,
                  'stdout': completed.stdout, 'stderr': completed.stderr}
        records.append(record)
        assert completed.returncode == expected, (name, completed.returncode, completed.stdout, completed.stderr)
        return completed

    def launch(name, argv, side='cli'):
        log = (root / (name + '.log')).open('w'); logs.append(log)
        actual = [str(binary / argv[0])] + argv[1:]
        process = subprocess.Popen(actual, cwd=root, env=env(side), stdout=log, stderr=subprocess.STDOUT)
        processes.append(process)
        save(root / (name + '.process.json'), {'argv': actual, 'pid': process.pid})
        return process

    def substitute(text, side, peer_url, peer_ae, job_uid):
        mapping = {'__FIXTURES__': str(fixtures), '__SIDE_OUTPUT__': str(root / side),
                   '__RUN_OUTPUT__': str(root), '__PEER_URL__': peer_url, '__PEER_AE__': peer_ae, '__JOB_UID__': job_uid}
        # Split the trusted corpus before substitution, then quote every literal
        # result. Paths containing shell punctuation cannot become operators.
        argv = shlex.split(text)
        for index, token in enumerate(argv):
            for key, value in mapping.items(): token = token.replace(key, value)
            argv[index] = token
        return argv

    def normalize(value):
        if isinstance(value, dict): return {k: normalize(v) for k, v in value.items() if k not in VOLATILE_JSON_KEYS}
        if isinstance(value, list): return [normalize(v) for v in value]
        if isinstance(value, str):
            for side in ['cli', 'workshop']: value = value.replace(str(root / side), '<SIDE_OUTPUT>')
            return value
        return value

    def raster_records(directory):
        result = []
        for path in sorted(directory.glob('*')):
            if path.suffix.lower() in ['.png', '.tif', '.tiff']:
                with Image.open(path) as image:
                    image.load(); rgba = image.convert('RGBA')
                    result.append({'suffix': path.suffix.lower(), 'size': list(rgba.size),
                                   'rgbaSHA256': hashlib.sha256(rgba.tobytes()).hexdigest(), 'path': str(path)})
            elif path.suffix.lower() == '.pdf':
                data = path.read_bytes()
                assert data.startswith(b'%PDF-') and b'%%EOF' in data[-1024:], str(path)
                result.append({'suffix': '.pdf', 'containerValid': True, 'path': str(path), 'bytes': len(data)})
        return result

    try:
        peer_port = port(); peer_url = 'pacs://127.0.0.1:' + str(peer_port); peer_ae = 'M6CLI'
        peer = launch('cli-peer', ['dicom-printscp', 'serve', '--port', str(peer_port), '--ae-title', peer_ae,
            '--config', str(root / 'cli' / 'absent.json'), '--output', 'none', '--dpi', '25', '--max-pixels', '1024',
            '--duration', '240', '--format', 'json'])
        wait_ready(peer, peer_port)
        seed = run('seed-retained-job', ['dicom-print', 'send', peer_url, str(sources['gray8']), '--aet', 'M6WORKSHOP',
            '--called-aet', peer_ae, '--raw', '--timeout', '5', '--format', 'json'])
        job_uid = json.loads(seed.stdout)['printJobUID']
        save(root / 'endpoint.json', {'url': peer_url, 'aet': peer_ae, 'retainedJobUID': job_uid,
                                     'sameLibraryLoopback': True})
        materialized = []; cli_by_name = {}
        for item in corpus:
            argv = substitute(item['command'], 'workshop', peer_url, peer_ae, job_uid)
            request = dict(item, command=shlex.join(argv))
            for key in ['stopSignalPath', 'readyPath']:
                if key in request: request[key] = request[key].replace('__RUN_OUTPUT__', str(root))
            materialized.append(request)
            if item['comparison'] == 'listener': continue
            control = substitute(item['command'], 'cli', peer_url, peer_ae, job_uid)
            result = run(item['name'] + '-cli', control, item['expectedExit'])
            cli_by_name[item['name']] = result.stdout + result.stderr
        request_path = root / 'requests.json'; save(request_path, materialized)
        workshop_output = root / 'workshop.json'
        workshop_env = dict(env('workshop'), DICOMKIT_M6_WORKSHOP_REQUESTS=str(request_path),
                            DICOMKIT_M6_WORKSHOP_OUTPUT=str(workshop_output))
        harness_log = (root / 'workshop-process.log').open('w'); logs.append(harness_log)
        harness_argv = ['xcrun', 'xctest', '-XCTest',
            'DICOMStudioTests.M6WorkshopExecutionTests/testConfiguredWorkshopActions', str(args.test_bundle.resolve())]
        harness = subprocess.Popen(harness_argv, cwd=root, env=workshop_env, stdout=harness_log, stderr=subprocess.STDOUT)
        processes.append(harness); save(root / 'harness-process.json', {'argv': harness_argv, 'pid': harness.pid})
        ready = root / 'workshop-listener-ready.json'; sent = False; deadline = time.monotonic() + 180
        while harness.poll() is None and time.monotonic() < deadline:
            if ready.exists() and not sent:
                state = json.loads(ready.read_text())
                assert state['name'] == 'scp-serve-quiet-stop' and state['running'] is True
                sent = True
                run('cli-to-workshop-listener', ['dicom-print', 'send', 'pacs://127.0.0.1:' + str(state['port']),
                    str(sources['gray8']), '--aet', 'M6WORKSHOP', '--called-aet', 'M6VM', '--raw', '--format', 'json', '--timeout', '5'])
                (root / 'stop-workshop-listener').write_text('Synthetic sender completed\n')
            time.sleep(.03)
        assert harness.poll() is not None, 'Workshop harness exceeded campaign deadline'
        assert harness.returncode == 0, (root / 'workshop-process.log').read_text()
        assert sent, 'Workshop listener never published active readiness'
        app = {v['name']: v for v in json.loads(workshop_output.read_text())}
        assert len(app) == len(corpus)
        for item in corpus:
            name = item['name']; result = app[name]
            assert result['exit'] == item['expectedExit'] and result['historyCount'] == 1
            assert result['runningAfterCompletion'] is False and result['timedOut'] is False
            body = result['console'].split('\n\n', 1)[-1].strip()
            if item['comparison'] == 'listener':
                assert result['listenerPortWhileActive'] > 0 and 'Stopped by user' in body
                comparisons.append({'name': name, 'kind': 'listener-ready-stop', 'passed': True}); continue
            control = cli_by_name[name].strip()
            if item['comparison'] == 'json':
                lhs, rhs = json_values(body), json_values(control)
                assert lhs and rhs, (name, body, control)
                assert normalize(lhs) == normalize(rhs), (name, normalize(lhs), normalize(rhs))
            elif item['comparison'] == 'error':
                for snippet in item['expectedSnippets']:
                    assert snippet in body and snippet in control, (name, body, control)
            else:
                assert normalize(body) == normalize(control), (name, body, control)
            comparisons.append({'name': name, 'kind': item['comparison'], 'passed': True})

        # Same CLI serve command as the Workshop listener, stopped by max-films
        # rather than the app Stop action; compare the received image rendering.
        receive_port = port()
        control = substitute(next(x['command'] for x in corpus if x['comparison'] == 'listener'), 'cli', peer_url, peer_ae, job_uid)
        control[control.index('--port') + 1] = str(receive_port)
        control += ['--max-films', '1']
        receiver = launch('cli-receiver-control', control)
        wait_ready(receiver, receive_port)
        run('cli-to-cli-receiver-control', ['dicom-print', 'send', 'pacs://127.0.0.1:' + str(receive_port),
            str(sources['gray8']), '--aet', 'M6WORKSHOP', '--called-aet', 'M6VM', '--raw', '--format', 'json', '--timeout', '5'])
        receiver.wait(timeout=15)
        assert receiver.returncode == 0, 'CLI receiver did not finish after one film'
        artifact_records = {}
        for kind, expected_suffixes in [('simulated', {'.tiff', '.pdf'}), ('received', {'.png', '.pdf'})]:
            left = raster_records(root / 'cli' / kind); right = raster_records(root / 'workshop' / kind)
            assert {x['suffix'] for x in left} == expected_suffixes, (kind, left)
            assert {x['suffix'] for x in right} == expected_suffixes, (kind, right)
            def pixels(rows): return sorted((x['suffix'], x['size'], x['rgbaSHA256']) for x in rows if 'rgbaSHA256' in x)
            assert pixels(left) == pixels(right), (kind, left, right)
            artifact_records[kind] = {'cli': left, 'workshop': right, 'rasterPixelEquality': True,
                                      'PDFScope': 'Both complete PDF containers produced; no diagnostic/hardware or PDF raster claim'}
        save(root / 'artifacts.json', artifact_records)
        for side in ['cli', 'workshop']:
            registry = json.loads((root / (side + '-settings') / 'printers.json').read_text())
            assert registry == [], (side, registry)
            assert (root / side / 'printscp.json').is_file()
            assert (root / side / 'simulation-settings.json').is_file()
            assert not (root / side / 'deliberately-missing.dcm').exists()
        assert {n: sha(p) for n, p in sources.items()} == source_hashes
        passed = True
        print(f'M6 Workshop: {len(corpus)} actions, all ten routes, CLI controls and bidirectional loopback passed')
    except BaseException:
        failure = traceback.format_exc()
        raise
    finally:
        for process in reversed(processes): stop(process)
        for log in logs: log.close()
        save(root / 'results.json', {'passed': passed, 'failure': failure, 'cliCases': len(records),
            'workshopRequests': len(corpus), 'comparisons': comparisons, 'records': records,
            'fixtureSHA256': source_hashes, 'binarySHA256': {name: sha(binary / name) for name in ['dicom-print', 'dicom-printscp']},
            'scope': 'Actual CLI and ViewModel actions with synthetic same-library loopback. No packaged GUI or independent-peer claim. PNG/TIFF pixel comparison; PDF container creation only.'})


if __name__ == '__main__': main()
