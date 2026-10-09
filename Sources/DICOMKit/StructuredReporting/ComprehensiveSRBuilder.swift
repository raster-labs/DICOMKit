// NEMA-verified: 2026a, checked 2026-09-29 — 2D SCOORD closed shapes are POLYLINE with the first vertex repeated, per PS3.3 2026a C.18.6.1.2 (D18); regionOfInterest, measurementLocation and temporalExtent against PS3.16 2026a Table D-1, CID 9000, CID 10073, TID 1410 row 8b, TID 301 row 5; validation recurses into the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31)
/// Comprehensive SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Comprehensive SR documents.
/// Comprehensive SR extends Enhanced SR by adding support for spatial coordinates (SCOORD),
/// temporal coordinates (TCOORD), and by-reference relationships. This is the most commonly
/// used SR type for measurement reports and clinical findings.
///
/// Reference: PS3.3 Section A.35.3 - Comprehensive SR
/// Reference: PS3.4 Annex B - Storage Service Class (Comprehensive SR)

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Comprehensive SR documents
///
/// ComprehensiveSRBuilder provides an API for creating structured reports that include
/// spatial coordinates (2D annotations on images), temporal coordinates (time-based references),
/// and all features supported by Enhanced SR.
///
/// Example:
/// ```swift
/// let document = try ComprehensiveSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle("Measurement Report")
///     .addSection("Findings") { section in
///         section.addText("Lesion identified in liver segment VII.")
///         section.addNumeric(
///             conceptName: CodedConcept.diameter,
///             value: 25.5,
///             units: UCUMUnit.millimeter.asCodedConcept()
///         )
///         section.addSpatialCoordinates(
///             conceptName: CodedConcept(
///                 codeValue: "111030",
///                 codingSchemeDesignator: "DCM",
///                 codeMeaning: "Image Region"
///             ),
///             graphicType: .circle,
///             graphicData: [100.0, 100.0, 120.0, 100.0]
///         )
///     }
///     .build()
/// ```
///
/// ## Supported Value Types
/// Comprehensive SR supports all Enhanced SR value types plus:
/// - SCOORD - 2D spatial coordinates (points, polylines, polygons, circles, ellipses)
/// - TCOORD - Temporal coordinates (time points, ranges, segments)
///
/// Supported from Enhanced SR:
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
/// Note: SCOORD3D (3D spatial coordinates) is NOT supported in Comprehensive SR.
/// Use `Comprehensive3DSRBuilder` or `SRDocumentBuilder` with `.comprehensive3DSR`
/// for reports requiring 3D coordinates.
public struct ComprehensiveSRBuilder: Sendable {
    
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
    
    // MARK: - Content Tree
    
    /// Root-level content items (sections, text, measurements, coordinates)
    public private(set) var contentItems: [AnyContentItem] = []
    
    // MARK: - Initialization
    
    /// Creates a new Comprehensive SR document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title using a coded concept
    /// - Parameter title: The document title as a coded concept
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> ComprehensiveSRBuilder {
        var copy = self
        copy.documentTitle = title
        copy.documentTitleString = nil
        return copy
    }
    
    /// Sets the Document Title using a simple string
    ///
    /// This method creates a coded concept using the code "121060" (Document Title)
    /// from the DCM coding scheme with your provided text as the code meaning.
    ///
    /// - Parameter title: The document title as a simple string
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.documentTitleString = title
        copy.documentTitle = nil
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> ComprehensiveSRBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> ComprehensiveSRBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> ComprehensiveSRBuilder {
        var copy = self
        copy.preliminaryFlag = flag
        return copy
    }
    
    // MARK: - Content Addition - Text
    
    /// Adds a text content item at the root level
    /// - Parameters:
    ///   - value: The text value
    ///   - conceptName: Optional concept name for the text item
    /// - Returns: Updated builder
    public func addText(_ value: String, conceptName: CodedConcept? = nil) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a labeled text content item (text with a string label)
    /// - Parameters:
    ///   - label: The label for the text (used as code meaning)
    ///   - value: The text value
    /// - Returns: Updated builder
    public func addLabeledText(label: String, value: String) -> ComprehensiveSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addText(value, conceptName: conceptName)
    }
    
    // MARK: - Content Addition - Numeric Measurements
    
    /// Adds a numeric measurement content item
    /// - Parameters:
    ///   - conceptName: The concept name for this measurement
    ///   - value: The numeric value
    ///   - units: The measurement units (coded concept)
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a numeric measurement with multiple values
    /// - Parameters:
    ///   - conceptName: The concept name for this measurement
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - qualifier: Optional qualifier for special values (e.g., "below detectable limit")
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        qualifier: NumericValueQualifier? = nil
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: values,
            units: units,
            floatingPointValues: nil,
            qualifier: qualifier,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a measurement with a label and value in millimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in millimeters
    /// - Returns: Updated builder
    public func addMeasurementMM(label: String, value: Double) -> ComprehensiveSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.millimeter.concept)
    }
    
    /// Adds a measurement with a label and value in centimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in centimeters
    /// - Returns: Updated builder
    public func addMeasurementCM(label: String, value: Double) -> ComprehensiveSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.centimeter.concept)
    }
    
    // MARK: - Content Addition - Spatial Coordinates (2D)
    
    /// Adds a 2D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - graphicType: The type of graphic (point, polyline, polygon, circle, ellipse)
    ///   - graphicData: The coordinate data as [col1, row1, col2, row2, ...]
    /// - Returns: Updated builder
    public func addSpatialCoordinates(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType,
        graphicData: [Float]
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a point coordinate (single 2D point)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - column: The column (x) coordinate
    ///   - row: The row (y) coordinate
    /// - Returns: Updated builder
    public func addPoint(
        conceptName: CodedConcept? = nil,
        column: Float,
        row: Float
    ) -> ComprehensiveSRBuilder {
        addSpatialCoordinates(
            conceptName: conceptName,
            graphicType: .point,
            graphicData: [column, row]
        )
    }
    
    /// Adds a polyline coordinate (connected line segments)
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - points: Array of (column, row) tuples
    /// - Returns: Updated builder
    public func addPolyline(
        conceptName: CodedConcept? = nil,
        points: [(column: Float, row: Float)]
    ) -> ComprehensiveSRBuilder {
        let graphicData = points.flatMap { [$0.column, $0.row] }
        return addSpatialCoordinates(
            conceptName: conceptName,
            graphicType: .polyline,
            graphicData: graphicData
        )
    }
    
    /// Adds a polygon coordinate (closed shape)
    ///
    /// PS3.3 C.18.6.1.2 defines no POLYGON Graphic Type for 2D SCOORD; a closed shape is a
    /// POLYLINE whose first and last vertices are the same, so the first vertex is repeated
    /// last unless the caller already closed the shape.
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - points: Array of (column, row) tuples forming the polygon vertices
    /// - Returns: Updated builder
    public func addPolygon(
        conceptName: CodedConcept? = nil,
        points: [(column: Float, row: Float)]
    ) -> ComprehensiveSRBuilder {
        addSpatialCoordinates(
            conceptName: conceptName,
            graphicType: .polyline,
            graphicData: ComprehensiveSectionContent.closedPolylineData(points)
        )
    }
    
    /// Adds a circle coordinate
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - centerColumn: The column (x) coordinate of the center
    ///   - centerRow: The row (y) coordinate of the center
    ///   - edgeColumn: The column (x) coordinate of a point on the circumference
    ///   - edgeRow: The row (y) coordinate of a point on the circumference
    /// - Returns: Updated builder
    public func addCircle(
        conceptName: CodedConcept? = nil,
        centerColumn: Float,
        centerRow: Float,
        edgeColumn: Float,
        edgeRow: Float
    ) -> ComprehensiveSRBuilder {
        addSpatialCoordinates(
            conceptName: conceptName,
            graphicType: .circle,
            graphicData: [centerColumn, centerRow, edgeColumn, edgeRow]
        )
    }
    
    /// Adds an ellipse coordinate
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - majorAxisEndpoint1: First endpoint of the major axis
    ///   - majorAxisEndpoint2: Second endpoint of the major axis
    ///   - minorAxisEndpoint1: First endpoint of the minor axis
    ///   - minorAxisEndpoint2: Second endpoint of the minor axis
    /// - Returns: Updated builder
    public func addEllipse(
        conceptName: CodedConcept? = nil,
        majorAxisEndpoint1: (column: Float, row: Float),
        majorAxisEndpoint2: (column: Float, row: Float),
        minorAxisEndpoint1: (column: Float, row: Float),
        minorAxisEndpoint2: (column: Float, row: Float)
    ) -> ComprehensiveSRBuilder {
        addSpatialCoordinates(
            conceptName: conceptName,
            graphicType: .ellipse,
            graphicData: [
                majorAxisEndpoint1.column, majorAxisEndpoint1.row,
                majorAxisEndpoint2.column, majorAxisEndpoint2.row,
                minorAxisEndpoint1.column, minorAxisEndpoint1.row,
                minorAxisEndpoint2.column, minorAxisEndpoint2.row
            ]
        )
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
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            samplePositions: samplePositions,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds temporal coordinates with time offsets
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - temporalRangeType: The type of temporal range
    ///   - timeOffsets: Time offsets in seconds
    /// - Returns: Updated builder
    public func addTemporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        timeOffsets: [Double]
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            timeOffsets: timeOffsets,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds temporal coordinates with datetime values
    /// - Parameters:
    ///   - conceptName: The concept name for this coordinate
    ///   - temporalRangeType: The type of temporal range
    ///   - dateTimes: DateTime values in DICOM DT format
    /// - Returns: Updated builder
    public func addTemporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        dateTimes: [String]
    ) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            dateTimes: dateTimes,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - Sections
    
    /// Adds a section (container) with nested content
    ///
    /// Sections provide hierarchical organization for Comprehensive SR documents.
    /// Each section can contain text, codes, numeric measurements, spatial coordinates,
    /// temporal coordinates, and nested subsections.
    ///
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - builder: A closure that builds the section's content using a ComprehensiveSectionContentBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: CodedConcept,
        @ComprehensiveSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> ComprehensiveSRBuilder {
        var copy = self
        let items = builder()
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a section with a string title
    ///
    /// This method creates a section with a coded concept using the string as the code meaning.
    ///
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - builder: A closure that builds the section's content using a ComprehensiveSectionContentBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: String,
        @ComprehensiveSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> ComprehensiveSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, builder: builder)
    }
    
    /// Adds a section with pre-built content items
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - items: The content items for the section
    /// - Returns: Updated builder
    public func addSection(_ title: CodedConcept, items: [AnyContentItem]) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a section with a string title and pre-built content items
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - items: The content items for the section
    /// - Returns: Updated builder
    public func addSection(_ title: String, items: [AnyContentItem]) -> ComprehensiveSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, items: items)
    }
    
    // MARK: - Content Addition - Codes
    
    /// Adds a code content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The coded value
    /// - Returns: Updated builder
    public func addCode(conceptName: CodedConcept?, value: CodedConcept) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - References
    
    /// Adds a person name content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - name: The person name in DICOM PN format
    /// - Returns: Updated builder
    public func addPersonName(conceptName: CodedConcept? = nil, name: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: name,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a UID reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - uid: The UID value
    /// - Returns: Updated builder
    public func addUIDRef(conceptName: CodedConcept? = nil, uid: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(UIDRefContentItem(
            conceptName: conceptName,
            uidValue: uid,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a date content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - date: The date value in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func addDate(conceptName: CodedConcept? = nil, date: String) -> ComprehensiveSRBuilder {
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
    public func addTime(conceptName: CodedConcept? = nil, time: String) -> ComprehensiveSRBuilder {
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
    public func addDateTime(conceptName: CodedConcept? = nil, datetime: String) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: datetime,
            relationshipType: .contains
        )))
        return copy
    }
    
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
    ) -> ComprehensiveSRBuilder {
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
    ) -> ComprehensiveSRBuilder {
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
    ) -> ComprehensiveSRBuilder {
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
    public func addItem(_ item: AnyContentItem) -> ComprehensiveSRBuilder {
        var copy = self
        copy.contentItems.append(item)
        return copy
    }
    
    // MARK: - Common Report Sections
    
    /// Adds a "Findings" section with text content
    /// - Parameter text: The findings text
    /// - Returns: Updated builder
    public func addFindings(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.findings) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds an "Impression" section with text content
    /// - Parameter text: The impression text
    /// - Returns: Updated builder
    public func addImpression(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.impression) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Clinical History" section with text content
    /// - Parameter text: The clinical history text
    /// - Returns: Updated builder
    public func addClinicalHistory(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.clinicalHistory) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Conclusion" section with text content
    /// - Parameter text: The conclusion text
    /// - Returns: Updated builder
    public func addConclusion(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.conclusion) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Recommendation" section with text content
    /// - Parameter text: The recommendation text
    /// - Returns: Updated builder
    public func addRecommendation(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.recommendation) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Procedure Description" section with text content
    /// - Parameter text: The procedure description text
    /// - Returns: Updated builder
    public func addProcedureDescription(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.procedureDescription) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Comparison" section with text content
    /// - Parameter text: The comparison text
    /// - Returns: Updated builder
    public func addComparison(_ text: String) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.comparison) {
            ComprehensiveSectionContent.text(text)
        }
    }
    
    /// Adds a "Measurements" section with nested measurements
    /// - Parameter builder: A closure that builds the measurements section content
    /// - Returns: Updated builder
    public func addMeasurements(
        @ComprehensiveSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> ComprehensiveSRBuilder {
        addSection(CodedConcept.measurements, builder: builder)
    }
    
    // MARK: - Build
    
    /// Builds the Comprehensive SR document
    /// - Returns: The constructed SR document
    /// - Throws: `BuildError` if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided.
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
            sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID,
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
    
    /// Validation errors for Comprehensive SR documents
    public enum BuildError: Error, Sendable, Equatable {
        /// Content item uses value type not allowed in Comprehensive SR
        case unsupportedValueType(valueType: ContentItemValueType)
        
        /// Description of the error
        public var localizedDescription: String {
            switch self {
            case .unsupportedValueType(let valueType):
                return "Value type '\(valueType)' is not supported in Comprehensive SR documents. Use Comprehensive3DSRBuilder or SRDocumentBuilder with .comprehensive3DSR for 3D spatial coordinates."
            }
        }
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Check that all content items use value types compatible with Comprehensive SR
        try validateValueTypes(items: contentItems)
    }
    
    /// Validates that all content items use value types compatible with Comprehensive SR
    private func validateValueTypes(items: [AnyContentItem]) throws {
        let allowedTypes = SRDocumentType.comprehensiveSR.allowedValueTypes
        
        for item in items {
            if !allowedTypes.contains(item.valueType) {
                throw BuildError.unsupportedValueType(valueType: item.valueType)
            }
            
            // Recursively validate children: a CONTAINER's, and the Content Sequence
            // any other value type may carry (PS3.3 Table C.17-6)
            try validateValueTypes(items: item.contentItems)
        }
    }
}

// MARK: - Comprehensive Section Content Builder

/// Result builder for constructing Comprehensive SR section content items
@resultBuilder
public struct ComprehensiveSectionContentBuilder {
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

// MARK: - Comprehensive Section Content Helpers

/// Helper enum for building Comprehensive SR section content
public enum ComprehensiveSectionContent {
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
    
    /// Creates a numeric content item with multiple values
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - qualifier: Optional qualifier for special values
    /// - Returns: The content item
    public static func numeric(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        qualifier: NumericValueQualifier? = nil
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: values,
            units: units,
            floatingPointValues: nil,
            qualifier: qualifier,
            relationshipType: .contains
        ))
    }
    
    /// Creates a 2D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - graphicType: The type of graphic
    ///   - graphicData: The coordinate data as [col1, row1, col2, row2, ...]
    /// - Returns: The content item
    public static func spatialCoordinates(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType,
        graphicData: [Float]
    ) -> AnyContentItem {
        AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            relationshipType: .contains
        ))
    }
    
    /// Creates a point coordinate (single 2D point)
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - column: The column (x) coordinate
    ///   - row: The row (y) coordinate
    /// - Returns: The content item
    public static func point(
        conceptName: CodedConcept? = nil,
        column: Float,
        row: Float
    ) -> AnyContentItem {
        spatialCoordinates(
            conceptName: conceptName,
            graphicType: .point,
            graphicData: [column, row]
        )
    }
    
    /// Creates a polyline coordinate (connected line segments)
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - points: Array of (column, row) tuples
    /// - Returns: The content item
    public static func polyline(
        conceptName: CodedConcept? = nil,
        points: [(column: Float, row: Float)]
    ) -> AnyContentItem {
        let graphicData = points.flatMap { [$0.column, $0.row] }
        return spatialCoordinates(
            conceptName: conceptName,
            graphicType: .polyline,
            graphicData: graphicData
        )
    }
    
    /// Creates a polygon coordinate (closed shape)
    ///
    /// Encoded as a closed POLYLINE (first vertex repeated last), since PS3.3 C.18.6.1.2
    /// defines POLYGON only for SCOORD3D.
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - points: Array of (column, row) tuples forming the polygon vertices
    /// - Returns: The content item
    public static func polygon(
        conceptName: CodedConcept? = nil,
        points: [(column: Float, row: Float)]
    ) -> AnyContentItem {
        spatialCoordinates(
            conceptName: conceptName,
            graphicType: .polyline,
            graphicData: closedPolylineData(points)
        )
    }

    static func closedPolylineData(_ points: [(column: Float, row: Float)]) -> [Float] {
        var vertices = points
        if let first = points.first, let last = points.last, points.count >= 2,
           first.column != last.column || first.row != last.row {
            vertices.append(first)
        }
        return vertices.flatMap { [$0.column, $0.row] }
    }
    
    /// Creates a circle coordinate
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - centerColumn: The column (x) coordinate of the center
    ///   - centerRow: The row (y) coordinate of the center
    ///   - edgeColumn: The column (x) coordinate of a point on the circumference
    ///   - edgeRow: The row (y) coordinate of a point on the circumference
    /// - Returns: The content item
    public static func circle(
        conceptName: CodedConcept? = nil,
        centerColumn: Float,
        centerRow: Float,
        edgeColumn: Float,
        edgeRow: Float
    ) -> AnyContentItem {
        spatialCoordinates(
            conceptName: conceptName,
            graphicType: .circle,
            graphicData: [centerColumn, centerRow, edgeColumn, edgeRow]
        )
    }
    
    /// Creates temporal coordinates with sample positions
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - temporalRangeType: The type of temporal range
    ///   - samplePositions: Sample positions in the waveform
    /// - Returns: The content item
    public static func temporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        samplePositions: [UInt32]
    ) -> AnyContentItem {
        AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            samplePositions: samplePositions,
            relationshipType: .contains
        ))
    }
    
    /// Creates temporal coordinates with time offsets
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - temporalRangeType: The type of temporal range
    ///   - timeOffsets: Time offsets in seconds
    /// - Returns: The content item
    public static func temporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        timeOffsets: [Double]
    ) -> AnyContentItem {
        AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            timeOffsets: timeOffsets,
            relationshipType: .contains
        ))
    }
    
    /// Creates temporal coordinates with datetime values
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - temporalRangeType: The type of temporal range
    ///   - dateTimes: DateTime values in DICOM DT format
    /// - Returns: The content item
    public static func temporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        dateTimes: [String]
    ) -> AnyContentItem {
        AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            dateTimes: dateTimes,
            relationshipType: .contains
        ))
    }
    
    /// Creates a code content item
    /// - Parameters:
    ///   - conceptName: The concept name
    ///   - value: The coded value
    /// - Returns: The content item
    public static func code(conceptName: CodedConcept?, value: CodedConcept) -> AnyContentItem {
        AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a person name content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - name: The person name
    /// - Returns: The content item
    public static func personName(conceptName: CodedConcept? = nil, name: String) -> AnyContentItem {
        AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: name,
            relationshipType: .contains
        ))
    }
    
    /// Creates a date content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - date: The date value
    /// - Returns: The content item
    public static func date(conceptName: CodedConcept? = nil, date: String) -> AnyContentItem {
        AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: date,
            relationshipType: .contains
        ))
    }
    
    /// Creates a time content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - time: The time value
    /// - Returns: The content item
    public static func time(conceptName: CodedConcept? = nil, time: String) -> AnyContentItem {
        AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: time,
            relationshipType: .contains
        ))
    }
    
    /// Creates a datetime content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - datetime: The datetime value
    /// - Returns: The content item
    public static func datetime(conceptName: CodedConcept? = nil, datetime: String) -> AnyContentItem {
        AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: datetime,
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
    
    /// Creates a waveform reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - channelNumbers: Optional channel numbers
    /// - Returns: The content item
    public static func waveformReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        channelNumbers: [Int]? = nil
    ) -> AnyContentItem {
        let sopRef = ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        let waveformRef = WaveformReference(
            sopReference: sopRef,
            channelNumbers: channelNumbers
        )
        return AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection (nested container)
    /// - Parameters:
    ///   - title: The section title
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(
        _ title: CodedConcept,
        items: [AnyContentItem]
    ) -> AnyContentItem {
        AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection with a string title
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(
        _ title: String,
        items: [AnyContentItem]
    ) -> AnyContentItem {
        subsection(CodedConcept.sectionHeading(title), items: items)
    }
}

// MARK: - CodedConcept Extensions for Comprehensive SR

extension CodedConcept {
    /// Standard concept for image region
    public static let imageRegion = CodedConcept(
        codeValue: "111030",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Image Region"
    )
    
    /// Standard concept for a region of interest that is not tied to a particular image
    ///
    /// (130488, DCM, "Region in Space") — PS3.16 2026a Table D-1: "A continuous part of space, not
    /// necessarily associated with a particular image." Used as the concept name of the ROI reference
    /// in TID 1410 row 8b and TID 1411 row 12b. For an ROI drawn on an image use ``imageRegion``
    /// (111030, DCM, "Image Region").
    public static let regionOfInterest = CodedConcept(
        codeValue: "130488",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Region in Space"
    )

    /// Standard concept for the anatomic location a measurement was taken at
    ///
    /// (363698007, SCT, "Finding Site") — PS3.16 2026a CID 9000 "Physical Quantity Descriptor";
    /// the HAS CONCEPT MOD concept of TID 301 row 5, TID 1419 row 2 and TID 1501 row 6.
    /// (The former value 121233 is "Source image for segmentation" in Table D-1.)
    public static let measurementLocation = CodedConcept(
        codeValue: "363698007",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Finding Site"
    )

    /// Standard concept for the temporal extent (duration) of a period of time
    ///
    /// (130532, DCM, "Duration of Time Period") — PS3.16 2026a CID 10073 "Value Timing";
    /// Table D-1: "All the points in time throughout a defined period of time".
    /// (The former value 128178 does not exist in Table D-1.)
    public static let temporalExtent = CodedConcept(
        codeValue: "130532",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Duration of Time Period"
    )
}
