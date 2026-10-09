// NEMA-verified: 2026a, checked 2026-09-29 — document titles diffed by Scripts/diff_kit.py against PS3.16 2026a CID 7010; Modality KO (C.17.6.1); value types per Table A.35.4-2 (D17); Sup 59 (before 2014a) kept as provenance
/// Key Object Selection Document Builder
///
/// Provides a specialized fluent API for creating DICOM Key Object Selection (KOS) documents.
/// KOS documents are used to flag or select significant images, waveforms, or other composite
/// objects for specific purposes such as teaching, quality control, or research.
///
/// Reference: PS3.3 Section A.35.5 - Key Object Selection Document
/// Reference: PS3.16 TID 2010 - Key Object Selection
/// Reference: DICOM Supplement 59 - Key Object Selection

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Key Object Selection documents
///
/// KeyObjectSelectionBuilder provides a simplified API for creating documents that
/// reference and select significant DICOM instances (images, waveforms, etc.) with
/// a purpose code indicating why they were selected.
///
/// Example:
/// ```swift
/// let document = try KeyObjectSelectionBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle(.forTeaching)
///     .addKeyObject(
///         sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
///         sopInstanceUID: "1.2.3.4.5.6.7",
///         description: "Excellent demonstration of pathology"
///     )
///     .build()
/// ```
///
/// ## Purpose Codes
/// KOS documents use standard purpose codes from CID 7010:
/// - For Teaching (113004, DCM)
/// - Rejected for Quality Reasons (113001, DCM)
/// - For Referring Provider (113002, DCM)
/// - For Surgery (113003, DCM)
/// - Quality Issue (113010, DCM)
/// - Of Interest (113000, DCM)
///
/// ## Supported Content
/// KOS documents support the value types of PS3.3 Table A.35.4-2:
/// - TEXT - Text descriptions
/// - CODE - Coded concepts
/// - UIDREF - UID references
/// - PNAME - Person names
/// - COMPOSITE, IMAGE, WAVEFORM - References to DICOM objects
/// - CONTAINER - Hierarchical structure
public struct KeyObjectSelectionBuilder: Sendable {
    
    // MARK: - Error Types
    
    /// Errors that can occur during building
    public enum BuildError: Error, Sendable, Equatable {
        /// Validation error
        case validationError(String)
    }
    
    // MARK: - Configuration
    
    /// Whether to validate during build
    public let validateOnBuild: Bool
    
    // MARK: - Document Identification
    
    /// SOP Instance UID (will be generated if not set)
    public private(set) var sopInstanceUID: String?
    
    /// Study Instance UID
    public private(set) var studyInstanceUID: String?
    
    /// Series Instance UID
    public private(set) var seriesInstanceUID: String?
    
    /// Instance Number
    public private(set) var instanceNumber: String?
    
    // MARK: - Patient Information
    
    /// Patient ID
    public private(set) var patientID: String?
    
    /// Patient Name
    public private(set) var patientName: String?
    
    /// Patient Birth Date
    public private(set) var patientBirthDate: String?
    
    /// Patient Sex
    public private(set) var patientSex: String?
    
    // MARK: - Study Information
    
    /// Study Date
    public private(set) var studyDate: String?
    
    /// Study Time
    public private(set) var studyTime: String?
    
    /// Study Description
    public private(set) var studyDescription: String?
    
    /// Accession Number
    public private(set) var accessionNumber: String?
    
    /// Referring Physician's Name
    public private(set) var referringPhysicianName: String?
    
    // MARK: - Series Information
    
    /// Series Number
    public private(set) var seriesNumber: String?
    
    /// Series Description
    public private(set) var seriesDescription: String?
    
    // MARK: - Document Information
    
    /// Content Date
    public private(set) var contentDate: String?
    
    /// Content Time
    public private(set) var contentTime: String?
    
    /// Document Title (Purpose of Selection)
    public private(set) var documentTitle: DocumentTitle?
    
    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .complete
    
    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified
    
    // MARK: - Key Objects
    
    /// Selected key objects (referenced instances)
    public private(set) var keyObjects: [KeyObject] = []
    
    // MARK: - Initialization
    
    /// Creates a new Key Object Selection document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The patient birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format (HHMMSS)
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format (HHMMSS)
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title (Purpose of Selection)
    /// - Parameter title: The document title indicating the purpose
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: DocumentTitle) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.documentTitle = title
        return copy
    }
    
    /// Sets the Document Title using a custom coded concept
    /// - Parameter concept: Custom coded concept for document title
    /// - Returns: Updated builder
    public func withDocumentTitle(_ concept: CodedConcept) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.documentTitle = .custom(concept)
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    // MARK: - Key Object Management
    
    /// Adds a key object (referenced instance) to the selection
    /// - Parameters:
    ///   - sopClassUID: SOP Class UID of the referenced instance
    ///   - sopInstanceUID: SOP Instance UID of the referenced instance
    ///   - description: Optional text description of why this object is selected
    ///   - frames: Optional frame numbers for multi-frame images
    /// - Returns: Updated builder
    public func addKeyObject(
        sopClassUID: String,
        sopInstanceUID: String,
        description: String? = nil,
        frames: [Int]? = nil
    ) -> KeyObjectSelectionBuilder {
        var copy = self
        let keyObject = KeyObject(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            description: description,
            frames: frames
        )
        copy.keyObjects.append(keyObject)
        return copy
    }
    
    /// Adds multiple key objects to the selection
    /// - Parameter objects: Array of key objects to add
    /// - Returns: Updated builder
    public func addKeyObjects(_ objects: [KeyObject]) -> KeyObjectSelectionBuilder {
        var copy = self
        copy.keyObjects.append(contentsOf: objects)
        return copy
    }
    
    // MARK: - Build
    
    /// Builds the Key Object Selection document
    /// - Throws: `SRDocumentBuilderError` if validation fails
    /// - Returns: The constructed SR document
    public func build() throws -> SRDocument {
        // Validate if enabled
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        
        // Determine document title
        let finalDocumentTitle = documentTitle?.concept ?? CodedConcept(
            codeValue: "113000",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Of Interest"
        )
        
        // Build the root container
        let rootContainer = try buildRootContainer()
        
        // Create the SR document
        let document = SRDocument(
            sopClassUID: SRDocumentType.keyObjectSelectionDocument.sopClassUID,
            sopInstanceUID: finalSOPInstanceUID,
            patientID: patientID,
            patientName: patientName,
            studyInstanceUID: finalStudyInstanceUID,
            studyDate: studyDate,
            studyTime: studyTime,
            accessionNumber: accessionNumber,
            seriesInstanceUID: finalSeriesInstanceUID,
            seriesNumber: seriesNumber,
            modality: "KO",   // Key Object Document Series Module (PS3.3 C.17.6.1): Enumerated Value KO
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: instanceNumber,
            completionFlag: completionFlag,
            verificationFlag: verificationFlag,
            preliminaryFlag: nil,
            documentTitle: finalDocumentTitle,
            rootContent: rootContainer,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName
        )
        
        return document
    }
    
    // MARK: - Private Helpers
    
    private func buildRootContainer() throws -> ContainerContentItem {
        var contentItems: [AnyContentItem] = []
        
        // Add each key object as a reference
        for keyObject in keyObjects {
            // Add text description if provided
            if let description = keyObject.description {
                let textItem = TextContentItem(
                    conceptName: CodedConcept(
                        codeValue: "113012",
                        codingSchemeDesignator: "DCM",
                        codeMeaning: "Key Object Description"
                    ),
                    textValue: description,
                    relationshipType: .contains
                )
                contentItems.append(AnyContentItem(textItem))
            }
            
            // Add the referenced object using ImageReference
            let imageRef = ImageReference(
                sopClassUID: keyObject.sopClassUID,
                sopInstanceUID: keyObject.sopInstanceUID,
                frameNumbers: keyObject.frames
            )
            
            let imageItem = ImageContentItem(
                conceptName: nil,
                imageReference: imageRef,
                relationshipType: .contains
            )
            contentItems.append(AnyContentItem(imageItem))
        }
        
        // Create the root container with the document title as its concept name
        let title = documentTitle?.concept ?? CodedConcept(
            codeValue: "113000",
            codingSchemeDesignator: "DCM",
            codeMeaning: "Of Interest"
        )
        
        let rootContainer = ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: contentItems
        )
        
        return rootContainer
    }
    
    private func validate() throws {
        // At least one key object must be present
        if keyObjects.isEmpty {
            throw BuildError.validationError(
                "Key Object Selection document must contain at least one referenced object"
            )
        }
    }
}

// MARK: - Supporting Types

/// Represents a key object (referenced instance) in a KOS document
public struct KeyObject: Sendable, Equatable {
    /// SOP Class UID of the referenced instance
    public let sopClassUID: String
    
    /// SOP Instance UID of the referenced instance
    public let sopInstanceUID: String
    
    /// Optional text description
    public let description: String?
    
    /// Optional frame numbers for multi-frame images
    public let frames: [Int]?
    
    /// Creates a new key object
    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        description: String? = nil,
        frames: [Int]? = nil
    ) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.description = description
        self.frames = frames
    }
}

/// Standard document titles (purpose codes) for Key Object Selection
///
/// Based on CID 7010 - Key Object Selection Document Title
public enum DocumentTitle: Sendable, Equatable {
    /// Of Interest (113000, DCM)
    case ofInterest
    
    /// Rejected for Quality Reasons (113001, DCM)
    case rejectedForQuality
    
    /// For Referring Provider (113002, DCM)
    case forReferringProvider
    
    /// For Surgery (113003, DCM)
    case forSurgery
    
    /// For Teaching (113004, DCM)
    case forTeaching
    
    /// Quality Issue (113010, DCM)
    case qualityIssue
    
    /// Best In Set (113020, DCM)
    case bestInSet
    
    /// For Printing (113030, DCM)
    case forPrinting
    
    /// For Report Attachment (113040, DCM)
    case forReportAttachment
    
    /// Custom purpose code
    case custom(CodedConcept)
    
    /// The coded concept for this document title
    public var concept: CodedConcept {
        switch self {
        case .ofInterest:
            return CodedConcept(
                codeValue: "113000",
                codingSchemeDesignator: "DCM",
                codeMeaning: "Of Interest"
            )
        case .rejectedForQuality:
            return CodedConcept(
                codeValue: "113001",
                codingSchemeDesignator: "DCM",
                codeMeaning: "Rejected for Quality Reasons"
            )
        case .forReferringProvider:
            return CodedConcept(
                codeValue: "113002",
                codingSchemeDesignator: "DCM",
                codeMeaning: "For Referring Provider"
            )
        case .forSurgery:
            return CodedConcept(
                codeValue: "113003",
                codingSchemeDesignator: "DCM",
                codeMeaning: "For Surgery"
            )
        case .forTeaching:
            return CodedConcept(
                codeValue: "113004",
                codingSchemeDesignator: "DCM",
                codeMeaning: "For Teaching"
            )
        case .qualityIssue:
            return CodedConcept(
                codeValue: "113010",
                codingSchemeDesignator: "DCM",
                codeMeaning: "Quality Issue"
            )
        case .bestInSet:
            return CodedConcept(
                codeValue: "113013",
                codingSchemeDesignator: "DCM",
                codeMeaning: "Best In Set"
            )
        case .forPrinting:
            return CodedConcept(
                codeValue: "113018",
                codingSchemeDesignator: "DCM",
                codeMeaning: "For Printing"
            )
        case .forReportAttachment:
            return CodedConcept(
                codeValue: "113020",
                codingSchemeDesignator: "DCM",
                codeMeaning: "For Report Attachment"
            )
        case .custom(let concept):
            return concept
        }
    }
}
