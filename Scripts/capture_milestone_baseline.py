#!/usr/bin/env python3
"""Capture source/audit contracts without building or running a DICOM operation.

Run from any directory. NEMA sources stay external; only hashes and URLs enter
the snapshot. Optional cached help is explicitly historical binary evidence.
"""
import argparse
import hashlib
import importlib.util
import json
import platform
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / 'Scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=True)
    return result.stdout.strip()


def source_identity():
    paths = ['Sources', 'Tests', 'Package.swift', 'DICOMStudio.xcodeproj']
    return {
        'git_head_at_capture': command('git', 'rev-parse', 'HEAD'),
        'branch': command('git', 'branch', '--show-current'),
        'tracked_source_tree_objects': {
            p: command('git', 'rev-parse', 'HEAD:' + p) for p in paths
        },
        'uncommitted_product_paths': command('git', 'status', '--porcelain=v1', '--', *paths).splitlines(),
        'swift_source_files': len(list((ROOT / 'Sources').rglob('*.swift'))),
        'swift_test_files': len(list((ROOT / 'Tests').rglob('*.swift'))),
    }


def build_inputs():
    patterns = [
        'Package.swift', 'Package.resolved',
        'DICOMStudio.xcodeproj/project.pbxproj',
        'DICOMStudio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
        'DICOMStudio.xcodeproj/xcshareddata/xcschemes/*.xcscheme',
        '.github/workflows/ci.yml', '.github/workflows/dicom-studio-ci.yml',
        '.github/scripts/setup-stable-swift.sh', '.github/scripts/run-focused-tests.sh',
    ]
    files = sorted({p for pattern in patterns for p in ROOT.glob(pattern) if p.is_file()})
    pbx = (ROOT / 'DICOMStudio.xcodeproj/project.pbxproj').read_text()
    setting_names = ['SWIFT_VERSION', 'MACOSX_DEPLOYMENT_TARGET', 'SDKROOT',
                     'PRODUCT_BUNDLE_IDENTIFIER', 'PRODUCT_NAME',
                     'ENABLE_APP_SANDBOX', 'CODE_SIGN_ENTITLEMENTS', 'SUPPORTED_PLATFORMS']
    return {
        'files_sha256': {str(p.relative_to(ROOT)): sha(p) for p in files},
        'root_package_resolved_present': (ROOT / 'Package.resolved').exists(),
        'declared_xcode_settings': {
            key: sorted(set(re.findall(r'\b' + key + r'\s*=\s*([^;]+);', pbx)))
            for key in setting_names
        },
        'swift_tools_version': (ROOT / 'Package.swift').read_text().splitlines()[0],
        'qualification': 'Declared source settings only; no build, dependency resolution or resolved Xcode setting query was performed.',
    }


def standards(directory):
    manifest = directory / 'manifest.json'
    expected = {row['file']: row for row in json.loads(manifest.read_text())} if manifest.exists() else {}
    rows = []
    for path in sorted(directory.glob('part*_2026a.xml')):
        digest = sha(path)
        if path.name in expected and digest != expected[path.name]['sha256']:
            raise ValueError('Frozen standard hash mismatch: ' + path.name)
        number = re.fullmatch(r'part(\d+)_2026a\.xml', path.name).group(1)
        rows.append({'file': path.name, 'sha256': digest, 'bytes': path.stat().st_size,
                     'url': f'https://dicom.nema.org/medical/dicom/2026a/source/docbook/part{number}/part{number}.xml'})
    required = {3, 4, 5, 6, 7, 10, 11, 15, 16, 18, 19}
    present = {int(re.search(r'part(\d+)', r['file']).group(1)) for r in rows}
    if not required <= present:
        raise ValueError('Missing frozen standard parts: ' + str(sorted(required - present)))
    return rows


def fixtures(path):
    document = json.loads(path.read_text())
    rows = []
    for item in document['fixtures']:
        data = bytes.fromhex(item['bytes_hex'])
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('Synthetic fixture hash mismatch: ' + item['name'])
        rows.append({key: item[key] for key in ['name', 'purpose', 'sha256']})
    return {'manifest': str(path.relative_to(ROOT)), 'manifest_sha256': sha(path),
            'qualification': document['qualification'], 'fixtures': rows}


def cached_help(directory):
    if directory is None:
        return {'status': 'Not supplied; not executed by this capture'}
    roots = json.loads((directory / 'help-results.json').read_text())
    recursive = json.loads((directory / 'recursive-help-results.json').read_text())
    return {
        'status': 'Reused historical cached-binary evidence; not rerun by this capture',
        'source_equivalence': 'Not established for the cached binaries; no fresh-build claim',
        'root_help_results': roots, 'recursive_help_results': recursive,
        'help_logs_sha256': {p.name: sha(p) for p in sorted(directory.glob('*-help.txt'))},
    }


def capture(args):
    dc, ds = load('diff_cli'), load('diff_studio')
    active = dc.active_tools()
    tools = []
    for tool in active:
        files, options, outputs, commands = dc.surface(tool)
        tools.append({
            'tool': tool, 'source_files_sha256': {
                'Sources/' + tool + '/' + name: hashlib.sha256(text.encode()).hexdigest()
                for name, text in sorted(files.items())
            },
            'source_declared_commands': commands,
            'declarations': [{k: option[k] for k in ['file', 'line', 'kind', 'var', 'names', 'type', 'default']}
                             for option in options],
        })
    ws = ds.workshop_surface()
    inventory = {p: {'group': g, 'tier': t} for p, (g, t) in sorted(ds.FILES.items())}
    doc = {
        'schema_version': 1, 'captured_at_utc': datetime.now(timezone.utc).isoformat(),
        'purpose': 'M0 reproducible source and audit baseline; not product certification',
        'source': source_identity(), 'build_inputs': build_inputs(),
        'audit_tools_sha256': {str(p.relative_to(ROOT)): sha(p)
                               for p in sorted(HERE.glob('*.py'))
                               if p.name.startswith(('diff_', 'test_', 'capture_milestone_'))
                               or p.name in ['cli_contracts.py', 'nema_docbook.py']},
        'host': {'system': platform.system(), 'release': platform.release(),
                 'machine': platform.machine(), 'python': platform.python_version()},
        'standards': standards(args.nema), 'synthetic_fixtures': fixtures(args.fixtures),
        'cli': {'enabled_products': active,
                'source_only_products': sorted(set(dc.source_tools()) - set(active)),
                'tools': tools,
                'limits': 'Source declaration extraction is not command registration, parser, protocol or runtime conformance proof.'},
        'studio': {'file_inventory': inventory,
                   'workshop_tool_mapping': ds.WORKSHOP_TOOLS,
                   'workshop_parameters': ws,
                   'limits': 'Static inventory and source-extracted forms only; packaged GUI qualification is not executed in M0.'},
        'cached_help': cached_help(args.cached_help),
    }
    if doc['source']['uncommitted_product_paths']:
        raise ValueError('M0 source baseline requires product paths unchanged')
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + '\n')
    print(f"Captured {len(active)} enabled CLI products, {len(ws)} Workshop entries, "
          f"{len(inventory)} Studio source entries; no product execution.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nema', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, default=ROOT / 'Scripts/audit_fixtures/m0/fixtures.json')
    parser.add_argument('--cached-help', type=Path)
    capture(parser.parse_args())
