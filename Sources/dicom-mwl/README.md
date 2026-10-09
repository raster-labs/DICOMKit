# dicom-mwl - DICOM Modality Worklist Management

Query DICOM Modality Worklist items from worklist SCP servers.

## Features

- Query Modality Worklist (C-FIND) from PACS/RIS servers
- Filter by date, time, station AET, patient name, patient ID, and modality
- Date and time filters support DICOM Range Matching (PS3.4 C.2.2.2.5.1 / C.2.2.2.5.2),
  including open-ended ranges, and combined date+time interval queries (PS3.4 Table K.6-1,
  remark under Scheduled Procedure Step Start Time (0040,0003))
- JSON output support for automation
- Verbose mode for detailed attribute display

## Usage

### Query Worklist

Query worklist items for today:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY --date today
```

Query with multiple filters:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date 20240315 \
  --station CT1 \
  --patient "DOE^JOHN*" \
  --modality CT
```

Query with verbose output:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date today \
  --verbose
```

Query with JSON output:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date today \
  --json
```

Query a date range (both bounds inclusive):
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date 20240705-20240707
```

Query an open-ended date range (everything from today onward):
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date today-
```

A range that *starts* with a hyphen must use the `--date=` form, otherwise the
argument parser treats the value as another flag:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date=-20240707
```

> **Note:** Open-ended ranges (`YYYYMMDD-` / `-YYYYMMDD`) are valid DICOM, but not
> every MWL SCP implements them. dcm4chee, for example, rejects them with
> `0x0110 Unable to process`. Closed ranges (`YYYYMMDD-YYYYMMDD`) are the most
> portable form — use `20240707-20240707` in place of a single-day open range.

Query a combined date+time range as one continuous interval (PS3.4 Table K.6-1,
remark under (0040,0003)) — July 5 10:00 through July 7 18:00:
```bash
dicom-mwl query pacs://server:11112 --aet MODALITY \
  --date 20240705-20240707 --time 1000-1800
```

## Options

- `--aet`: Local Application Entity Title (required)
- `--called-aet`: Remote Application Entity Title (default: ANY-SCP)
- `--date`: Scheduled date filter — `YYYYMMDD`, `'today'`, `'tomorrow'` (Single Value
  Matching), or a DICOM date range `YYYYMMDD-YYYYMMDD`, `YYYYMMDD-`, `-YYYYMMDD`
  (Range Matching, both bounds inclusive; `today`/`tomorrow` may be used as a bound)
- `--time`: Scheduled time filter — `HHMMSS` (Single Value Matching), or a DICOM time
  range `HHMMSS-HHMMSS`, `HHMMSS-`, `-HHMMSS` (Range Matching). When both `--date` and
  `--time` are ranges, the SCP is expected to interpret them as one continuous
  date-time interval (PS3.4 Table K.6-1, remark under (0040,0003)) rather than
  independent filters. A TM value may be `HH`, `HHMM` or `HHMMSS[.FFFFFF]` (PS3.5
  Table 6.2-1); a range never crosses midnight (PS3.4 C.2.2.2.5.2).
- `--station`: Scheduled Station AE Title (0040,0001) filter, Single Value Matching
- `--patient`: Patient's Name (0010,0010) filter (Single Value or Wild Card Matching: *)
- `--patient-id`: Patient ID (0010,0020) filter, Single Value Matching
- `--modality`: Modality (0008,0060) filter (e.g., CT, MR, US), Single Value Matching
- `--sps-status`: Scheduled Procedure Step Status (0040,0020) filter. Defined Terms
  (PS3.3 Table C.4-10): `SCHEDULED`, `ARRIVED`, `READY`, `STARTED`, `DEPARTED`. Another
  value is sent as given, with a warning — `IN PROGRESS` / `COMPLETED` / `DISCONTINUED`
  are Performed Procedure Step Status values (Table C.4-14), not worklist states.
- `--accession-number`: Accession Number (0008,0050) filter
- `--performing-physician`: Scheduled Performing Physician's Name (0040,0006) filter
  (Single Value or Wild Card Matching: *)
- `--timeout`: Connection timeout in seconds (default: 60)
- `-v, --verbose`: Show verbose output with all attributes
- `--json`: Output results as JSON (one object per worklist item; see JSON keys below)

## JSON Keys

`--json` keys are PS3.6 2026a Table 6-1 keywords. Ten values were written under
abbreviated keys before 2026-10-01; they are now **also** written under their
keywords, and the old keys are kept with the same values but are **deprecated**
(read the keyword key; the old ones will be removed in a later release):

| Keyword key (use this) | Deprecated key | Attribute |
|---|---|---|
| `ScheduledProcedureStepStartDate` | `SPSStartDate` | (0040,0002) |
| `ScheduledProcedureStepStartTime` | `SPSStartTime` | (0040,0003) |
| `ScheduledProcedureStepStatus` | `SPSStatus` | (0040,0020) |
| `ScheduledProcedureStepID` | `SPSID` | (0040,0009) |
| `ScheduledProcedureStepDescription` | `SPSDescription` | (0040,0007) |
| `ScheduledProcedureStepLocation` | `SPSLocation` | (0040,0011) |
| `ScheduledPerformingPhysicianName` | `ScheduledPerformingPhysician` | (0040,0006) |
| `RequestedProcedureCodeSequence` (array of `{CodeValue, CodingSchemeDesignator, CodeMeaning}`) | `RequestedProcedureCode` (one object) | (0032,1064) |
| `ScheduledProtocolCodeSequence` (array) | `ScheduledProtocolCodes` | (0040,0008) |
| `ReferencedStudySequence` (array of `{ReferencedSOPClassUID, ReferencedSOPInstanceUID}`, every item) | `ReferencedStudySOPInstanceUID` (first item's UID only) | (0008,1110) |

## DICOM Reference

Implements PS3.4 Annex K - Modality Worklist Information Model (matching keys per
Table K.6-1; C-FIND response statuses per Table K.4-1).

SOP Class UID: 1.2.840.10008.5.1.4.31 (Modality Worklist Information Model - FIND)
