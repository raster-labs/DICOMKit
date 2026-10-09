// NEMA-verified: 2026a, checked 2026-09-29 — SCOORD3D graphic types match PS3.3 2026a C.18.9.1.2; Referenced Frame of Reference UID per Table C.18.9-1; validation recurses into the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31)
/// Comprehensive 3D SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Comprehensive 3D SR documents.
/// Comprehensive 3D SR extends Comprehensive SR by adding support for 3D spatial coordinates
/// (SCOORD3D), enabling representation of volumetric annotations, 3D ROIs, and 3D measurements
/// in patient coordinate systems.
///
/// Reference: PS3.3 Section A.35.13 - Comprehensive 3D SR
/// Reference: PS3.4 Annex B - Storage Service Class (Comprehensive 3D SR)

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Comprehensive 3D SR documents
///
/// Comprehensive3DSRBuilder provides an API for creating structured reports that include
/// 3D spatial coordinates for volumetric annotations, 3D ROI definitions, and measurements
/// in 3D space. This is essential for advanced imaging modalities like CT, MRI, and PET
/// where measurements and annotations are referenced in a common 3D coordinate system.
///
/// Example:
/// ```swift
/// let document = try Comprehensive3DSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle("3D Lesion Analysis")
///     .withFrameOfReferenceUID("1.2.840.10008.5.1.4.1.1.88.34")
///     .addSection("Findings") { section in
///         section.addText("Lesion identified in liver segment VII.")
///         section.addNumeric(
///             conceptName: CodedConcept.diameter,
///             value: 25.5,
///             units: UCUMUnit.millimeter.asCodedConcept()
///         )
///         section.addSpatialCoordinates3D(
///             conceptName: CodedConcept(
///                 codeValue: "111030",
///                 codingSchemeDesignator: "DCM",
///                 codeMeaning: "Image Region"
///             ),
///             graphicType: .ellipsoid,
///             graphicData: [100.0, 100.0, 50.0, 120.0, 100.0, 50.0, 110.0, 120.0, 50.0, 110.0, 100.0, 60.0, 110.0, 100.0, 40.0, 100.0, 110.0, 50.0]
///         )
///     }
///     .build()
/// ```
///
/// ## Supported Value Types
/// Comprehensive 3D SR supports all Comprehensive SR value types plus:
/// - SCOORD3D - 3D spatial coordinates (points, polylines, polygons, ellipses, ellipsoids)
///
/// Supported from Comprehensive SR:
/// - SCOORD - 2D spatial coordinates
/// - TCOORD - Temporal coordinates
/// - TEXT - Free-form text content
/// - CODE - Coded concept values
/// - NUM - Numeric measurements with units
/// - DATETIME, DATE, TIME - Temporal values
/// - UIDREF - UID reference values
/// - PNAME - Person name values
/// - COMPOSITE, IMAGE - Reference types
/// - WAVEFORM - Waveform references
/// - CONTAINER - For hierarchical structure
///
/// ## Frame of Reference
/// 3D spatial coordinates require a Frame of Reference UID to define the coordinate system.
/// This is typically shared across a series of images. Use `withFrameOfReferenceUID()` to
/// set the default frame of reference for all 3D coordinates, or provide it per-coordinate.
public struct Comprehensive3DSRBuilder: Sendable {
    
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
    
    /// Document Title (Concept Name of root container)
    public private(set) var documentTitle: CodedConcept?
    
    /// Simple string document title (converted to coded concept)
    public private(set) var documentTitleString: String?
    
    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .partial
    
    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified
    
    /// Preliminary Flag
    public private(set) var preliminaryFlag: PreliminaryFlag?
    
    // MARK: - 3D Coordinate Information
    
    /// Default Frame of Reference UID for 3D coordinates
    public private(set) var frameOfReferenceUID: String?
    
    // MARK: - Content Tree
    
    /// Root-level content items (sections, text, measurements, coordinates)
    public private(set) var contentItems: [AnyContentItem] = []
    
    // MARK: - Initialization
    
    /// Creates a new Comprehensive 3D SR document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the document title from a coded concept
    /// - Parameter title: The document title as a coded concept
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.documentTitle = title
        copy.documentTitleString = nil
        return copy
    }
    
    /// Sets the document title from a string
    /// - Parameter title: The document title as a simple string
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.documentTitleString = title
        copy.documentTitle = nil
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.preliminaryFlag = flag
        return copy
    }
    
    // MARK: - 3D Coordinate Information Setters
    
    /// Sets the default Frame of Reference UID for 3D coordinates
    /// - Parameter uid: The Frame of Reference UID
    /// - Returns: Updated builder
    public func withFrameOfReferenceUID(_ uid: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.frameOfReferenceUID = uid
        return copy
    }
    
    // MARK: - Section Building
    
    /// Adds a section (container) with a concept name and nested content
    /// - Parameters:
    ///   - conceptName: The concept name for this section
    ///   - builder: A result builder closure that produces the section content items
    /// - Returns: Updated builder
    public func addSection(
        _ conceptName: CodedConcept,
        @Comprehensive3DSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        let sectionItems = builder()
        let section = ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: .separate,
            contentItems: sectionItems,
            relationshipType: .contains
        )
        copy.contentItems.append(AnyContentItem(section))
        return copy
    }
    
    /// Adds a section (container) with a string heading and nested content
    /// - Parameters:
    ///   - heading: The heading for this section (converted to coded concept)
    ///   - builder: A result builder closure that produces the section content items
    /// - Returns: Updated builder
    public func addSection(
        _ heading: String,
        @Comprehensive3DSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.sectionHeading(heading), builder: builder)
    }
    
    // MARK: - Content Addition - Text
    
    /// Adds a text content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - text: The text content
    /// - Returns: Updated builder
    public func addText(conceptName: CodedConcept? = nil, text: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: text,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a labeled text content item
    /// - Parameters:
    ///   - label: The label for the text
    ///   - text: The text content
    /// - Returns: Updated builder
    public func addLabeledText(label: String, text: String) -> Comprehensive3DSRBuilder {
        addText(conceptName: CodedConcept.textLabel(label), text: text)
    }
    
    // MARK: - Content Addition - Coded Concepts
    
    /// Adds a code content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - code: The coded concept value
    /// - Returns: Updated builder
    public func addCode(conceptName: CodedConcept? = nil, code: CodedConcept) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: code,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - Numeric
    
    /// Adds a numeric measurement with units
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: Updated builder
    public func addNumeric(conceptName: CodedConcept? = nil, value: Double, units: CodedConcept? = nil) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a labeled measurement
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: Updated builder
    public func addMeasurement(label: String, value: Double, units: CodedConcept) -> Comprehensive3DSRBuilder {
        addNumeric(conceptName: CodedConcept.textLabel(label), value: value, units: units)
    }
    
    /// Adds a measurement with a label and value in millimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in millimeters
    /// - Returns: Updated builder
    public func addMeasurementMM(label: String, value: Double) -> Comprehensive3DSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.millimeter.concept)
    }
    
    /// Adds a measurement with a label and value in centimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in centimeters
    /// - Returns: Updated builder
    public func addMeasurementCM(label: String, value: Double) -> Comprehensive3DSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.centimeter.concept)
    }
    
    // MARK: - Content Addition - 3D Spatial Coordinates
    
    /// Adds a 3D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - graphicType: The type of 3D graphic (point, polyline, polygon, ellipse, ellipsoid, multipoint)
    ///   - graphicData: The coordinate data as [x1, y1, z1, x2, y2, z2, ...]
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addSpatialCoordinates3D(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType3D,
        graphicData: [Float],
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        let finalFrameOfReferenceUID = frameOfReferenceUID ?? self.frameOfReferenceUID
        copy.contentItems.append(AnyContentItem(SpatialCoordinates3DContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            frameOfReferenceUID: finalFrameOfReferenceUID,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a single 3D point coordinate
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - x: The x coordinate
    ///   - y: The y coordinate
    ///   - z: The z coordinate
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addPoint3D(
        conceptName: CodedConcept? = nil,
        x: Float,
        y: Float,
        z: Float,
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .point,
            graphicData: [x, y, z],
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    /// Adds a 3D polyline coordinate (connected line segments)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - points: Array of (x, y, z) tuples
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addPolyline3D(
        conceptName: CodedConcept? = nil,
        points: [(x: Float, y: Float, z: Float)],
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        let graphicData = points.flatMap { [$0.x, $0.y, $0.z] }
        return addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .polyline,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    /// Adds a 3D polygon coordinate (closed shape)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - points: Array of (x, y, z) tuples forming the polygon vertices
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addPolygon3D(
        conceptName: CodedConcept? = nil,
        points: [(x: Float, y: Float, z: Float)],
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        let graphicData = points.flatMap { [$0.x, $0.y, $0.z] }
        return addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .polygon,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    /// Adds a 3D ellipse coordinate
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - majorAxisEndpoint1: First endpoint of the major axis
    ///   - majorAxisEndpoint2: Second endpoint of the major axis
    ///   - minorAxisEndpoint1: First endpoint of the minor axis
    ///   - minorAxisEndpoint2: Second endpoint of the minor axis
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addEllipse3D(
        conceptName: CodedConcept? = nil,
        majorAxisEndpoint1: (x: Float, y: Float, z: Float),
        majorAxisEndpoint2: (x: Float, y: Float, z: Float),
        minorAxisEndpoint1: (x: Float, y: Float, z: Float),
        minorAxisEndpoint2: (x: Float, y: Float, z: Float),
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .ellipse,
            graphicData: [
                majorAxisEndpoint1.x, majorAxisEndpoint1.y, majorAxisEndpoint1.z,
                majorAxisEndpoint2.x, majorAxisEndpoint2.y, majorAxisEndpoint2.z,
                minorAxisEndpoint1.x, minorAxisEndpoint1.y, minorAxisEndpoint1.z,
                minorAxisEndpoint2.x, minorAxisEndpoint2.y, minorAxisEndpoint2.z
            ],
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    /// Adds a 3D ellipsoid coordinate
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - firstAxis: Endpoints of the first axis
    ///   - secondAxis: Endpoints of the second axis
    ///   - thirdAxis: Endpoints of the third axis
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addEllipsoid(
        conceptName: CodedConcept? = nil,
        firstAxis: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float)),
        secondAxis: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float)),
        thirdAxis: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float)),
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .ellipsoid,
            graphicData: [
                firstAxis.point1.x, firstAxis.point1.y, firstAxis.point1.z,
                firstAxis.point2.x, firstAxis.point2.y, firstAxis.point2.z,
                secondAxis.point1.x, secondAxis.point1.y, secondAxis.point1.z,
                secondAxis.point2.x, secondAxis.point2.y, secondAxis.point2.z,
                thirdAxis.point1.x, thirdAxis.point1.y, thirdAxis.point1.z,
                thirdAxis.point2.x, thirdAxis.point2.y, thirdAxis.point2.z
            ],
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    /// Adds multiple disconnected 3D points
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - points: Array of (x, y, z) tuples
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    /// - Returns: Updated builder
    public func addMultipoint3D(
        conceptName: CodedConcept? = nil,
        points: [(x: Float, y: Float, z: Float)],
        frameOfReferenceUID: String? = nil
    ) -> Comprehensive3DSRBuilder {
        let graphicData = points.flatMap { [$0.x, $0.y, $0.z] }
        return addSpatialCoordinates3D(
            conceptName: conceptName,
            graphicType: .multipoint,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID
        )
    }
    
    // MARK: - Content Addition - 2D Spatial Coordinates
    
    /// Adds a 2D spatial coordinates content item (from Comprehensive SR)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - graphicType: The type of graphic (point, polyline, polygon, circle, ellipse)
    ///   - graphicData: The coordinate data as [col1, row1, col2, row2, ...]
    /// - Returns: Updated builder
    public func addSpatialCoordinates(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType,
        graphicData: [Float]
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - Temporal Coordinates
    
    /// Adds temporal coordinates with sample positions (for waveform data)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - temporalRangeType: The type of temporal range
    ///   - samplePositions: Sample positions in the waveform
    /// - Returns: Updated builder
    public func addTemporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        samplePositions: [UInt32]
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            samplePositions: samplePositions,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - Dates and Times
    
    /// Adds a date content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - date: The date value in DICOM DA format
    /// - Returns: Updated builder
    public func addDate(conceptName: CodedConcept? = nil, date: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: date,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a time content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - time: The time value in DICOM TM format
    /// - Returns: Updated builder
    public func addTime(conceptName: CodedConcept? = nil, time: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: time,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a datetime content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - datetime: The datetime value in DICOM DT format
    /// - Returns: Updated builder
    public func addDateTime(conceptName: CodedConcept? = nil, datetime: String) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: datetime,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - References
    
    /// Adds an image reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced image
    ///   - sopInstanceUID: The SOP Instance UID of the referenced image
    ///   - frameNumbers: Optional frame numbers
    /// - Returns: Updated builder
    public func addImageReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a composite reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced composite object
    ///   - sopInstanceUID: The SOP Instance UID of the referenced composite object
    /// - Returns: Updated builder
    public func addCompositeReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CompositeContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a waveform reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced waveform
    ///   - sopInstanceUID: The SOP Instance UID of the referenced waveform
    ///   - channelNumbers: Optional channel numbers
    /// - Returns: Updated builder
    public func addWaveformReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        channelNumbers: [Int]? = nil
    ) -> Comprehensive3DSRBuilder {
        var copy = self
        let sopRef = ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        let waveformRef = WaveformReference(
            sopReference: sopRef,
            channelNumbers: channelNumbers
        )
        copy.contentItems.append(AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a pre-built content item
    /// - Parameter item: The content item to add
    /// - Returns: Updated builder
    public func addItem(_ item: AnyContentItem) -> Comprehensive3DSRBuilder {
        var copy = self
        copy.contentItems.append(item)
        return copy
    }
    
    // MARK: - Common Report Sections
    
    /// Adds a "Findings" section with text content
    /// - Parameter text: The findings text
    /// - Returns: Updated builder
    public func addFindings(_ text: String) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.findings) {
            Comprehensive3DSectionContent.text(text)
        }
    }
    
    /// Adds an "Impression" section with text content
    /// - Parameter text: The impression text
    /// - Returns: Updated builder
    public func addImpression(_ text: String) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.impression) {
            Comprehensive3DSectionContent.text(text)
        }
    }
    
    /// Adds a "Clinical History" section with text content
    /// - Parameter text: The clinical history text
    /// - Returns: Updated builder
    public func addClinicalHistory(_ text: String) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.clinicalHistory) {
            Comprehensive3DSectionContent.text(text)
        }
    }
    
    /// Adds a "Conclusion" section with text content
    /// - Parameter text: The conclusion text
    /// - Returns: Updated builder
    public func addConclusion(_ text: String) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.conclusion) {
            Comprehensive3DSectionContent.text(text)
        }
    }
    
    /// Adds a "Recommendation" section with text content
    /// - Parameter text: The recommendation text
    /// - Returns: Updated builder
    public func addRecommendation(_ text: String) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.recommendation) {
            Comprehensive3DSectionContent.text(text)
        }
    }
    
    /// Adds a "Measurements" section with nested measurements
    /// - Parameter builder: A closure that builds the measurements section content
    /// - Returns: Updated builder
    public func addMeasurements(
        @Comprehensive3DSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.measurements, builder: builder)
    }
    
    // MARK: - 3D ROI Definition Helpers
    
    /// Adds a 3D ROI (Region of Interest) with a label, ellipsoid shape, and optional measurement
    /// - Parameters:
    ///   - label: The ROI label
    ///   - ellipsoidAxes: The three axes of the ellipsoid
    ///   - frameOfReferenceUID: Optional Frame of Reference UID (uses default if not provided)
    ///   - volume: Optional volume measurement in cubic millimeters
    /// - Returns: Updated builder
    public func add3DROI(
        label: String,
        ellipsoidAxes: (
            first: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float)),
            second: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float)),
            third: (point1: (x: Float, y: Float, z: Float), point2: (x: Float, y: Float, z: Float))
        ),
        frameOfReferenceUID: String? = nil,
        volume: Double? = nil
    ) -> Comprehensive3DSRBuilder {
        addSection(CodedConcept.textLabel(label)) {
            let coords = Comprehensive3DSectionContent.spatialCoordinates3D(
                graphicType: .ellipsoid,
                graphicData: [
                    ellipsoidAxes.first.point1.x, ellipsoidAxes.first.point1.y, ellipsoidAxes.first.point1.z,
                    ellipsoidAxes.first.point2.x, ellipsoidAxes.first.point2.y, ellipsoidAxes.first.point2.z,
                    ellipsoidAxes.second.point1.x, ellipsoidAxes.second.point1.y, ellipsoidAxes.second.point1.z,
                    ellipsoidAxes.second.point2.x, ellipsoidAxes.second.point2.y, ellipsoidAxes.second.point2.z,
                    ellipsoidAxes.third.point1.x, ellipsoidAxes.third.point1.y, ellipsoidAxes.third.point1.z,
                    ellipsoidAxes.third.point2.x, ellipsoidAxes.third.point2.y, ellipsoidAxes.third.point2.z
                ],
                frameOfReferenceUID: frameOfReferenceUID ?? self.frameOfReferenceUID
            )
            
            if let volume = volume {
                return [
                    coords,
                    Comprehensive3DSectionContent.measurement(
                        label: "Volume",
                        value: volume,
                        units: UCUMUnit.cubicMillimeter.concept
                    )
                ]
            } else {
                return [coords]
            }
        }
    }
    
    // MARK: - Build
    
    /// Builds the Comprehensive 3D SR document
    /// - Returns: The constructed SR document
    /// - Throws: `BuildError` if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        
        // Determine document title
        let finalDocumentTitle: CodedConcept?
        if let title = documentTitle {
            finalDocumentTitle = title
        } else if let titleString = documentTitleString {
            finalDocumentTitle = CodedConcept.documentTitle(titleString)
        } else {
            finalDocumentTitle = nil
        }
        
        // Create the root container
        let rootContent = ContainerContentItem(
            conceptName: finalDocumentTitle,
            continuityOfContent: .separate,
            contentItems: contentItems
        )
        
        return SRDocument(
            sopClassUID: SRDocumentType.comprehensive3DSR.sopClassUID,
            sopInstanceUID: finalSOPInstanceUID,
            patientID: patientID,
            patientName: patientName,
            studyInstanceUID: finalStudyInstanceUID,
            studyDate: studyDate,
            studyTime: studyTime,
            accessionNumber: accessionNumber,
            seriesInstanceUID: finalSeriesInstanceUID,
            seriesNumber: seriesNumber,
            modality: "SR",
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: instanceNumber,
            completionFlag: completionFlag,
            verificationFlag: verificationFlag,
            preliminaryFlag: preliminaryFlag,
            documentTitle: finalDocumentTitle,
            rootContent: rootContent,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName
        )
    }
    
    // MARK: - Validation
    
    /// Validation errors for Comprehensive 3D SR documents
    public enum BuildError: Error, Sendable, Equatable {
        /// 3D coordinates require a Frame of Reference UID
        case missingFrameOfReferenceUID
        
        /// Description of the error
        public var localizedDescription: String {
            switch self {
            case .missingFrameOfReferenceUID:
                return "3D spatial coordinates require a Frame of Reference UID. Set it via withFrameOfReferenceUID() or provide it for each 3D coordinate."
            }
        }
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Check that 3D coordinates have a Frame of Reference UID
        try validateFrameOfReference(items: contentItems)
    }
    
    /// Validates that all 3D spatial coordinates have a Frame of Reference UID
    private func validateFrameOfReference(items: [AnyContentItem]) throws {
        for item in items {
            // Check if this is a 3D coordinate without a Frame of Reference UID
            if let scoord3D = item.asSpatialCoordinates3D {
                if scoord3D.frameOfReferenceUID == nil && frameOfReferenceUID == nil {
                    throw BuildError.missingFrameOfReferenceUID
                }
            }
            
            // Recursively validate children: a CONTAINER's, and the Content Sequence
            // any other value type may carry (PS3.3 Table C.17-6)
            try validateFrameOfReference(items: item.contentItems)
        }
    }
}

// MARK: - Comprehensive 3D Section Content Builder

/// Result builder for constructing Comprehensive 3D SR section content items
@resultBuilder
public struct Comprehensive3DSectionContentBuilder {
    /// Builds an empty block
    public static func buildBlock() -> [AnyContentItem] {
        []
    }
    
    /// Builds a block from arrays of content items
    public static func buildBlock(_ components: [AnyContentItem]...) -> [AnyContentItem] {
        components.flatMap { $0 }
    }
    
    /// Builds a block from arrays of content items
    public static func buildArray(_ components: [[AnyContentItem]]) -> [AnyContentItem] {
        components.flatMap { $0 }
    }
    
    public static func buildOptional(_ component: [AnyContentItem]?) -> [AnyContentItem] {
        component ?? []
    }
    
    public static func buildEither(first component: [AnyContentItem]) -> [AnyContentItem] {
        component
    }
    
    public static func buildEither(second component: [AnyContentItem]) -> [AnyContentItem] {
        component
    }
    
    /// Builds from an expression (single item)
    public static func buildExpression(_ expression: AnyContentItem) -> [AnyContentItem] {
        [expression]
    }
}

// MARK: - Comprehensive 3D Section Content Helpers

/// Helper enum for building Comprehensive 3D SR section content
public enum Comprehensive3DSectionContent {
    /// Creates a text content item
    /// - Parameters:
    ///   - value: The text value
    ///   - conceptName: Optional concept name
    /// - Returns: The content item
    public static func text(_ value: String, conceptName: CodedConcept? = nil) -> AnyContentItem {
        AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a labeled text content item
    /// - Parameters:
    ///   - label: The label for the text
    ///   - value: The text value
    /// - Returns: The content item
    public static func labeledText(label: String, value: String) -> AnyContentItem {
        AnyContentItem(TextContentItem(
            conceptName: CodedConcept.textLabel(label),
            textValue: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a numeric content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: The content item
    public static func numeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: .contains
        ))
    }
    
    /// Creates a numeric content item with a label and units
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: The content item
    public static func measurement(
        label: String,
        value: Double,
        units: CodedConcept
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: CodedConcept.textLabel(label),
            value: value,
            units: units,
            relationshipType: .contains
        ))
    }
    
    /// Creates a 3D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - graphicType: The type of 3D graphic
    ///   - graphicData: The coordinate data as [x1, y1, z1, x2, y2, z2, ...]
    ///   - frameOfReferenceUID: Optional Frame of Reference UID
    /// - Returns: The content item
    public static func spatialCoordinates3D(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType3D,
        graphicData: [Float],
        frameOfReferenceUID: String? = nil
    ) -> AnyContentItem {
        AnyContentItem(SpatialCoordinates3DContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID,
            relationshipType: .contains
        ))
    }
    
    /// Creates a code content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - code: The coded concept value
    /// - Returns: The content item
    public static func code(conceptName: CodedConcept? = nil, code: CodedConcept) -> AnyContentItem {
        AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: code,
            relationshipType: .contains
        ))
    }
    
    /// Creates an image reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - frameNumbers: Optional frame numbers
    /// - Returns: The content item
    public static func imageReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) -> AnyContentItem {
        AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            relationshipType: .contains
        ))
    }
}
