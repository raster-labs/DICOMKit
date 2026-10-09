//
// Tag+EncapsulatedDocument.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// DICOM tags for Encapsulated Document Module
///
/// Reference: PS3.6 Section 6 - Registry of DICOM Data Elements
/// Encapsulated Document tags are in group 0x0042
/// Reference: PS3.3 C.24 - Encapsulated Document Module
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {

    // MARK: - Encapsulated Document Module (PS3.3 C.24.2)

    /// MIME Type of Encapsulated Document (0042,0012)
    /// Required. The MIME type of the encapsulated document (e.g., "application/pdf")
    public static let mimeTypeOfEncapsulatedDocument = Tag(group: 0x0042, element: 0x0012)

    /// Encapsulated Document (0042,0011)
    /// Required. The actual encapsulated document data
    public static let encapsulatedDocument = Tag(group: 0x0042, element: 0x0011)

    // MARK: - Encapsulated Document Series Module (PS3.3 C.24.1)

    /// Document Title (0042,0010)
    /// Optional. Title of the encapsulated document
    public static let documentTitle = Tag(group: 0x0042, element: 0x0010)

    // MARK: - Concept Name Code Sequence (already defined in Tag+StructuredReporting.swift)
    // conceptNameCodeSequence (0040,A043) is available from SR module

    // MARK: - HL7 Instance Identifier (0040,E001)
    /// HL7 Instance Identifier (0040,E001)
    /// Optional. HL7 CDA document instance identifier
    public static let hl7InstanceIdentifier = Tag(group: 0x0040, element: 0xE001)

    // MARK: - Source Instance Sequence (0042,0013)
    /// Source Instance Sequence (0042,0013)
    /// Optional. References to source instances that contributed to the document
    public static let sourceInstanceSequence = Tag(group: 0x0042, element: 0x0013)

    // MARK: - List of MIME Types (0042,0014)
    /// List of MIME Types (0042,0014)
    /// Optional. List of MIME types for encapsulated document with additional data
    public static let listOfMIMETypes = Tag(group: 0x0042, element: 0x0014)
}
