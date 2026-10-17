#!/usr/bin/env python3
"""Bind a verified CLI archive to its exact tag, source tree and release run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from package_release_cli import verify


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--local', action='store_true', help='Prepare a non-publication receipt without creating a tag')
    args = parser.parse_args()
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', args.tag):
        raise ValueError('Invalid release tag')
    git = lambda *values: subprocess.check_output(['git', *values], text=True).strip()
    commit, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    if git('status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Tracked release inputs must be committed')
    if not args.local and git('rev-parse', args.tag + '^{commit}') != commit:
        raise ValueError('Release tag does not match checked-out source')
    inventory = json.loads(args.inventory.read_text())
    actual = verify(args.archive)
    if any(inventory.get(key) != value for key, value in actual.items()):
        raise ValueError('Inventory does not match verified archive')
    archive_hash = digest(args.archive)
    if inventory.get('archiveSHA256') != archive_hash:
        raise ValueError('Inventory archive digest mismatch')
    receipt = {'schemaVersion': 1, 'tag': args.tag, 'commit': commit, 'tree': tree,
               'localPreparationOnly': args.local,
               'workflowRun': None if args.local else os.environ.get('GITHUB_RUN_ID'),
               'workflowAttempt': None if args.local else os.environ.get('GITHUB_RUN_ATTEMPT'),
               'archive': {'name': args.archive.name, 'sha256': archive_hash, 'bytes': args.archive.stat().st_size},
               'inventorySHA256': digest(args.inventory),
               'packageResolved': json.loads(Path('Package.resolved').read_text()),
               'packageResolvedSHA256': digest(Path('Package.resolved')),
               'scalarQualificationSHA256': digest(Path('Documentation/BoundedInput/DecimalScalarQualificationReceipt.json')),
               'limits': 'Scalar library qualification and release artifacts do not establish application/runtime/bootstrap acceptance.'}
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
