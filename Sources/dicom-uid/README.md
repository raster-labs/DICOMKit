# dicom-uid

DICOM UID generation, validation, and management tool.

## Features

- **Generate** new DICOM UIDs with custom roots and types
- **Validate** UIDs against DICOM PS3.5 Section 9 compliance rules
- **Look up** UIDs registered in PS3.6 Table A-1 (filter with `--type`: transfer-syntax, sop-class, meta-sop-class, well-known-sop-instance, ldap-oid, coding-scheme, application-context-name, service-class, application-hosting-model, mapping-resource, synchronization-frame-of-reference)
- **Regenerate** UIDs in DICOM files while maintaining hierarchical relationships
- **Export** old→new UID mappings to JSON for tracking

## Usage

### Generate UIDs

```bash
# Generate a single UID
dicom-uid generate

# Generate 5 study UIDs
dicom-uid generate --count 5 --type study

# Generate with your organisation's registered root (PS3.5 9.2.2); the default is
# DICOMKit's root 1.2.826.0.1.3680043.10.511.4. A root that is not a valid UID, or is
# too long to leave room for the unique suffix within 64 characters, is rejected.
dicom-uid generate --root 1.2.826.0.1.3680043.9.1234

# UUID derived UIDs, 2.25.<UUID as a decimal integer> (PS3.5 B.2)
dicom-uid generate --uuid --count 3

# Output as JSON
dicom-uid generate --count 3 --json
```

### Validate UIDs

```bash
# Validate a UID string
dicom-uid validate 1.2.840.10008.1.2.1

# Validate multiple UIDs
dicom-uid validate 1.2.3.4.5 1.2.3..4 1.2.3.04

# Validate all UIDs in a DICOM file
dicom-uid validate --file study.dcm

# Check registry names
dicom-uid validate 1.2.840.10008.1.2.1 --check-registry
```

### Look Up UIDs

```bash
# Look up a specific UID
dicom-uid lookup 1.2.840.10008.1.2.1

# List all known UIDs
dicom-uid lookup --list-all

# Filter by type
dicom-uid lookup --list-all --type transfer-syntax

# Search by name
dicom-uid lookup --search "CT"
```

`lookup` prints the UID Type of PS3.6 2026a Table A-1 verbatim (for example "Well-known SOP Instance",
"Application Context Name", "DICOM UIDs as a Coding Scheme"). With `--json` each entry has `uid`, `name`,
`uidType` (the Table A-1 UID Type) and `type`. **`type` is deprecated**: it keeps the former tool wording
("Well-Known UID", "Application Context", "Coding Scheme" for the DICOM UID Registry) for existing scripts and
will be removed in the next major version; read `uidType` instead.

### Regenerate UIDs

```bash
# Regenerate UIDs in a file (in-place)
dicom-uid regenerate file.dcm

# Regenerate to a new file
dicom-uid regenerate file.dcm --output new.dcm

# Batch regeneration with relationship maintenance
dicom-uid regenerate file1.dcm file2.dcm --output output_dir/ --maintain-relationships

# Export UID mapping
dicom-uid regenerate study/*.dcm --output new/ --export-map mapping.json

# Preview changes (dry run)
dicom-uid regenerate file.dcm --dry-run --verbose
```

## UID Validation Rules (PS3.5 9.1)

- Maximum 64 characters
- Only digits (0-9) and periods (.)
- No leading or trailing periods
- No consecutive periods
- No leading zeros in components (except "0" itself)

Each failure names PS3.5 9.1. `validate --file` checks every UI value of the file, File Meta
and sequence items included.

## Regeneration scope

`regenerate` replaces the values of the 57 UI attributes of PS3.15 Table E.1-1 (action U,
and D for Annotation Group UID): SOP Instance, Study, Series and Frame of Reference UIDs,
Referenced SOP Instance UID (0008,1155) in Referenced / Source Image Sequence, Referenced
Frame of Reference UID (3006,0024), and the rest of that table, at every sequence depth. The
same old UID gets the same new UID throughout a file and, with `--maintain-relationships`
(automatic for more than one input), across files, so references between the files keep
pointing at the right instance. Other UI attributes (SOP Class, Transfer Syntax, Coding
Scheme UID (0008,010C), Context Group Extension Creator UID, private attributes) and any
value that is a PS3.6 Table A-1 UID are kept. The Media Storage SOP Instance UID (0002,0003)
follows the new SOP Instance UID.

## Version

1.3.2
