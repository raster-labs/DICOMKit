// NEMA-verified: 2026a, checked 2026-09-29 — SOP Class gate and value-type walk per PS3.3 2026a A.35.4
/// Key Object Selection Extraction API
///
/// Provides high-level extraction of Key Object Selection data from KOS documents.
///
/// Reference: PS3.3 Section A.35.5 - Key Object Selection Document
/// Reference: PS3.16 TID 2010 - Key Object Selection

import Foundation
import DICOMCore

/// Represents extracted Key Objects from a KOS document
///
/// Provides structured access to selected DICOM instances (images, waveforms, etc.)
/// with their selection purpose and optional descriptions.
///
/// Example:
/// ```swift
/// let parser = SRDocumentParser()
/// let document = try parser.parse(dataSet: dataSet)
/// let keyObjects = try KeyObjects.extract(from: document)
/// 
/// print("Purpose: \(keyObjects.selectionPurpose?.codeMeaning ?? "Unknown")")
/// for obj in keyObjects.objects {
///     print("Object: \(obj.sopInstanceUID)")
///     if let desc = obj.description {
///         print("  Description: \(desc)")
///     }
/// }
/// ```
public struct KeyObjects: Sendable, Equatable {
    
    // MARK: - Document Information
    
    /// The original SR document
    public let document: SRDocument
    
    /// Document title (Purpose of Selection)
    public var documentTitle: CodedConcept? {
        document.documentTitle
    }
    
    /// Purpose of selection (same as document title)
    public var selectionPurpose: CodedConcept? {
        documentTitle
    }
    
    // MARK: - Selected Objects
    
    /// Selected key objects
    public let objects: [KeyObject]
    
    // MARK: - Extraction API
    
    /// Extracts key objects from a KOS document
    /// - Parameter document: The SR document to extract from
    /// - Returns: Extracted key objects
    /// - Throws: `ExtractionError` if the document is not a valid KOS document
    public static func extract(from document: SRDocument) throws -> KeyObjects {
        // Validate document type
        guard let docType = document.documentType,
              docType.sopClassUID == SRDocumentType.keyObjectSelectionDocument.sopClassUID else {
            throw ExtractionError.invalidDocumentType(
                "Document must be Key Object Selection Document, got: \(document.sopClassUID)"
            )
        }
        
        // Extract key objects from the root container
        let objects = extractKeyObjects(from: document.rootContent)
        
        // Validate that at least one key object was found
        if objects.isEmpty {
            throw ExtractionError.invalidStructure("No key objects found in document")
        }
        
        return KeyObjects(
            document: document,
            objects: objects
        )
    }
    
    // MARK: - Private Extraction Helpers
    
    private static func extractKeyObjects(from container: ContainerContentItem) -> [KeyObject] {
        var objects: [KeyObject] = []
        var currentDescription: String?
        
        // Process content items in sequence
        for item in container.contentItems {
            // Text items provide descriptions for subsequent image references
            if let textItem = item.asText {
                // Store description for the next image reference
                currentDescription = textItem.textValue
            }
            
            // Image references are the key objects
            else if let imageItem = item.asImage {
                let sopRef = imageItem.imageReference.sopReference
                let frames = imageItem.imageReference.frameNumbers
                let keyObject = KeyObject(
                    sopClassUID: sopRef.sopClassUID,
                    sopInstanceUID: sopRef.sopInstanceUID,
                    description: currentDescription,
                    frames: frames
                )
                objects.append(keyObject)
                
                // Clear description after using it
                currentDescription = nil
            }
            
            // Composite references (general DICOM object references)
            else if let compositeItem = item.asComposite {
                let sopRef = compositeItem.referencedSOPSequence
                let keyObject = KeyObject(
                    sopClassUID: sopRef.sopClassUID,
                    sopInstanceUID: sopRef.sopInstanceUID,
                    description: currentDescription,
                    frames: nil
                )
                objects.append(keyObject)
                
                // Clear description after using it
                currentDescription = nil
            }
            
            // Check nested containers
            else if let nestedContainer = item.asContainer {
                let nestedObjects = extractKeyObjects(from: nestedContainer)
                objects.append(contentsOf: nestedObjects)
            }
        }
        
        return objects
    }
}

// Note: KeyObject type is defined in KeyObjectSelectionBuilder.swift and is reused here
