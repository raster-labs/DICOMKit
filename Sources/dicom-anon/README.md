# dicom-anon

De-identifies DICOM files to the DICOM standard: **PS3.15 Annex E, Basic Application
Level Confidentiality Profile** — header attributes *and* text burned into the pixels.

There is one profile and it is always applied. The standard's named **retention
options** are the only way to keep more; its **Clean Pixel Data** option is on by
default. There is no per-tag keep/replace override: a file this tool writes either
meets the profile it declares in (0012,0063)/(0012,0064), or is marked
Patient Identity Removed = NO and written only if you say so.

## What the Basic Profile does

- Every direct identifier in PS3.15 Table E.1-1 is handled by its action code:
  Type 1/2 attributes such as Patient's Name are **zeroed** (present, empty — the file
  stays conformant), Type 3 ones such as Institution Name are **removed**.
- Every sequence item is scrubbed recursively.
- Every remaining person-name (PN) attribute is removed; every instance UID is
  **regenerated consistently** (one map per run, so a study still holds together);
  every private tag is removed.
- Dates and times are zeroed unless a temporal option is chosen.
- The de-identification method is recorded: (0012,0062) Patient Identity Removed,
  (0012,0063) De-identification Method, (0012,0064) with the CID 7050 codes
  (113100 Basic Profile, plus one code per option applied, plus 113101 when pixels
  were cleaned).

## Retention options (PS3.15 E.3)

| Flag | Option | Code |
|---|---|---|
| `--retain-dates` | Retain Longitudinal Temporal Information with Full Dates | 113106 |
| `--shift-dates N` | … with Modified Dates: eligible longitudinal dates shifted by N days, times untouched; birth date remains cleared by the main profile rules | 113107 |
| `--retain-characteristics` | Retain Patient Characteristics (age, sex, size, weight) | 113108 |
| `--retain-device` | Retain Device Identity (model, station name, serial) | 113109 |
| `--retain-institution` | Retain Institution Identity (name, address, department) | 113112 |
| `--retain-uids` | Retain UIDs (no regeneration) | 113110 |
| `--clean-descriptors` | Clean Descriptors: remove identifying text from retained study/series descriptions | 113105 |

`--retain-dates` and `--shift-dates` are alternatives; passing both is an error.

## Clean Pixel Data (113101) — on by default

Burned-in identifiers are located from up to four sources, unioned: the declared
clinical region (Ultrasound Regions, blank everything outside), a curated device
template, on-device OCR (Apple Vision), and any `--redact-region` you name. Regions
are blanked (decode → mask every frame → attest) and the file is re-emitted as
Explicit VR Little Endian unless `--recompress` says otherwise. Burned In Annotation
is set to NO and 113101 recorded **only when pixels were actually blanked**.

**Burned In Annotation (0028,0301) policy**

| (0028,0301) | What happens |
|---|---|
| `YES` | Pixels are cleaned. If no source can locate the text the run **refuses** rather than guessing. |
| absent | OCR decides: text found → cleaned; nothing found → pixels untouched. |
| `NO` | The declaration is trusted; pixels are neither inspected nor modified. The verbose console and the audit log say so. Overlay planes or `--redact-region` override the trust. |

| Flag | Role |
|---|---|
| `--no-clean-pixel-data` | Header only. Files whose pixels may still carry PHI are refused unless `--allow-burned-in-phi`. |
| `--ocr-mode header\|classify` | `header`: only text matching the file's own PHI or a PHI-shaped pattern; scales and legends survive; fails **open**. `classify` (default): plus PHI keywords, keeping only text on the clinical allowlist; fails **closed**. To erase an area whatever it reads, use `--redact-region`. |
| `--text-only` | Blank only the flagged text at its exact position — no banner band from the declared regions or the device template. Pair with `--ocr-mode header`. Drops the safety net; verify visually. |
| `--ocr-all-frames` | OCR every frame instead of first/middle/last. |
| `--redact-region x,y,w,h` | Explicit rectangle (repeatable); always applied. |
| `--redact-fill black\|white\|N` | Fill value for blanked samples. |
| `--redact-style blank\|label\|replace` | Fill only; a `REDACTED` stamp (`--redact-label`); or the header engine's own de-identified value (a shifted date) so pixels and header agree. |
| `--recompress source\|<codec>` | Re-encode the clean pixels; regions are re-verified blank afterwards. |
| `--allow-burned-in-phi` | Write anyway; output marked Patient Identity Removed = NO. |

## Run control

`--output`, `--recursive`, `--dry-run` (header changes and the pixel redaction plan,
nothing written), `--backup`, `--audit-log` (tags and action codes — never values),
`--force`, `--verbose`.

## Usage

```bash
# Strict Basic Profile, header and pixels
dicom-anon file.dcm --output anon.dcm

# Longitudinal study: keep intervals and age/sex
dicom-anon study/ --output anon_study/ --recursive --shift-dates 100 --retain-characteristics

# Preview everything, write nothing
dicom-anon file.dcm --dry-run

# Ultrasound: remove exactly the study's own identifiers, keep scales and legends
dicom-anon echo.dcm --output anon.dcm --ocr-mode header --text-only --redact-fill white

# Fixed banner, keep the source codec
dicom-anon xa.dcm --output anon.dcm --redact-region 0,0,1024,90 --recompress source

# Header only (refuses files that declare burned-in text)
dicom-anon ct.dcm --output anon.dcm --no-clean-pixel-data
```

## Exit codes

- `0`: every file de-identified
- `1`: one or more files failed or were refused

## Limitations

1. Region selection is not verifiable by test — inspect output visually before release.
2. `--ocr-mode header` fails open: text the header never carried is not recognised.
3. Header cleaning uses the current PS3.15 Table E.1-1 rules and selected option
   columns, plus private-attribute and VR handling; see `ConfidentialityProfile.swift`.
4. Automatic OCR requires Apple Vision. Unsupported OCR requests fail rather than silently skipping recognition.
5. Linux builds remain blocked by the existing JLISwift dependency, which imports
   Apple’s Accelerate framework. This integration does not resolve that dependency
   limitation; `--no-clean-pixel-data` does not bypass a build-time dependency failure.
   Validation for this integration was performed on macOS with Swift 6.4/Xcode 27.

## See Also

- `dicom-info`, `dicom-validate`, `dicom-convert`
- DICOM PS3.15 Annex E — Attribute Confidentiality Profiles; PS3.16 CID 7050

### Integration with the current header engine

The OCR workflow uses the audited header engine from main. It preserves descriptor and structured-content cleaning, safe-private handling, modified-date rules, and file-meta UID synchronization. Pixel replacement previews reserve the same UID mappings used by the final header pass.

Additional supported options are `--retain-safe-private`, `--clean-graphics`, `--clean-structured-content`, and `--clean-recognizable-visual-features` (requires explicit `--redact-region`). `--retain-full-dates` aliases `--retain-dates`; `--retain-modified-dates` requires `--shift-dates`. `--profile ps315` and `--profile basic` select the same Basic Profile. This is a CLI compatibility change: `legacy-basic`, `legacy-clinical-trial`, and `legacy-research` are rejected by the OCR CLI and no longer offered in Studio. Legacy attribute-list profiles remain available through the library API. Existing scripts should use `ps315`/`basic` with the explicit retention options and review the resulting output; the Basic Profile is not equivalent to a legacy tag list.

`--remove` and `--replace` accept tags or keywords and apply after the header pass. Replacement previews use these same overrides, and file-meta UIDs remain synchronized.

Non-image DICOM objects bypass OCR. Audit files record method names, tags, actions, and pixel-work notes without original attribute values.
