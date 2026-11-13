# GSPS VOI and reference admission

`GrayscalePresentationState.voiLUT` represents one transformation applying to all images and frames in `referencedSeries`. It does not represent per-image VOI items or resolve overlapping scopes. `GrayscalePresentationStateParser` now rejects profiles that cannot be represented without losing source scope.

## Supported and rejected forms

- One Softcopy VOI LUT Sequence item without a nested Referenced Image Sequence remains supported, with either one window pair or one LUT table.
- Any nested Referenced Image Sequence is explicitly unsupported, including a scope that happens to match the top-level relationship. Matching a particular source does not make erasing its explicit scope safe for general consumers.
- Multiple Softcopy VOI items, multiple tables/window pairs, conflicting window/table definitions, malformed sequences, and items without a supported transformation throw `ParseError.unsupportedVOILUT`.
- A present unsupported Softcopy VOI sequence never falls back to top-level Window Center/Width or VOI LUT attributes. The existing legacy top-level reader remains available only when the Softcopy sequence is absent.
- The same parser checks apply when reading color or pseudo-color presentation-state classes through the shared parser.

Relationship references must contain nonempty SQ series/image sequences and complete single UI identifiers. Every entry must parse: malformed entries are not removed by `compactMap` or `continue`. Referenced SOP Classes must agree within a series. A present Referenced Frame Number must have IS VR, valid integer components, and strictly positive values. Only an absent frame restriction becomes `nil`; valid multiple frame numbers and multiple image references retain their original cardinality and order. Segment restrictions are explicitly rejected because `ReferencedImage` cannot represent them. These failures throw `ParseError.invalidReference` (a missing top-level relationship sequence retains the existing missing-attribute error).

For example, a relationship to image A/frame 1 with a nested VOI reference to image B/frame 2 previously produced a global window for A. It now fails parsing. Similarly, `2\BAD` in a present frame restriction previously became unrestricted; it now fails parsing.

## Scope of the repair

This is conservative rejection, not new scoped-VOI rendering support or complete presentation-state conformance validation. Applications must still verify that the selected image/SOP/frame belongs to the presentation state before using the model or applicator. Unrelated annotation/display-area profiles and legacy top-level VOI behavior are not expanded by this repair. The builder's existing single unscoped window/table output remains supported.

Synthetic regressions cover contradictory SOP/frame scopes, matching explicit scopes, item ordering/cardinality, malformed reference attributes, valid multiframe references, supported windows/tables, and legacy compatibility. Existing grayscale, color, pseudo-color, LUT and presentation-state tests provide related regression coverage. No DCMTK, private corpus or application pin changes are required for these library checks.

## References

- [DICOM PS3.3 C.11.8, Softcopy VOI LUT Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.11.8.html): VOI applicability to referenced images/frames and the per-image/frame transformation constraint.
- [DICOM PS3.3 C.11.11, Presentation State Relationship Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.11.11.html): required series/image references and consistent SOP Class within a series.
- [DICOM PS3.3 Table 10-3, Image SOP Instance Reference Macro](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_10.3.html): frame numbering and frame/segment restrictions.
