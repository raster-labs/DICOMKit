// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data: the two values are this library's own switch between the Basic Grayscale and Basic Color Print Management Meta SOP Classes (PS3.4 Annex H), not an attribute term. C1 classification confirmed.
//
// PrintColorMode.swift
// DICOMCore
//
// The one definition of the print colour mode shared by DICOMKit's `ImagePreprocessor`
// and DICOMNetwork's `PrintConfiguration`. Both modules re-export it under their own
// name with a `typealias`, so `DICOMKit.PrintColorMode` and `DICOMNetwork.PrintColorMode`
// are the same type and no mapping between them is needed (D24 / P-PRINT).

import Foundation

/// Whether a print job uses the Basic Grayscale or the Basic Color Print Management
/// Meta SOP Class (PS3.4 H.4.1, H.4.2) and, on the image side, whether the prepared
/// pixels are MONOCHROME2 or RGB.
public enum PrintColorMode: String, Sendable, Codable, CaseIterable {
    case grayscale = "GRAYSCALE"
    case color = "COLOR"
}
