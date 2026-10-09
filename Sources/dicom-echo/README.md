# dicom-echo

DICOM network testing and diagnostics tool using C-ECHO verification service.

## Overview

`dicom-echo` is a command-line tool for testing DICOM connectivity with PACS servers using the C-ECHO service. This is the simplest DICOM network operation and is primarily used to verify that:

- The PACS server is reachable
- DICOM association can be established
- Application Entity titles are correctly configured
- Network latency and stability

## Usage

```
dicom-echo <host> [--port <port>] --aet <aet> [options]
```

The `<host>` argument accepts a hostname or IP address, optionally with a port suffix (`host:port`). Use `--port` to specify the port separately. If no port is given, the default is 11112.

### Basic C-ECHO

```bash
dicom-echo server:11112 --aet TEST_SCU
```

### Multiple Echo Requests with Statistics

```bash
dicom-echo server:11112 --aet TEST_SCU --count 10 --stats
```

### Verbose Output

```bash
dicom-echo server:11112 --aet TEST_SCU --verbose
```

### Network Diagnostics

```bash
dicom-echo server:11112 --aet TEST_SCU --diagnose
```

## Options

- `<host>` (required): PACS server hostname or IP address, optionally `host:port`
- `--port`: PACS server port (default: 11112; overrides port embedded in `<host>`)
- `--aet` (required): Local Application Entity Title (calling AE)
- `--called-aet`: Remote Application Entity Title (default: ANY-SCP)
- `--count, -c`: Number of echo requests to send (default: 1)
- `--timeout`: Connection timeout in seconds (default: 30)
- `--stats`: Show statistics (min/avg/max round-trip time)
- `--diagnose`: Run comprehensive network diagnostics
- `--verbose, -v`: Show verbose output including connection details

## Examples

### Test connectivity to PACS

```bash
dicom-echo pacs.hospital.com:11112 --aet WORKSTATION --called-aet PACS_SCP
```

### Measure network latency (10 requests)

```bash
dicom-echo pacs.hospital.com:11112 --aet WORKSTATION --count 10 --stats
```

Output:
```
..........
Summary:
  Sent: 10
  Successful: 10
  Failed: 0
  Success rate: 100.0%

Round-trip time statistics:
  Min: 0.023s
  Avg: 0.028s
  Max: 0.045s
```

### Full network diagnostics

```bash
dicom-echo pacs.hospital.com:11112 --aet WORKSTATION --diagnose
```

Output:
```
Running DICOM network diagnostics...

Test 1: Basic C-ECHO connectivity
  Testing connection to pacs.hospital.com:11112...
  ✓ Basic connectivity: PASS
    Round-trip time: 0.025s

Test 2: Connection stability (5 requests)
  [1/5] ✓ RTT: 0.024s
  [2/5] ✓ RTT: 0.026s
  [3/5] ✓ RTT: 0.023s
  [4/5] ✓ RTT: 0.027s
  [5/5] ✓ RTT: 0.025s
  Connection stability: 5/5 successful
  RTT min/avg/max/stddev: 0.023/0.025/0.027/0.001s

Test 3: Association parameters
  Implementation Class UID: 1.2.826.0.1.3680043.10.511.3.0.5.0
  Implementation Version: DICOMKIT_001
  SOP Class: Verification (1.2.840.10008.1.1)
  Transfer Syntaxes: Explicit VR Little Endian, Implicit VR Little Endian

Diagnostics complete.
Result: All tests PASSED ✓
```

## Exit Codes

- `0`: All echo requests succeeded (C-ECHO status Success, `0000`)
- `1`: One or more echo requests failed (a non-Success status per PS3.7 9.1.5.1.4, or a network error)
- `64`: Invalid arguments (usage error, e.g. `--count 0`)

## Features

- **Simple connectivity testing**: Single C-ECHO request with success/failure result
- **Latency measurement**: Multiple requests with min/avg/max statistics
- **Network diagnostics**: Comprehensive testing of connectivity and stability
- **Verbose output**: Detailed connection information for troubleshooting
- **Custom timeouts**: Configurable timeout for different network conditions
- **Custom AE titles**: Support for custom calling and called AE titles

## Technical Details

- Uses DICOM Verification Service Class (C-ECHO)
- SOP Class UID: 1.2.840.10008.1.1
- Supports both Explicit VR Little Endian and Implicit VR Little Endian transfer syntaxes
- Round-trip time includes association establishment, C-ECHO exchange, and association release
- Standard deviation calculation for connection stability assessment

## Related Tools

- `dicom-query`: Query DICOM servers (C-FIND)
- `dicom-send`: Send DICOM files to PACS (C-STORE)
- `dicom-retrieve`: Retrieve studies from PACS (C-MOVE/C-GET)

## References

- DICOM PS3.4 Annex A - Verification Service Class
- DICOM PS3.7 Section 9.1.5 - C-ECHO Service
