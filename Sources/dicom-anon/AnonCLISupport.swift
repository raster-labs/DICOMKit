// NEMA-verified: 2026a, checked 2026-10-06 — lifted into DICOMKit as Sources/DICOMKit/Anonymization/AnonCLISupport.swift (D275), where the PS3.15 2026a E.3 Option names, Table E.1-1a action codes and the PS3.10 Table 7.1-1 (0002,0003) sync are re-verified; this deprecated alias keeps the CLI name for the dicom-anon tests and for DICOMStudio's text-identical copy (WorkshopAnonCLI, diff_studio_g1) until the Studio pass rewires it; main.swift consumes DICOMKit.AnonCLI and rethrows DICOMKit.AnonCLI.ValidationError as the CLI's own ValidationError (same message and exit status)
import DICOMKit

/// Lifted into DICOMKit (D275): use ``DICOMKit/AnonCLI``.
@available(*, deprecated, renamed: "DICOMKit.AnonCLI", message: "lifted into DICOMKit (D275)")
typealias AnonCLI = DICOMKit.AnonCLI
