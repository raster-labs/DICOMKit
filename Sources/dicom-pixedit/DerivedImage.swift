// NEMA-verified: 2026a, checked 2026-10-06 — lifted into DICOMKit as Sources/DICOMKit/PixelEditing/PixelEditInputChecks.swift (D270), where the PS3.3 2026a C.7.6.3.1 stored-range and C.11.2.1.2 Window Width refusals (P-PIXEDIT-RANGE) are re-verified; this deprecated alias keeps the CLI name for the dicom-pixedit tests and for DICOMStudio's text-identical copy (WorkshopDerivedImage) until the Studio pass rewires it; main.swift consumes DICOMKit.PixelEditInputChecks
import DICOMKit

/// Lifted into DICOMKit (D270): use ``DICOMKit/PixelEditInputChecks``.
@available(*, deprecated, renamed: "DICOMKit.PixelEditInputChecks", message: "lifted into DICOMKit (D270)")
typealias DerivedImage = DICOMKit.PixelEditInputChecks
