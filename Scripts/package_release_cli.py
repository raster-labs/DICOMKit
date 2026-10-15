#!/usr/bin/env python3
"""Stage and assemble the release CLI archive, including its runtime resources.

Batch tar files preserve executable permissions through upload-artifact. Assembly
refuses an incomplete tool or resource inventory before a release can be created.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ('DICOMKit_DICOMRenderKit.bundle', 'J2KSwift_J2KMetal.bundle',
             'DICOMKit_DICOMDictionary.bundle')


def tool_names():
    workflow = (ROOT / '.github/workflows/release.yml').read_text()
    names = [name for match in re.finditer(r'tools: "([^"]+)"', workflow)
             for name in match[1].split()]
    if len(names) != 36 or len(set(names)) != 36:
        raise ValueError('Release matrix must define exactly 36 distinct CLI tools')
    return names


def bundle_complete(names, bundle):
    prefix = 'bin/' + bundle + '/Contents/'
    return (prefix + 'Info.plist' in names
            and any(name.startswith(prefix + 'Resources/') for name in names))


def stage(products, archive, names):
    if not names or len(set(names)) != len(names) or not set(names) <= set(tool_names()):
        raise ValueError('Unexpected or duplicated batch tools')
    for name in names:
        path = products / name
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError('Missing executable: ' + name)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'w') as target:
        for name in names:
            target.add(products / name, arcname='bin/' + name)
        for name in RESOURCES:
            if (products / name).is_dir():
                target.add(products / name, arcname='bin/' + name)


def verify(archive):
    tools = tool_names()
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = {item.name: item for item in members}
        if len(names) != len(members):
            raise ValueError('Duplicate archive entries')
        for item in members:
            path = PurePosixPath(item.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                    or path.parts[0] != 'bin' or not (item.isfile() or item.isdir())):
                raise ValueError('Unexpected archive member: ' + item.name)
            if len(path.parts) > 1 and path.parts[1] not in tools + list(RESOURCES):
                raise ValueError('Unexpected packaged product: ' + item.name)
        for name in tools:
            item = names.get('bin/' + name)
            if item is None or not item.isfile() or item.size == 0 or not item.mode & 0o111:
                raise ValueError('Missing executable archive member: ' + name)
        files = {name for name, item in names.items() if item.isfile() and item.size > 0}
        for name in RESOURCES:
            if not bundle_complete(files, name):
                raise ValueError('Missing resource bundle: ' + name)
        return {'tools': tools, 'resourceBundles': list(RESOURCES),
                'members': sorted(names), 'executableModesPreserved': True}


def assemble(artifacts, archive):
    batches = sorted(artifacts.glob('cli-binaries-batch-*/staged-cli.tar'))
    if not batches:
        raise ValueError('No staged CLI batch archives found')
    selected = {}
    with contextlib.ExitStack() as stack:
        for path in batches:
            source = stack.enter_context(tarfile.open(path))
            members = source.getmembers()
            by_name = {item.name: item for item in members}
            for name in tool_names():
                key = 'bin/' + name
                if key in by_name:
                    if key in selected:
                        raise ValueError('Duplicate batch executable: ' + name)
                    selected[key] = (source, by_name[key])
            files = {item.name for item in members if item.isfile() and item.size > 0}
            for name in RESOURCES:
                prefix = 'bin/' + name
                if prefix in selected or not bundle_complete(files, name):
                    continue
                for item in members:
                    if item.name == prefix or item.name.startswith(prefix + '/'):
                        selected[item.name] = (source, item)
        for name in tool_names():
            if 'bin/' + name not in selected:
                raise ValueError('Missing batch executable: ' + name)
        for name in RESOURCES:
            if not bundle_complete(set(selected), name):
                raise ValueError('Missing resource bundle: ' + name)
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, 'w:gz', compresslevel=1) as target:
            for name in sorted(selected):
                source, item = selected[name]
                target.addfile(item, source.extractfile(item) if item.isfile() else None)
    inventory = verify(archive)
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    inventory['archiveSHA256'] = digest.hexdigest()
    return inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    stage_parser = commands.add_parser('stage')
    stage_parser.add_argument('--products', type=Path, required=True)
    stage_parser.add_argument('--archive', type=Path, required=True)
    stage_parser.add_argument('--tools', nargs='+', required=True)
    assemble_parser = commands.add_parser('assemble')
    assemble_parser.add_argument('--artifacts', type=Path, required=True)
    assemble_parser.add_argument('--archive', type=Path, required=True)
    verify_parser = commands.add_parser('verify')
    verify_parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'stage':
        stage(args.products, args.archive, args.tools)
        print(json.dumps({'stagedTools': len(args.tools), 'archive': str(args.archive)}))
    elif args.command == 'assemble':
        print(json.dumps(assemble(args.artifacts, args.archive)))
    else:
        print(json.dumps(verify(args.archive)))


if __name__ == '__main__':
    main()
