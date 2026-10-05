// EncapsulatedDocumentHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent encapsulated document type helpers
// Reference: DICOM PS3.3 A.45 (Encapsulated Document IODs: A.45.1 Encapsulated PDF, A.45.2 Encapsulated CDA), A.85 (Encapsulated 3D Manufacturing Model IODs: A.85.1 STL, A.85.2 OBJ, A.85.3 MTL), C.24 (Encapsulated Document Modules)
// NEMA-verified: 2026a, checked 2026-10-05 — the 5 MIME Type of Encapsulated Document Enumerated Values matched case-insensitively against PS3.3 2026a A.45.1.4.1, A.45.2.4 and A.85.1-A.85.3 (application/pdf, text/XML, model/stl, model/obj, model/mtl: 5/5; the STL / OBJ / MTL IODs are A.85, not A.45.3-A.45.5 — citation corrected; application/sla is an extra alias for STL files); the 5 SOP Class UIDs come from DICOMKit.EncapsulatedDocument (PS3.6 Table A-1 1.2.840.10008.5.1.4.1.1.104.1-5); the rest is formatting

import Foundation
import DICOMKit

/// Platform-independent helpers for encapsulated document handling.
public enum EncapsulatedDocumentHelpers: Sendable {

    // MARK: - Type Detection

    /// Maps a MIME type string to an `EncapsulatedDocumentType`.
    public static func documentType(for mimeType: String) -> EncapsulatedDocumentType {
        switch mimeType.lowercased() {
        case "application/pdf":                     return .pdf
        case "text/xml":                            return .cda
        case "model/stl", "application/sla":        return .stl
        case "model/obj":                           return .obj
        case "model/mtl":                           return .mtl
        default:                                    return .unknown
        }
    }

    /// Maps a DICOM SOP Class UID to an `EncapsulatedDocumentType`.
    public static func documentTypeForSopClassUID(_ sopClassUID: String) -> EncapsulatedDocumentType {
        switch sopClassUID {
        case EncapsulatedDocument.encapsulatedPDFStorageUID: return .pdf
        case EncapsulatedDocument.encapsulatedCDAStorageUID: return .cda
        case EncapsulatedDocument.encapsulatedSTLStorageUID: return .stl
        case EncapsulatedDocument.encapsulatedOBJStorageUID: return .obj
        case EncapsulatedDocument.encapsulatedMTLStorageUID: return .mtl
        default:                                             return .unknown
        }
    }

    // MARK: - Formatting

    /// Returns a human-readable file size string.
    ///
    /// - Less than 1 KB: `"X bytes"`
    /// - Less than 1 MB: `"X.X KB"`
    /// - 1 MB and above: `"X.X MB"`
    public static func formattedFileSize(_ bytes: Int) -> String {
        if bytes < 1_024 {
            return "\(bytes) bytes"
        } else if bytes < 1_048_576 {
            let kb = Double(bytes) / 1_024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / 1_048_576.0
            return String(format: "%.1f MB", mb)
        }
    }

    // MARK: - Appearance

    /// Returns the SF Symbol name for the given document type.
    public static func sfSymbolForDocumentType(_ type: EncapsulatedDocumentType) -> String {
        type.sfSymbol
    }

    /// Returns the default zoom level for the given document type.
    public static func defaultZoom(for type: EncapsulatedDocumentType) -> Double {
        switch type {
        case .pdf, .cda:         return 1.0
        case .stl, .obj, .mtl:  return 0.8
        case .unknown:           return 1.0
        }
    }

    // MARK: - Display Logic

    /// Returns whether the given document type can be rendered in the viewer.
    public static func canDisplay(_ type: EncapsulatedDocumentType) -> Bool {
        type.isViewable
    }

    /// Returns a page indicator string such as `"Page 1 of 3"` or `"No pages"`.
    public static func pageDescription(currentPage: Int, totalPages: Int) -> String {
        guard totalPages > 0 else { return "No pages" }
        return "Page \(currentPage + 1) of \(totalPages)"
    }
}
