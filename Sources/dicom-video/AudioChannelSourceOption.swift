// NEMA-verified: 2026a, checked 2026-10-06 — lifted into DICOMKit as Sources/DICOMKit/Video/AudioChannelSourceOption.swift (D269), where the 6 PS3.16 2026a CID 3000 keywords and the (003A,0208) / (003A,0300) rules are re-verified; this deprecated alias keeps the CLI name for the dicom-video tests and for DICOMStudio's text-identical copy (diff_studio_g1) until the Studio pass rewires it; main.swift consumes DICOMKit.AudioChannelSourceOption
import DICOMKit

/// Lifted into DICOMKit (D269): use ``DICOMKit/AudioChannelSourceOption``.
@available(*, deprecated, renamed: "DICOMKit.AudioChannelSourceOption", message: "lifted into DICOMKit (D269)")
typealias AudioChannelSourceOption = DICOMKit.AudioChannelSourceOption
