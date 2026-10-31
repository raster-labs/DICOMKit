#!/usr/bin/env python3
"""Reproducible M3 DIMSE CLI gate against the independent synthetic loopback peer.
Requires an already built dicom-query; performs no build or external PACS access.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

# Importing the peer must not leave build artifacts in the source checkout.
sys.dont_write_bytecode = True


def load_peer(path):
    spec = importlib.util.spec_from_file_location('m3_dimse_peer', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    binary = (args.bin_dir / 'dicom-query').resolve()
    if not binary.is_file():
        parser.error('The supplied --bin-dir must contain a built dicom-query')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    capture = output / 'capture'
    if capture.exists():
        parser.error('Use a fresh output directory; capture evidence will not be overwritten')
    capture.mkdir()
    peer_path = Path(__file__).with_name('m3_dimse_capture_peer.py').resolve()
    peer_module = load_peer(peer_path)
    runs = []
    report = {'item': 'NET-04-A', 'binary': str(binary),
              'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'peer_sha256': hashlib.sha256(peer_path.read_bytes()).hexdigest(),
              'synthetic_loopback_only': True, 'runs': runs, 'passed': False}

    def state():
        return json.loads((capture / 'state.json').read_text())

    def run(name, extra, expected=0):
        before = state()
        argv = [str(binary), '127.0.0.1', '--port', str(port), '--aet', 'M3CLI',
                '--called-aet', 'M3SCP', '--timeout', '5', '--format', 'json', '--verbose', *extra]
        result = subprocess.run(argv, capture_output=True, text=True, timeout=20)
        (output / (name + '.stdout.txt')).write_text(result.stdout)
        (output / (name + '.stderr.txt')).write_text(result.stderr)
        after = state()
        record = {'name': name, 'argv': argv, 'exit': result.returncode, 'expected_exit': expected,
                  'associations_before': before['associations'], 'associations_after': after['associations'],
                  'requests_before': before['requests'], 'requests_after': after['requests']}
        runs.append(record)
        assert result.returncode == expected, (record, result.stderr, result.stdout)
        if expected:
            assert after['associations'] == before['associations'], record
            assert after['requests'] == before['requests'], record
            assert 'No query was sent' in result.stderr + result.stdout
            assert 'cannot be matched at' in result.stderr + result.stdout
            assert 'DICOM Query (C-FIND)' not in result.stdout, 'Refusal must precede verbose header'
            return
        assert after['associations'] == before['associations'] + 1, record
        assert after['requests'] == before['requests'] + 1, record
        identifier = capture / f"request-{after['requests']:03}.identifier.bin"
        request = json.loads(identifier.with_suffix('').with_suffix('.json').read_text())
        explicit = request['transferSyntax'] == peer_module.EXPLICIT
        keys = peer_module.decode(identifier.read_bytes(), explicit)
        assert peer_module.serial_keys(keys) == request['keys'], 'Raw bytes and saved JSON differ'
        # JSON result follows the verbose header. It is the first array in stdout.
        start = result.stdout.find('[\n')
        assert start >= 0, result.stdout
        results = json.loads(result.stdout[start:])
        record.update({'result_count': len(results), 'identifier_sha256': hashlib.sha256(identifier.read_bytes()).hexdigest(),
                       'captured_keys': request['keys'], 'results': results})
        return keys, results, result.stdout

    with (output / 'peer.log').open('w') as peer_log:
        peer = subprocess.Popen([sys.executable, '-B', str(peer_path), str(capture), '--seconds', '180'],
                                stdout=peer_log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 5
            while not (capture / 'ready.json').exists():
                assert peer.poll() is None, 'Capture peer failed; inspect peer.log'
                assert time.monotonic() < deadline, 'Capture peer did not become ready'
                time.sleep(.05)
            port = json.loads((capture / 'ready.json').read_text())['port']
            # Control query proves the fixture has both CT and MR studies.
            _, results, _ = run('study-control', ['--level', 'study'])
            assert {row['(0020,000D)'] for row in results} == {'2.25.301', '2.25.302'}
            keys, results, header = run('study-ct', ['--level', 'study', '--modality', 'CT',
                '--study-date', '20260101-20261231', '--patient-name', 'AUDIT*', '--study-description', 'M3*'])
            assert keys[0x00080061]['value'] == 'CT' and 0x00080060 not in keys
            assert keys[0x00080020]['value'] == '20260101-20261231'
            assert keys[0x00100010]['value'] == 'AUDIT*' and keys[0x00081030]['value'] == 'M3*'
            assert [row['(0020,000D)'] for row in results] == ['2.25.301']
            assert 'Modality:' in header and 'Study Date:' in header and 'Patient Name:' in header
            keys, results, header = run('series-ct', ['--level', 'series', '--study-uid', '2.25.301', '--modality', 'CT'])
            assert keys[0x00080060]['value'] == 'CT' and 0x00080061 not in keys
            assert keys[0x0020000D]['value'] == '2.25.301'
            assert [row['(0020,000E)'] for row in results] == ['2.25.301.1']
            assert 'Study Date:' not in header and 'Patient Name:' not in header
            keys, results, header = run('image-valid', ['--level', 'image', '--study-uid', '2.25.301', '--series-uid', '2.25.301.1'])
            assert 0x00080060 not in keys and 0x00080061 not in keys
            assert [row['(0008,0018)'] for row in results] == ['2.25.301.1.1']
            assert 'Modality:' not in header
            run('refuse-image-modality', ['--level', 'image', '--study-uid', '2.25.301',
                '--series-uid', '2.25.301.1', '--modality', 'CT'], 64)
            for name, flag, value in [('date', '--study-date', '20260101-20261231'),
                                     ('description', '--study-description', 'M3*'), ('uid', '--study-uid', '2.25.301')]:
                run('refuse-patient-study-' + name, ['--level', 'patient', flag, value], 64)
            final = state()
            assert final == {'associations': 4, 'requests': 4, 'errors': []}, final
            report['final_peer_state'] = final
            report['passed'] = True
        except Exception as error:
            report['error'] = str(error)
            raise
        finally:
            (capture / 'stop').touch()
            try:
                peer.wait(timeout=5)
            except subprocess.TimeoutExpired:
                peer.terminate()
                peer.wait(timeout=5)
            report['peer_exit'] = peer.returncode
            (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('M3 DIMSE passed: 4 accepted C-FIND requests, correct STUDY/SERIES modality tags and results, matching expressions preserved, 4 refused queries with zero additional associations.')


if __name__ == '__main__':
    main()
