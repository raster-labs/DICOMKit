"""Regenerate synthetic CharLS fixture constants without replacing regression tests.

Run from the repository root with Documentation/Compression/oracle-requirements.txt.
No patient data is used and the external codec is never a runtime dependency.
"""
from pathlib import Path
import base64
import re

import numpy as np
import jpeg_ls


def fixture(bits, values):
    samples = np.tile(np.array(values, dtype='<u2'), 16).reshape(8, 16)
    encoded = bytes(jpeg_ls.encode_pixel_data(
        samples.tobytes(), rows=8, columns=16, samples_per_pixel=1, bits_stored=bits))
    assert np.array_equal(jpeg_ls.jlsread(encoded), samples)
    return base64.b64encode(encoded).decode()


fixtures = {
    'low': fixture(16, [0, 44, 255, 1024, 2047, 2048, 4094, 4095]),
    'high': fixture(16, [0, 1, 4095, 4096, 32767, 32768, 65534, 65535]),
    'narrow': fixture(12, [0, 44, 255, 1024, 2047, 2048, 4094, 4095]),
}
path = Path('Tests/DICOMCoreTests/JPEGLSPrecisionRecoveryTests.swift')
source = path.read_text()
for name, value in fixtures.items():
    source, count = re.subn(rf'private let {name} = "[^"]+"',
                            f'private let {name} = "{value}"', source)
    assert count == 1, f'Expected one {name} fixture constant'
path.write_text(source)
