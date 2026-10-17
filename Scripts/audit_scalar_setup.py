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
decimal_mode = len(sys.argv) > 1 and sys.argv[1] == '--decimal-scalar'
arguments = sys.argv[2:] if decimal_mode else sys.argv[1:]
output = Path(arguments[0] if arguments else 'work/scalar-setup-audit.json')
base = root / '.build/out/Intermediates.noindex/DICOMKit.build/Release'
objects = [base / f'{module}-t.build/Objects-normal/arm64/{name}.o'
           for module, names in [('DICOMCore', ['JLICodec', 'JPEGLSCodec', 'PixelDecodeLimits']),
                                 ('DICOMKit', ['BoundedParsingOptions', 'ParsingOptions'])]
           for name in names]
if decimal_mode:
    # Second argument is the test-only C-callable Swift wrapper object.
    objects = [base / 'DICOMCore-t.build/Objects-normal/arm64/DICOMDecimalString+Scalar.o',
               Path(arguments[1]).resolve()]

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
        if in_text and (match := re.match(r'^([0-9a-f]{8})\s+.*\bBR(?:26|19|14)\s+False\s+(\S+)', line)):
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
            elif opcode in ['bl', 'b', 'cbz', 'cbnz', 'tbz', 'tbnz'] or opcode.startswith('b.'):
                target = re.search(r'(?:^|,\s*)0x([0-9a-f]+)(?:\s|$)', operand)
                if not target:
                    calls.append('UNPARSED:' + opcode + ':' + operand)
                elif not start <= int(target[1], 16) < end:
                    candidates = [name for location, name in symbols if location == int(target[1], 16)]
                    calls.append(candidates[0] if candidates else 'UNRESOLVED:' + opcode + ':' + operand)
            elif opcode in ['blr', 'br', 'blraa', 'braa', 'blrab', 'brab', 'blraaz', 'braaz', 'blrabz', 'brabz']:
                calls.append('INDIRECT:' + opcode + ':' + operand)
        functions[symbol] = {'name': name, 'object': str(path.relative_to(root)),
                             'calls': sorted(set(calls)), 'instructions': body}

selectors = ['static DICOMKit.BoundedParsingOptions.make(',
             'DICOMCore.JLICodec.init(decodingSyntax:',
             'DICOMCore.JPEGLSCodec.init(decodingSyntax:']
if decimal_mode:
    selectors = ['static DICOMCore.DICOMDecimalString.parseScalar(',
                 'decimalScalarProbe(', 'dicom_decimal_scalar_probe']
roots = [symbol for symbol, function in functions.items()
         if any(selector in function['name'] for selector in selectors)]
assert all(any(selector in functions[symbol]['name'] for symbol in roots)
           for selector in selectors), 'Required Release constructor symbols are missing'
pending = list(roots)
visited = {}
unresolved = []
terminal_guards = []
while pending:
    symbol = pending.pop()
    if symbol in visited:
        continue
    if symbol not in functions:
        if decimal_mode and symbol == '___stack_chk_fail':
            terminal_guards.append(symbol)
            continue
        unresolved.append(symbol)
        continue
    visited[symbol] = functions[symbol]
    pending.extend(functions[symbol]['calls'])
result = {'scope': 'Selected arm64 Release scalar setup and resolvable direct call closure only',
          'passed': not unresolved, 'objectSHA256': object_hashes, 'roots': roots,
          'functions': visited, 'unresolvedCalls': sorted(set(unresolved)),
          'terminalStackCorruptionGuards': sorted(set(terminal_guards)),
          'limits': 'No whole-program heap, Swift runtime, worker/bootstrap or provider acceptance claim.'}
if decimal_mode:
    # The qualified emission uses fixed immediate stack frames only. Reject a
    # future dynamic stack adjustment instead of silently reusing this bound.
    frames = {}
    for symbol, function in visited.items():
        frame = 0
        for _, opcode, operand in function['instructions']:
            if opcode == 'sub' and operand.startswith('sp,'):
                match = re.fullmatch(r'sp, sp, #(0x[0-9a-f]+|[0-9]+)', operand)
                assert match, ('Dynamic stack adjustment', function['name'], operand)
                frame += int(match[1], 0)
            elif opcode in ['stp', 'str'] and '[sp,' in operand and operand.endswith('!'):
                match = re.search(r'\[sp, #-(0x[0-9a-f]+|[0-9]+)\]!', operand)
                assert match, ('Unknown stack pre-index', function['name'], operand)
                frame += int(match[1], 0)
            elif opcode in ['mov', 'and'] and operand.startswith('sp,'):
                raise AssertionError(('Unknown stack write', function['name'], operand))
        frames[symbol] = frame

    def path_stack(symbol, ancestors=()):
        assert symbol not in ancestors, 'Recursive scalar call path'
        return frames[symbol] + max([0] + [path_stack(callee, ancestors + (symbol,))
                                         for callee in visited[symbol]['calls'] if callee in visited])

    result['fixedFrameBytes'] = {visited[symbol]['name']: size for symbol, size in frames.items()}
    result['maximumKnownCallPathStackBytes'] = max(path_stack(symbol) for symbol in roots)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'passed': result['passed'], 'roots': len(roots),
                  'functions': len(visited), 'unresolvedCalls': result['unresolvedCalls']}))
sys.exit(0 if result['passed'] else 1)
