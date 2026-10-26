# Implicit Modality LUT value representations

The bounded reader resolves LUT Descriptor `(0028,3002)` only when it is an
immediate element of a Modality LUT Sequence `(0028,3000)` item. Its VR is `US`
for Pixel Representation 0 and `SS` for Pixel Representation 1. A descriptor
must contain exactly three 16-bit words, and effective Pixel Representation
must be one valid 16-bit value, 0 or 1. Otherwise bounded parsing returns a
scalar failure before publication.

The first and third descriptor words remain **unsigned**, even when the
descriptor VR is `SS`. The first is the entry count (zero means 65,536), the
second is the first mapped input value, and the third is the entry depth.
The reader does not convert these words or replace their raw bytes.

For implicit VR Little Endian, LUT Data `(0028,3006)` is exposed as `OW` in
every dataset scope. PS3.5 A.1 permits either US or OW: OW is this API's
canonical choice, not a claim that the standard uniquely requires it. It
preserves the original value length and bytes, including packed eight-bit
entries and the padding needed for an even value length. Consumers use the
descriptor to distinguish packed eight-bit entries from sixteen-bit entries;
an `OW` value must not automatically be treated as one LUT entry per word.

The existing nearest-enclosing Pixel Representation policy also applies to
Modality descriptors. A local value overrides its ancestors, an absent value
inherits, and an invalid local value blocks inheritance. This is the bounded
API's context policy, not a general assertion that all DICOM attributes inherit.
Resolution happens after the full structure is captured, so late parent
metadata works without leaking a sibling item's context. Each scope records
its owning sequence in the existing admitted index. The same finalizer handles
pixel padding and LUTs and checks cancellation per scope and element. It creates
no separate backing allocation or source scan; the additional scope metadata
remains charged to the existing admitted index.

Explicit VRs remain unchanged, including mismatches. Descriptor VRs in other
contexts, including VOI LUT Sequence, retain their existing dictionary-default
behavior: VOI signedness depends on the post-Modality input domain and cannot
be resolved safely from the stored pixel representation alone. This change
does not claim to resolve every ambiguous DICOM VR.

Structural parsing does not establish semantic LUT admission. Consumers still
validate descriptor depth (8 or 16 for Modality LUT), count/payload agreement,
padding, explicit VR consistency, supported historical encodings, and transform
exclusivity. No malformed table is repaired or silently normalized. The legacy
materialized reader and application dependency pins are outside this change.

Normative references checked on 26 October 2026:

- [PS3.5 A.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/chapter_A.html): implicit VR encoding and unsigned first/third descriptor words.
- [PS3.3 C.11.1.1.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.11.html): Modality LUT count, signed input, depth and packed eight-bit storage.
- [PS3.3 C.11.2.1.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.11.2.html): VOI LUT input signedness.
- [PS3.5 7.1.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/chapter_7.html): even value field length.
