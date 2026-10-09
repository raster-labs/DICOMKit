# DICOM Print Management — Conformance Statement

DICOMKit implements the Print Management Service Class (PS3.4 Annex H) in **both**
roles:

- **SCU** — `DICOMPrintService` / `PrintWorkflow`: sends film sessions, film boxes and
  image boxes to a DICOM printer.
- **SCP** — `DICOMPrintServer`: a **printer emulator** that accepts print jobs from any
  modality or third-party application and composes the resulting film.

This document is what a modality or printer vendor will ask for. It states what is
implemented, what is deliberately not, and what has been verified against a foreign
implementation.

Version: 2026-08-03.

---

## 1. Network services

### 1.1 Application Entity, association

| Item | SCU | SCP |
|---|---|---|
| Association initiation | Yes | No |
| Association acceptance | No | Yes |
| Maximum PDU size | Negotiated, default 65536 | Negotiated, `maxPDUSize` (default 65536) |
| Maximum simultaneous associations | 1 per job | `maxConcurrentAssociations`, default 10 |
| Association at capacity | — | A-ASSOCIATE-RJ, transient / service-provider (presentation) / local-limit-exceeded (2) |
| Called AE title check | — | Exact match against the configured AE title |
| Calling AE title check | — | Optional whitelist / blacklist (blacklist wins) |
| Idle association timeout | — | `associationIdleTimeout`, default 300 s; 0 disables. Aborts and frees the slot |
| Asynchronous operations window | Not negotiated | Not negotiated |
| SOP class extended negotiation | Not proposed | Not required |

### 1.2 Presentation contexts

The SCU proposes the meta SOP Class **and** every individual SOP Class, then routes each
N-service to whichever context the printer accepted (individual preferred, meta as the
fallback). A printer that supports only one of the two styles works either way; only a
printer that accepts nothing at all fails the job.

| Abstract syntax | UID | SCU proposes | SCP accepts |
|---|---|---|---|
| Basic Grayscale Print Management Meta | 1.2.840.10008.5.1.1.9 | Yes (grayscale mode) | Yes |
| Basic Color Print Management Meta | 1.2.840.10008.5.1.1.18 | Yes (color mode) | Yes, when `supportsColor` |
| Basic Film Session | 1.2.840.10008.5.1.1.1 | Yes | Yes |
| Basic Film Box | 1.2.840.10008.5.1.1.2 | Yes | Yes |
| Basic Grayscale Image Box | 1.2.840.10008.5.1.1.4 | Yes | Yes |
| Basic Color Image Box | 1.2.840.10008.5.1.1.4.1 | Yes (color mode) | Yes, when `supportsColor` |
| Printer | 1.2.840.10008.5.1.1.16 | Yes | Yes |
| Print Job | 1.2.840.10008.5.1.1.14 | Yes | Yes |
| Presentation LUT | 1.2.840.10008.5.1.1.23 | Yes | Yes, when `acceptPresentationLUT` |
| Basic Annotation Box | 1.2.840.10008.5.1.1.15 | Yes | Yes, when `acceptAnnotationBox` |
| Verification | 1.2.840.10008.1.1 | — | Yes (C-ECHO on the same endpoint) |

Transfer syntaxes, both roles, both directions:

| Transfer syntax | UID | Supported |
|---|---|---|
| Explicit VR Little Endian | 1.2.840.10008.1.2.1 | Yes (preferred) |
| Implicit VR Little Endian | 1.2.840.10008.1.2 | Yes |
| Explicit VR Big Endian | 1.2.840.10008.1.2.2 | No |

Implicit VR is fully supported in both directions, including sequence parsing and
`PixelData` — modalities that propose implicit-only are common.

---

## 2. SOP class support

### 2.1 SCP (printer emulator)

| SOP Class | N-CREATE | N-SET | N-GET | N-ACTION | N-DELETE | N-EVENT-REPORT |
|---|---|---|---|---|---|---|
| Basic Film Session | Yes | Yes | Yes | Yes (print session) | Yes (cascades) | — |
| Basic Film Box | Yes | Yes | — | Yes (print film) | Yes (cascades to image boxes) | — |
| Basic Grayscale/Color Image Box | implicit (created with the film box) | Yes | — | — | with the film box | — |
| Printer | — | — | Yes | — | — | Sends, when configured |
| Print Job | — | — | Yes | — | — | Sends, when `pushPrintJobEvents` |
| Presentation LUT | Yes | — | — | — | Yes | — |
| Basic Annotation Box | Yes | Yes | — | — | Yes | — |

Notes:

- One Film Session per association (a second N-CREATE is refused with 0x0111). Print state
  is association-scoped, per PS3.4 H.4.
- **The SCU may supply the SOP Instance UID on N-CREATE** (PS3.7 10.1.5). When Affected SOP
  Instance UID (0000,1000) is present and valid, the SCP stores the object under *that* UID
  and echoes it in the response; otherwise it mints one. This applies to Film Session, Film
  Box, Presentation LUT and Basic Annotation Box. A supplied UID is accepted only if it is
  non-empty after trimming NUL/space padding, at most 64 characters, and composed of digits
  and dots; anything else is ignored and the SCP mints its own. Honoring it matters:
  dcm4che-based SCUs address every follow-up N-SET / N-ACTION by the UID *they* sent, not by
  the one returned.
- Image Box SOP Instance UIDs are allocated at Film Box N-CREATE and returned in
  Referenced Image Box Sequence (2010,0510), in film order. They are never SCU-supplied —
  image boxes are created implicitly with the film box.
- A film box carrying Annotation Display Format ID (2010,0030) is answered with
  `annotationBoxesPerFilm` (default 6) Basic Annotation Boxes in Referenced Basic
  Annotation Box Sequence (2010,0520) for the SCU to N-SET.
- N-GET returns the full attribute set; the Attribute Identifier List is not used to filter.

### 2.2 SCU

Creates a Film Session, one Film Box per film (images spill onto further films when they
exceed the layout's cells), N-SETs each Image Box, N-ACTIONs the Film Box, then N-DELETEs
the Film Session — all on **one association**, as PS3.4 H.4 requires. Optionally creates a
Presentation LUT and fills Annotation Boxes. Queries printer status (N-GET) and print job
status (N-GET) on demand.

---

## 3. Attributes

### 3.1 Image Display Format (2010,0010)

`STANDARD\C,R` is **columns first, then rows**, per PS3.3 C.13.3. Supported forms:

| Form | SCU sends | SCP accepts | Image boxes |
|---|---|---|---|
| `STANDARD\C,R` | Yes | Yes | C × R |
| `ROW\c1,c2,…` | No | Yes | Σ cᵢ |
| `COL\r1,r2,…` | No | Yes | Σ rᵢ |
| `SLIDE`, `SUPERSLIDE` | No | Yes | 1 |
| `CUSTOM\i` | No | Yes | 1 (printer-defined; not derivable) |

### 3.2 Enumerated values

| Attribute | Values |
|---|---|
| Film Size ID (2010,0050) | 8INX10IN, 8_5INX11IN, 10INX12IN, 10INX14IN, 11INX14IN, 11INX17IN, 14INX14IN, 14INX17IN, 24CMX24CM, 24CMX30CM, A4, A3 |
| Film Orientation (2010,0040) | PORTRAIT, LANDSCAPE |
| Medium Type (2000,0030) | PAPER, CLEAR FILM, BLUE FILM, MAMMO CLEAR FILM, MAMMO BLUE FILM (PS3.3 Table C.13-1; the SCP also reads the legacy MAMMO CLEAR / MAMMO BLUE as those terms) |
| Film Destination (2000,0040) | MAGAZINE, PROCESSOR, BIN_1, BIN_2 |
| Print Priority (2000,0020) | HIGH, MED, LOW |
| Magnification Type (2010,0060) | NONE, REPLICATE, BILINEAR, CUBIC |
| Trim (2010,0140) | YES, NO |
| Polarity (2020,0020) | NORMAL, REVERSE |
| Requested Decimate/Crop Behavior (2020,0040) | DECIMATE, CROP, FAIL |
| Presentation LUT Shape (2050,0020) | IDENTITY, LIN OD (PS3.3 C.11.4); an inverted film is rendered into the pixels by the SCU, never sent as a shape |

The SCP restricts Film Size ID and Medium Type to its configured sets and answers 0x0106
for anything else.

### 3.3 Optional attributes the SCU deliberately omits

Sent only when they carry information, because printers that do not implement them reject
the whole film box or image box when the attribute is merely present:

| Attribute | Omitted when | Rationale |
|---|---|---|
| Trim (2010,0140) | value is NO | Type 2C; NO is the printer default. Observed: DCMTK answers 0x0105 "trim requested but not supported" for a film box carrying Trim at all |
| Requested Decimate/Crop Behavior (2020,0040) | value is DECIMATE | Type 3; DECIMATE is what printers do by default. Observed: DCMTK answers 0x0105 when the attribute is unsupported |
| Configuration Information (2010,0150) | empty | Type 2C, printer-specific. **Sent whenever supplied** — several vendors require it to select a rendering configuration |
| Film Session Label (2000,0050) | empty | Type 3 |

### 3.4 Pixel data

| Item | SCU | SCP |
|---|---|---|
| Samples per Pixel | 1 (grayscale), 3 (color) | 1 or 3; 3 refused on the grayscale image box |
| Bits Allocated / Stored | 8/8, or 16 allocated with 12 stored (PS3.3 Table C.13-5); a request for 16 stored is clamped to 12; `--raw` frames outside Table C.13-5 are refused | 8 or 16 allocated; Bits Stored outside 8/12 clamped and logged |
| Photometric Interpretation | MONOCHROME1/2, RGB | MONOCHROME1/2, RGB, YBR_FULL, YBR_FULL_422, YBR_PARTIAL_422 |
| Encapsulated / compressed pixel data | No — native only | No — native only |

Subsampled YBR (PS3.3 C.7.6.3.1.2, Y1 Y2 Cb Cr per pixel pair) is accepted and unpacked by the
SCP even though Table C.13-5 enumerates only RGB for colour and our own SCU converts to RGB
before sending.

### 3.5 Image placement: Requested Image Size and Requested Decimate/Crop Behavior

PS3.3 Table C.13-5 applies CROP "if the image rows or columns is greater than the available
printable pixels in an Image Box", and Requested Image Size (2020,0030) "overrides the size that
corresponds with optimal filling of the Image Box" — "optimal filling" itself is not defined.
This implementation reads it as follows (decided 2026-09-29, P-CROP):

| Received | SCP (emulator) composes | SCU sends it for |
|---|---|---|
| DECIMATE or absent, no size | the image fitted inside the box (aspect kept) | Fit to Film |
| DECIMATE with a size | the requested width, never larger than the box | — |
| CROP, no size | the image scaled to *cover* the box, the overflow cropped (optimal filling read as filling the box) | Fill to Film |
| CROP with a size | the requested width, the overflow cropped | True Size (the width from the pixel spacing) |
| FAIL | the requested size or 1:1; a box it does not fit is left empty and reported | — |

A printer that reads "optimal filling" as *fit* prints a Fill to Film job fitted, uncropped;
the print sheet's preview shows the emulator's reading.

### 3.6 Rendering the composed sheet

The emulator draws each film as one of three density mappings (`--density`):

| Mapping | P-Values | LIN OD, Border/Empty densities |
|---|---|---|
| `paper` (default) | drawn as device grey, unchanged | LIN OD as transmitted luminance between Min and Max Density; numeric densities linear between them |
| `film` | as `paper`, inverted (a film on a light-box) | as `paper`, inverted |
| `gsdf` | laid down at the density the Grayscale Standard Display Function gives them (PS3.14 7.2 for film media, 7.3 for PAPER; Min/Max Density from the film box or 0.20/3.00 OD; L0/La the typical values of 7.2/7.3), shown as the sheet's luminance relative to its brightest, sRGB-encoded | taken as densities: L = La + L0·10^−D |

---

## 4. Status codes

Returned by the SCP; understood by the SCU (PS3.4 H.4, PS3.7 Annex C).

| Code | Meaning | When the SCP returns it |
|---|---|---|
| 0x0000 | Success | — |
| 0x0105 | No such attribute | — |
| 0x0106 | Invalid attribute value | Unsupported film size / medium type, bad enumerated value, bad pixel module, short Pixel Data |
| 0x0110 | Processing failure | The delegate could not produce the film |
| 0x0111 | Duplicate SOP Instance | Second Film Session on one association; Film Box N-CREATE with an SCU-supplied UID already in use |
| 0x0112 | No such SOP Instance | Unknown film box / image box / annotation box / print job UID |
| 0x0117 | Invalid object instance | — |
| 0x0120 | Missing attribute | Film Box N-CREATE without Image Display Format |
| 0x0122 | SOP Class not supported | N-service on a SOP Class this printer does not provide |
| 0xB600, 0xB604, 0xB605, 0xB609 | Warnings | Reserved; not currently returned |
| 0xC000 | Unable to process | Film Box before a Film Session, layout beyond `maxImageBoxesPerFilm`, N-ACTION on a film with no image content |
| 0xC603 | Image larger than image box | Image exceeds `maxImageBoxPixelDimension` |

Error Comment (0000,0902) accompanies every failure, transliterated to ASCII and truncated
to 64 characters.

**0x0106 is a failure, not a warning.** An SCU must stop when it sees it; treating it as a
warning makes a job continue past a rejected attribute and fail later with a misleading
code.

---

## 5. Verified interoperability

Automated, in `Tests/DICOMPrintKitTests/DCMTKInteropTests.swift`. These run against
**DCMTK 3.7.0**, an independent implementation, and skip when it is not installed.

| Direction | Peer | Result |
|---|---|---|
| DCMTK Print SCU (`dcmpsprt` + `dcmprscu`) → our SCP | DCMTK 3.7.0 | Film received and composed; calling AE, image count and geometry as sent |
| Our SCU → DCMTK Print SCP (`dcmprscp`, IHE Full profile) | DCMTK 3.7.0 | Film session, film box, image box, N-ACTION print and N-DELETE all accepted |
| Our SCU → DCMTK Print SCP, printer rejects an attribute | DCMTK 3.7.0 | Job fails immediately with the printer's own status (0x0106) |

Observations from those runs, all handled:

- `dcmprscp` rejects the Printer and Print Job SOP Class contexts; the SCU falls back to the
  meta context for those services and reports no Print Job UID, which is legitimate.
- `dcmprscp` validates image bit depth against its configured Presentation LUT, and accepts
  only 8- or 12-bit stored data.
- Film session and film box attributes are validated against the printer's *configured*
  value lists, not merely against the standard's defined terms.

Not yet tested against physical hardware.

---

## 6. Out of scope

Explicitly not implemented:

- Basic Print Image Overlay Box (1.2.840.10008.5.1.1.24.1)
- Image Overlay Box, Stored Print Storage, and the pull print model (Print Job as initiator)
- Presentation LUT **data tables** — the *shape* (IDENTITY / INVERSE / LIN OD) is honored;
  a LUT with explicit table data is accepted and stored but not applied
- Print Job N-EVENT-REPORT is optional and off by default (`pushPrintJobEvents`)
- Compressed (encapsulated) pixel data in image boxes
- TLS on the print association

---

## 7. Configuration reference

`PrintSCPConfiguration` (SCP): `aeTitle`, `port`, `maxPDUSize`, `maxConcurrentAssociations`,
`callingAEWhitelist`, `callingAEBlacklist`, `supportsColor`, `supportedFilmSizes`,
`supportedMediumTypes`, `maxImageBoxesPerFilm`, `maxImageBoxPixelDimension`, `printerName`,
`manufacturer`, `manufacturerModelName`, `deviceSerialNumber`, `softwareVersion`,
`acceptPresentationLUT`, `acceptAnnotationBox`, `annotationBoxesPerFilm`,
`associationIdleTimeout`, `pushPrintJobEvents`.

`PrintConfiguration` + `PrintOptions` (SCU): host, port, AE titles, timeout, color mode;
copies, priority, film size, orientation, medium type, destination, border/empty density,
magnification, polarity, trim, session label, Presentation LUT shape, annotations,
annotation display format ID, configuration information.
