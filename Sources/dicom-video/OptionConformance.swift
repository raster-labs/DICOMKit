// NEMA-verified: 2026a, checked 2026-10-06 — lifted into DICOMKit as Sources/DICOMKit/Video/VideoOptionConformance.swift (D269), where the Modality / Patient's Sex / DA / Table A-1 refusals are re-verified; this deprecated alias keeps the CLI name for the dicom-video tests and for DICOMStudio's text-identical copy (diff_studio_g1) until the Studio pass rewires it; main.swift consumes DICOMKit.VideoOptionConformance
import DICOMKit

/// Lifted into DICOMKit (D269): use ``DICOMKit/VideoOptionConformance``.
@available(*, deprecated, renamed: "DICOMKit.VideoOptionConformance", message: "lifted into DICOMKit (D269)")
typealias VideoOptionConformance = DICOMKit.VideoOptionConformance
