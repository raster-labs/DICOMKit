#!/usr/bin/env python3
"""Independent decimal oracle and cold/hot allocation checks for the Release probe.

Usage: python3 Scripts/qualify_decimal_scalar.py PROBE OUTPUT.json
The probe must link the actual package Release objects, not a rewritten parser.
Expected values use Decimal's exact integer ratio and a binary search over IEEE
representable values; this deliberately differs from the production division.
"""
import decimal
import hashlib
import json
import random
import re
import subprocess
import sys
from pathlib import Path

GRAMMAR = re.compile(rb"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")
MAX = 0x7FEFFFFFFFFFFFFF


def ratio(bits):
    if bits == MAX + 1:
        return 1 << 1024, 1  # conceptual next value at the overflow midpoint
    exponent, fraction = bits >> 52, bits & ((1 << 52) - 1)
    coefficient = fraction if exponent == 0 else fraction | (1 << 52)
    power = -1074 if exponent == 0 else exponent - 1075
    return (coefficient << power, 1) if power >= 0 else (coefficient, 1 << -power)


def expected(raw):
    if len(raw) > 16:
        return 2, 0
    stripped = raw.strip(b" ")
    if not stripped:
        return 1, 0
    if not GRAMMAR.fullmatch(stripped):
        return 3, 0
    value = decimal.Decimal(stripped.decode("ascii"))
    sign = (1 << 63) if value.is_signed() else 0
    if value.is_zero() or value.adjusted() < -325:
        return 0, sign
    if value.adjusted() > 309:
        return 4, 0
    n, d = abs(value).as_integer_ratio()
    lo, hi = 0, MAX + 1
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        a, b = ratio(mid)
        if a * d <= n * b:
            lo = mid
        else:
            hi = mid
    a, b = ratio(lo)
    c, e = ratio(hi)
    delta = 2 * n * b * e - d * (a * e + c * b)
    chosen = hi if delta > 0 or (delta == 0 and lo & 1) else lo
    return (4, 0) if chosen > MAX else (0, sign | chosen)


def check(raw, result):
    status, bits = expected(raw)
    assert result["status"] == status and int(result["bits"], 16) == bits, (raw, result, status, hex(bits))
    assert result["allocations"] == result["mappings"] == 0 and result["stable"] == 1, (raw, result)


def main():
    probe, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    cold = [b"", b" " * 16, b" " * 17, b"+", b"1e+", b"1\\2", b"1\0", b"0x1p2",
            b"0e9999999999999", b"-0", b"1e-999999999999", b"1e309", b"1e308",
            b"9007199254740993", b"9007199254740995", b"9999999999999999",
            b"2.470328229e-324", b"2.470328230e-324", b"-2.470328230e-324",
            b"22250738585e-318", b"22250738586e-318", b"179769313486e297", b"179769313487e297",
            b"+.5E-2", b" 1.25 ", b"1e-339", b"-5e-324"]
    control = json.loads(subprocess.check_output([probe, "--control"], text=True))
    assert control["allocations"] > 0 and control["mappings"] > 0, control
    cold_results = []
    for raw in cold:
        result = json.loads(subprocess.check_output([probe, raw.hex(), "400"], text=True))
        check(raw, result)
        cold_results.append({"hex": raw.hex(), **result})
    rng = random.Random(0xD1C05)
    corpus = list(cold)
    for exponent in range(-340, 310):
        for coefficient in [1, 17, 9999999999]:
            corpus.append(f"{coefficient}e{exponent}".encode())
    for _ in range(8000):
        digits = str(rng.randrange(10 ** rng.randrange(1, 17)))
        if rng.randrange(2):
            pos = rng.randrange(len(digits) + 1)
            digits = digits[:pos] + "." + digits[pos:]
        if rng.randrange(4):
            digits += rng.choice(["e", "E"]) + rng.choice(["", "+"] if rng.randrange(2) else ["-"]) + str(rng.randrange(450))
        corpus.append((rng.choice(["", "+", "-"]) + digits).encode())
    for _ in range(3000):
        corpus.append(bytes(rng.randrange(256) for _ in range(rng.randrange(20))))
    for byte in range(256):
        corpus.extend([bytes([byte, 49]), bytes([49, byte])])
    data = "".join(raw.hex() + "\n" for raw in corpus)
    results = subprocess.check_output([probe], input=data, text=True).splitlines()
    assert len(results) == len(corpus)
    counts = {}
    for raw, row in zip(corpus, results):
        result = json.loads(row)
        check(raw, result)
        counts[str(result["status"])] = counts.get(str(result["status"]), 0) + 1
    receipt = {"passed": True, "oracle": "Exact Decimal ratio; independent binary search of IEEE values and integer midpoint comparison",
               "coldProcesses": len(cold), "coldAndHotCalls": len(cold) * 400,
               "corpusCases": len(corpus), "corpusCalls": len(corpus) * 4, "statusCounts": counts,
               "roundingModes": ["nearest", "down", "up", "towardZero"],
               "allocationControl": control, "coldResults": cold_results,
               "probeSHA256": hashlib.sha256(probe.read_bytes()).hexdigest(),
               "corpusSHA256": hashlib.sha256(data.encode()).hexdigest(),
               "limits": "Counters cover calls after process/runtime loading and byte preparation; use direct-call audit to exclude Swift allocation/runtime paths. Caller stack admission and whole-worker bootstrap are separate."}
    output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({key: value for key, value in receipt.items() if key != "coldResults"}))


if __name__ == "__main__":
    main()
