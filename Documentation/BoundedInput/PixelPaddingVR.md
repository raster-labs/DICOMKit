# Implicit pixel padding VR

The bounded reader resolves Pixel Padding Value `(0028,0120)` and Pixel Padding
Range Limit `(0028,0121)` to `US` when Pixel Representation `(0028,0103)` is 0,
and `SS` when it is 1. This follows the padding dependency in
[PS3.3 C.7.5.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.5.html)
and the Image Pixel Module in
[PS3.3 C.7.6.3](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.3.html).

Each nested dataset uses its local Pixel Representation if present; otherwise
the bounded reader uses the nearest enclosing dataset's context. Resolution
happens after the complete structure is captured, so a sequence preceding its
parent's Pixel Representation is handled correctly. Local context never leaks
to sibling items. A malformed local value blocks inheritance, while a valid
local value can override missing or malformed ancestor context.

For implicit padding, Pixel Representation must be one 16-bit value, 0 or 1,
and each padding element must contain exactly one 16-bit value. Missing or
invalid effective context returns a scalar parser failure. Datasets without
padding retain their existing structural parsing behavior.

Explicit VR is preserved exactly, including a mismatch with Pixel
Representation. Consumers must continue rejecting such semantic mismatches;
the reader does not repair encoded VRs or reinterpret the raw value bytes.

The canonical parser captures signedness through its existing verified cursor.
Resolution uses the existing admitted scope/element vectors, takes linear time
in their size, checks cancellation, and finishes before source validation and
publication. It creates no additional source scan or backing allocation.
The legacy materialized reader's dictionary-first VR behavior is outside this
bounded-reader repair. This change does not update application dependencies or
qualify display, padding exclusion, or codec behavior.

The same finalization pass now also handles the bounded
[implicit Modality LUT contract](ImplicitLUTVR.md).
