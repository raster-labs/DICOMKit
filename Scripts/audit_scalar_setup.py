#!/usr/bin/env python3
"""Inspect the selected arm64 Release constructors and their direct call closure.

This is a narrow code-generation receipt, not whole-process allocation qualification.
Run after the stabilized Release build. No source or build products are modified.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else 'work/scalar-setup-audit.json')
base = root / '.build/out/Intermediates.noindex/DICOMKit.build/Release'
objects = [base / f'{module}-t.build/Objects-normal/arm64/{name}.o'
           for module, names in [('DICOMCore', ['JLICodec', 'JPEGLSCodec', 'PixelDecodeLimits']),
                                 ('DICOMKit', ['BoundedParsingOptions', 'ParsingOptions'])]
           for name in names]

def command(*args, data=None):
    return subprocess.check_output(args, input=data, text=True)

functions = {}
object_hashes = {}
for path in objects:
    object_hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    symbols = [(int(match[1], 16), match[2])
               for line in command('xcrun', 'nm', '-n', str(path)).splitlines()
               if (match := re.match(r'^([0-9a-f]+)\s+[tT]\s+(\S+)$', line))]
    names = command('xcrun', 'swift-demangle', '--compact',
                    data='\n'.join(symbol for _, symbol in symbols) + '\n').splitlines()
    instructions = [(int(match[1], 16), match[2], match[3])
                    for line in command('xcrun', 'otool', '-tvV', str(path)).splitlines()
                    if (match := re.match(r'^([0-9a-f]{16})\s+(\S+)\s*(.*)$', line))]
    relocations = {}
    in_text = False
    for line in command('xcrun', 'otool', '-rv', str(path)).splitlines():
        if line.startswith('Relocation information'):
            in_text = '(__TEXT,__text)' in line
        if in_text and (match := re.match(r'^([0-9a-f]{8})\s+.*\bBR26\s+False\s+(\S+)', line)):
            relocations[int(match[1], 16)] = match[2]
    starts = sorted(set(address for address, _ in symbols))
    final = max(address for address, _, _ in instructions) + 4
    for (start, symbol), name in zip(symbols, names):
        end = next((address for address in starts if address > start), final)
        body = [item for item in instructions if start <= item[0] < end]
        calls = []
        for address, opcode, operand in body:
            if address in relocations:
                calls.append(relocations[address])
            elif opcode in ['bl', 'b']:
                target = re.match(r'0x([0-9a-f]+)', operand)
                if target and not start <= int(target[1], 16) < end:
                    candidates = [name for location, name in symbols if location == int(target[1], 16)]
                    calls.append(candidates[0] if candidates else 'UNRESOLVED:' + operand)
            elif opcode in ['blr', 'br', 'blraa', 'braa', 'blrab', 'brab']:
                calls.append('INDIRECT:' + opcode + ':' + operand)
        functions[symbol] = {'name': name, 'object': str(path.relative_to(root)),
                             'calls': sorted(set(calls)), 'instructions': body}

selectors = ['static DICOMKit.BoundedParsingOptions.make(',
             'DICOMCore.JLICodec.init(decodingSyntax:',
             'DICOMCore.JPEGLSCodec.init(decodingSyntax:']
roots = [symbol for symbol, function in functions.items()
         if any(selector in function['name'] for selector in selectors)]
assert all(any(selector in functions[symbol]['name'] for symbol in roots)
           for selector in selectors), 'Required Release constructor symbols are missing'
pending = list(roots)
visited = {}
unresolved = []
while pending:
    symbol = pending.pop()
    if symbol in visited:
        continue
    if symbol not in functions:
        unresolved.append(symbol)
        continue
    visited[symbol] = functions[symbol]
    pending.extend(functions[symbol]['calls'])
result = {'scope': 'Selected arm64 Release scalar setup and resolvable direct call closure only',
          'passed': not unresolved, 'objectSHA256': object_hashes, 'roots': roots,
          'functions': visited, 'unresolvedCalls': sorted(set(unresolved)),
          'limits': 'No whole-program heap, Swift runtime, worker/bootstrap or provider acceptance claim.'}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'passed': result['passed'], 'roots': len(roots),
                  'functions': len(visited), 'unresolvedCalls': result['unresolvedCalls']}))
sys.exit(0 if result['passed'] else 1)
