# dicom-gateway

Bridge DICOM with other healthcare standards (HL7 v2, HL7 FHIR, IHE profiles) for interoperability and integration with broader healthcare IT systems.

## Features

### Protocol Support
- **HL7 v2**: Parse and generate HL7 v2 messages (ADT, ORM, ORU)
- **HL7 FHIR**: Convert DICOM to FHIR resources (ImagingStudy, Patient, Practitioner, DiagnosticReport)
- **Bidirectional Conversion**: DICOM ↔ HL7, DICOM ↔ FHIR
- **Batch Processing**: Convert multiple files at once

### Conversion Modes

#### DICOM to HL7
- Extract demographics, study info for HL7 messages
- Support ADT (Admission/Discharge/Transfer) messages
- Support ORM (Order Message) for imaging orders
- Support ORU (Observation Result) for study results

#### HL7 to DICOM
- Populate DICOM tags from HL7 messages
- Support patient demographics (PID segment)
- Support order information (ORC, OBR segments)
- Template-based conversion for existing DICOM files

#### DICOM to FHIR
- Create FHIR ImagingStudy from DICOM studies
- Generate Patient resources from demographics
- Create Practitioner resources from referring physicians
- Generate DiagnosticReport resources

#### FHIR to DICOM
- Populate DICOM from FHIR ImagingStudy
- Extract patient data from FHIR Patient resources
- Template-based conversion

## Installation

```bash
# Build from source
swift build -c release

# Or use with Swift Package Manager
swift package install
```

## Usage

### DICOM to HL7 Conversion

```bash
# Convert DICOM to HL7 ADT message
dicom-gateway dicom-to-hl7 study.dcm --output study.hl7 --message-type ADT

# Convert to ORM (Order Message)
dicom-gateway dicom-to-hl7 study.dcm --output order.hl7 --message-type ORM

# Convert to ORU (Observation Result)
dicom-gateway dicom-to-hl7 study.dcm --output result.hl7 --message-type ORU

# Specify ADT event type
dicom-gateway dicom-to-hl7 study.dcm --output admit.hl7 --message-type ADT --event-type A01

# Verbose output
dicom-gateway dicom-to-hl7 study.dcm --output study.hl7 -v
```

### HL7 to DICOM Conversion

```bash
# Convert HL7 to DICOM: --template is required
dicom-gateway hl7-to-dicom message.hl7 --template template.dcm --output study.dcm

# Verbose output
dicom-gateway hl7-to-dicom message.hl7 --template template.dcm --output study.dcm -v
```

`--template` is required (exit 1 without it). An HL7 message carries no image; without a
template the output would claim Secondary Capture Image Storage with no Image Pixel Module and no
SC Image Module, both Mandatory in the Secondary Capture Image IOD (PS3.3 2026a Table A.8-1).
A template whose SOP Class is an image Storage SOP Class but which has no Pixel Data is refused
for the same reason.

### DICOM to FHIR Conversion

```bash
# Convert to FHIR ImagingStudy (default)
dicom-gateway dicom-to-fhir study.dcm --output study.json

# Convert to Patient resource
dicom-gateway dicom-to-fhir study.dcm --output patient.json --resource Patient

# Convert to Practitioner resource
dicom-gateway dicom-to-fhir study.dcm --output practitioner.json --resource Practitioner

# Convert to DiagnosticReport
dicom-gateway dicom-to-fhir study.dcm --output report.json --resource DiagnosticReport

# Pretty-print JSON
dicom-gateway dicom-to-fhir study.dcm --output study.json --pretty

# Output to stdout
dicom-gateway dicom-to-fhir study.dcm --resource ImagingStudy
```

### FHIR to DICOM Conversion

```bash
# Convert FHIR ImagingStudy to DICOM: --template is required
dicom-gateway fhir-to-dicom imaging-study.json --template template.dcm --output study.dcm

# Patient resource into a template
dicom-gateway fhir-to-dicom patient.json --template template.dcm --output study.dcm

# Verbose output
dicom-gateway fhir-to-dicom imaging-study.json --template template.dcm --output study.dcm -v
```

`--template` is required, as for `hl7-to-dicom` (PS3.3 2026a Table A.8-1).

### Batch Conversion

```bash
# Batch convert DICOM to HL7
dicom-gateway batch dicom-to-hl7 "studies/*.dcm" --output hl7-messages/

# Batch convert DICOM to FHIR ImagingStudy
dicom-gateway batch dicom-to-fhir "studies/*.dcm" --output fhir-resources/

# Batch convert to FHIR Patient resources
dicom-gateway batch dicom-to-fhir "studies/*.dcm" --output patients/ --type Patient

# Verbose batch conversion
dicom-gateway batch dicom-to-fhir "studies/*.dcm" --output fhir/ -v
```

## HL7 v2 Message Types

### ADT (Admission/Discharge/Transfer)
- **A01**: Admit/visit notification
- **A02**: Transfer a patient
- **A03**: Discharge/end visit
- **A04**: Register a patient
- **A05**: Pre-admit a patient

### ORM (Order Message)
- New imaging orders
- Includes patient demographics, order details, procedure information

### ORU (Observation Result)
- Imaging study results
- Includes observations, measurements, image counts

## FHIR Resource Types

### ImagingStudy
- Study-level information from DICOM
- Study UID, date, time, modality
- Number of series and instances
- Patient reference

### Patient
- Patient demographics from DICOM
- Patient ID, name, birth date, gender
- Identifier mappings

### Practitioner
- Referring physician information
- Name extracted from DICOM

### DiagnosticReport
- Study as a diagnostic report
- Code, effective date/time
- Patient reference

## Data Mapping

### DICOM to HL7 ADT
```
DICOM Tag                    → HL7 Segment.Field
─────────────────────────────────────────────────
Patient ID (0010,0020)            → PID-2
Patient's Name (0010,0010)        → PID-5
Patient's Birth Date (0010,0030)  → PID-7
Patient's Sex (0010,0040)         → PID-8
Accession Number (0008,0050)      → PV1-19
```

### HL7 v2 to DICOM (`hl7-to-dicom`)
```
HL7 Segment.Field   → DICOM Attribute (VR)
─────────────────────────────────────────────────
PID-3 CX.1          → Patient ID (0010,0020) LO
PID-3 CX.4          → Issuer of Patient ID (0010,0021) LO
PID-5 XPN           → Patient's Name (0010,0010) PN — family^given^middle^prefix^suffix
PID-7               → Patient's Birth Date (0010,0030) DA — YYYYMMDD only, else empty
PID-8               → Patient's Sex (0010,0040) CS — M, F, O; U → empty
ORC-2 EI.1          → Accession Number (0008,0050) SH — warning above 16 characters
OBR-3 EI.1          → Study Instance UID (0020,000D) — only when a valid UID
OBR-4.1 / OBR-4.2   → Modality (0008,0060) / Study Description (0008,1030)
OBR-7               → Study Date (0008,0020) DA, Study Time (0008,0030) TM
```
Values follow PS3.5 2026a Table 6.2-1 and PS3.3 2026a Table C.7-1. The values are written into
the `--template` data set, which is required: a demographics-only data set claiming Secondary
Capture Image Storage with no pixel data is not a Secondary Capture Image IOD (PS3.3 2026a
Table A.8-1), so it is no longer written.

### DICOM to HL7 ORM
```
DICOM Tag                    → HL7 Segment.Field
─────────────────────────────────────────────────
Accession Number (0008,0050) → ORC-2, OBR-2
Study Instance UID           → ORC-3, OBR-3
Study Description (0008,1030)→ OBR-4
Modality (0008,0060)         → OBR-4
Study Date/Time              → OBR-7
```

### DICOM to FHIR ImagingStudy
```
DICOM Tag                      → FHIR Element
───────────────────────────────────────────────
Study Instance UID (0020,000D) → identifier.value
Study Date/Time (0008,0020/30) → started
Modality (0008,0060)           → modality.code
Study Description (0008,1030)  → description
Number of Series (0020,1206)   → numberOfSeries
Number of Instances (0020,1208)→ numberOfInstances
Patient ID (0010,0020)         → subject.reference
```

## Examples

### Complete HL7 ADT Message

```hl7
MSH|^~\&|DICOMKit|IMAGING|HIS|HOSPITAL|20260215120000||ADT^A01|MSG001|P|2.5
EVN|A01|20260215120000
PID||12345||DOE^JOHN^MICHAEL||19800115|M
PV1||O|||||||||||||||||||ACC12345
```

### Complete FHIR ImagingStudy Resource

```json
{
  "resourceType": "ImagingStudy",
  "status": "available",
  "identifier": [
    {
      "system": "urn:dicom:uid",
      "value": "urn:oid:1.2.840.113619.2.62.994044785528.114289542805"
    }
  ],
  "started": "2026-02-15T12:00:00",
  "modality": [
    {
      "system": "http://dicom.nema.org/resources/ontology/DCM",
      "code": "CT"
    }
  ],
  "description": "CT Chest with Contrast",
  "numberOfSeries": 3,
  "numberOfInstances": 150,
  "subject": {
    "reference": "Patient/12345"
  }
}
```

## Error Handling

The tool provides clear error messages for common issues:

- **Invalid input file**: File not found or unreadable
- **Parsing failed**: Malformed HL7 or FHIR data
- **Conversion failed**: Missing required DICOM tags
- **Invalid protocol**: Unsupported message or resource type

Use `--verbose` flag for detailed error information and conversion progress.

## Development

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test
```

### File Structure

```
dicom-gateway/
├── main.swift                   # CLI interface
├── GatewayTypes.swift           # Common types and errors
├── HL7Parser.swift              # HL7 v2 parsing and generation
├── DICOMToHL7Converter.swift    # DICOM → HL7 conversion
├── HL7ToDICOMConverter.swift    # HL7 → DICOM conversion
├── FHIRConverter.swift          # DICOM ↔ FHIR conversion
└── README.md                    # This file
```

## Standards Compliance

- **DICOM**: the DICOM side of the mappings (PN, DA, TM, Patient's Sex, UIDs) is checked against DICOM 2026a; HL7 v2, FHIR and IHE are not NEMA standards
- **HL7 v2.5**: Supports HL7 v2.5 message structure
- **FHIR R4**: Generates FHIR R4 resources
- **IHE**: Foundation IHE profile support (PDI, XDS-I, PIX, PDQ)

## IHE Profile Support (Phase D)

### Supported Profiles

- **PDI (Portable Data for Imaging)**: DICOMDIR validation and media export
- **XDS-I (Cross-Enterprise Document Sharing for Imaging)**: Metadata extraction for registry
- **PIX (Patient Identifier Cross-Referencing)**: Cross-domain patient ID mapping
- **PDQ (Patient Demographics Query)**: Demographics query generation

### IHE Profile Validation

```bash
# Validate DICOM file against PDI profile
dicom-gateway validate-profile study.dcm --profile PDI

# Extract XDS-I metadata
dicom-gateway extract-xds study.dcm --output metadata.json

# Create PIX query
dicom-gateway create-pix-query --patient-id 12345 --source-domain HOSPITAL
```

## Custom Mapping Engine (Phase D)

### Mapping Configuration

Create custom field mappings with transformations:

```json
{
  "name": "Custom DICOM to HL7 Mapping",
  "sourceFormat": "dicom",
  "targetFormat": "hl7",
  "rules": [
    {
      "source": "PatientID",
      "target": "PID-2",
      "required": true
    },
    {
      "source": "PatientName",
      "target": "PID-5",
      "transform": "uppercase",
      "required": true
    },
    {
      "source": "PatientBirthDate",
      "target": "PID-7",
      "transform": "date_format"
    }
  ],
  "includeUnmapped": true
}
```

### Using Custom Mappings

```bash
# Apply custom mapping
dicom-gateway dicom-to-hl7 study.dcm \
  --output message.hl7 \
  --mapping custom-mapping.json

# Create mapping configuration
dicom-gateway create-mapping \
  --name "Hospital A Integration" \
  --source dicom \
  --target hl7 \
  --output mapping.json
```

### Available Transformations

- `uppercase` / `lowercase`: Case conversion
- `trim`: Remove whitespace
- `date_format`: Convert date formats
- `split_name`: Extract name components
- `combine_name`: Join name components
- `extract_first` / `extract_last`: Extract first/last word
- `remove_spaces`: Remove all spaces
- `pad_left` / `pad_right`: Add padding
- `substring`: Extract substring

## Gateway Modes (Phase C)

### Listener Mode

Listen for HL7 messages and forward to PACS:

```bash
# Start HL7 listener
dicom-gateway listen \
  --protocol hl7 \
  --port 2575 \
  --forward pacs://server:11112 \
  --message-types ADT,ORM \
  --verbose

# Listen for all message types
dicom-gateway listen \
  --port 2575 \
  --forward pacs://server:11112
```

**Features:**
- Real-time HL7 message processing
- Automatic ACK generation
- Message type filtering
- Conversion to DICOM and forwarding
- Multi-client support

### Forwarder Mode

Forward DICOM events as HL7/FHIR:

```bash
# Forward to HL7 destination
dicom-gateway forward \
  --listen-port 11112 \
  --forward-hl7 hl7://server:2575 \
  --message-type ORU \
  --verbose

# Forward to FHIR server
dicom-gateway forward \
  --listen-port 11112 \
  --forward-fhir https://fhir.example.com/ImagingStudy \
  --message-type ORU

# Forward to both
dicom-gateway forward \
  --listen-port 11112 \
  --forward-hl7 hl7://hl7server:2575 \
  --forward-fhir https://fhir.example.com/ImagingStudy \
  --message-type ORU
```

**Features:**
- DICOM event listener
- Automatic HL7/FHIR conversion
- Multiple destination support
- Configurable message types
- Async processing

## Limitations

### Current Implementation

- **HL7 v2**: Basic support for ADT, ORM, ORU messages
- **FHIR**: Core resources only (ImagingStudy, Patient, Practitioner, DiagnosticReport)
- **IHE Profiles**: Basic PDI, XDS-I, PIX, PDQ support (not fully certified)
- **Listener/Forwarder**: Foundation implementation (TCP sockets, simplified DIMSE handling)

### Future Enhancements

- Full DIMSE protocol integration for forwarder mode
- IHE certification and extended profile support
- Additional HL7 message types (DFT, SIU, etc.)
- Additional FHIR resources (Observation, Procedure, etc.)
- TLS/SSL support for secure connections
- Enhanced error recovery and retry logic
- Persistent message queuing
- Load balancing for multiple destinations

## Architecture

### Components

- **main.swift**: CLI interface with ArgumentParser
- **GatewayTypes.swift**: Common types and errors
- **HL7Parser.swift**: HL7 v2 parsing and generation
- **DICOMToHL7Converter.swift**: DICOM → HL7 conversion
- **HL7ToDICOMConverter.swift**: HL7 → DICOM conversion
- **FHIRConverter.swift**: DICOM ↔ FHIR conversion
- **GatewayListener.swift**: HL7 listener and DICOM forwarder (Phase C)
- **IHEProfiles.swift**: IHE profile support (Phase D)
- **MappingEngine.swift**: Custom mapping engine (Phase D)

## License

Part of DICOMKit - See main repository license.

## Version

**1.1.0** - Phases A, B, C, and D complete (43+ tests)
- Phase A: HL7 v2 conversion (9 tests)
- Phase B: FHIR conversion and batch processing (8 tests)
- Phase C: Listener and forwarder modes (10 tests)
- Phase D: IHE profiles and custom mapping engine (16 tests)

## Testing

Comprehensive test suite with 43+ unit and integration tests covering:
- HL7 v2 message parsing and generation
- DICOM ↔ HL7 bidirectional conversion
- DICOM ↔ FHIR bidirectional conversion
- Gateway listener and forwarder modes
- IHE profile validation (PDI, XDS-I, PIX, PDQ)
- Custom mapping engine with transformations
- Error handling and edge cases
- Round-trip conversion validation

Run tests:
```bash
swift test --filter DICOMGatewayTests
```
