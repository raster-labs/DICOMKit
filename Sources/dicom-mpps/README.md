# dicom-mpps - DICOM Modality Performed Procedure Step

Create and update DICOM Modality Performed Procedure Step (MPPS) instances.

## Features

- Create MPPS instances (N-CREATE) to notify procedure start
- Update MPPS instances (N-SET) to notify procedure completion
- Support for IN PROGRESS, COMPLETED, and DISCONTINUED states
- Reference image SOPs in completion notifications

## Usage

### Create MPPS (Procedure Started)

Create an MPPS instance when a procedure begins:
```bash
dicom-mpps create pacs://server:11112 \
  --aet MODALITY \
  --study-uid 1.2.3.4.5.6.7.8.9 \
  --modality CT \
  --status "IN PROGRESS"
```

The tool will output the MPPS Instance UID which you'll need for updates.

### Update MPPS (Procedure Completed)

Update an MPPS instance when a procedure completes. `COMPLETED` requires at least
one Performed Series Sequence (0040,0340) item (PS3.4 Table F.7.2-1, final state),
so name the series and the images it produced with their real SOP Class:
```bash
dicom-mpps update pacs://server:11112 \
  --aet MODALITY \
  --mpps-uid 1.2.840.113619.2.xxx \
  --status COMPLETED \
  --study-uid 1.2.3.4.5 \
  --series-uid 1.2.3.4.5.6 \
  --sop-class-uid 1.2.840.10008.5.1.4.1.1.2 \
  --image-uid 1.2.3.4.5.6.7 \
  --image-uid 1.2.3.4.5.6.8
```

Without `--sop-class-uid` the Referenced SOP Class UID (0008,1150) defaults to
Secondary Capture Image Storage, which is wrong for anything but SC images.

### Discontinue Procedure

Mark a procedure as discontinued, optionally with a coded reason from PS3.16
CID 9300 "Procedure Discontinuation Reason" (which includes CID 9301), scheme DCM:
```bash
dicom-mpps update pacs://server:11112 \
  --aet MODALITY \
  --mpps-uid 1.2.840.113619.2.xxx \
  --status DISCONTINUED \
  --discontinuation-reason "110513|DCM|Discontinued for unspecified reason"
```

Other CID 9301 codes: `110500` Doctor canceled procedure, `110501` Equipment failure,
`110507` Patient did not arrive (PS3.16 Table D-1).

## Options

### Create Command
- `--aet`: Local Application Entity Title (required)
- `--called-aet`: Remote Application Entity Title (default: ANY-SCP)
- `--study-uid`: Study Instance UID (0020,000D) for the procedure (required)
- `--modality`: Modality (0008,0060) — required, Type 1 in the N-CREATE (PS3.4 Table F.7.2-1)
- `--status`: Initial status (default and only value: "IN PROGRESS", PS3.4 F.7.2.1.2)
- `--patient-sex`: Patient's Sex (0010,0040), Enumerated Values M, F, O (PS3.3 Table C.2-3)
- `--patient-birth-date`: Patient's Birth Date (0010,0030) as YYYYMMDD (VR DA)
- `--timeout`: Connection timeout in seconds (default: 60)
- `-v, --verbose`: Show verbose output

### Update Command
- `--aet`: Local Application Entity Title (required)
- `--called-aet`: Remote Application Entity Title (default: ANY-SCP)
- `--mpps-uid`: MPPS SOP Instance UID to update (required)
- `--status`: New Performed Procedure Step Status (0040,0252) — COMPLETED or
  DISCONTINUED (required; PS3.3 Table C.4-14 Enumerated Values, PS3.4 F.7.2.2.2)
- `--study-uid`: Study Instance UID for referenced images
- `--series-uid`: Series Instance UID (0020,000E) of the Performed Series item
- `--image-uid`: SOP Instance UIDs for referenced images (can be repeated; needs
  `--study-uid` and `--series-uid`)
- `--sop-class-uid`: Referenced SOP Class UID (0008,1150) of those images
- `--discontinuation-reason`: `CODE|SCHEME|MEANING` for (0040,0281), only with DISCONTINUED
- `--timeout`: Connection timeout in seconds (default: 60)
- `-v, --verbose`: Show verbose output

## Input Validation

These are refused before any association is opened (usage error, exit 64), with a
message citing the 2026a table; there is no override flag (owner decision
P-MPPS-STRICT, 2026-10-01: keep them as errors, not warnings):

| Refused input | Why (DICOM 2026a) |
|---|---|
| `create` without `--modality` | Modality (0008,0060) is Type 1 in the N-CREATE (PS3.4 Table F.7.2-1) |
| `--patient-sex` other than `M`, `F`, `O` | Patient's Sex (0010,0040) Enumerated Values (PS3.3 Table C.2-3) |
| `--patient-birth-date` not `YYYYMMDD` | Patient's Birth Date (0010,0030) is VR DA (PS3.5 Table 6.2-1) |
| `update --image-uid` without `--study-uid` and `--series-uid` | Referenced Image Sequence (0008,1140) items live in a Performed Series Sequence (0040,0340) item, which needs Series Instance UID (0020,000E) (PS3.4 Table F.7.2-1) |

## MPPS Workflow

1. **Procedure Start**: Create MPPS with status "IN PROGRESS"
2. **Procedure Execution**: Modality performs the imaging
3. **Procedure End**: Update MPPS with status "COMPLETED" and referenced images

## DICOM Reference

Implements PS3.4 Annex F - Modality Performed Procedure Step SOP Class (attributes
per Table F.7.2-1; N-SET statuses per Table F.7.2-2 and PS3.7 Annex C)

SOP Class UID: 1.2.840.10008.3.1.2.3.3 (Modality Performed Procedure Step SOP Class)
