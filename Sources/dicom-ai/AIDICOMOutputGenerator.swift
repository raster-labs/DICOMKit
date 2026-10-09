// NEMA-verified: 2026a, checked 2026-10-01 — createSegmentationObject diffed against PS3.3 2026a Table C.8.20-4 (14 rows) and Table C.8.20-2 (16 rows): the hand-built DataSet wrote 5 of the 30 rows and omitted 10 Type 1/1C rows that apply (Image Type, Photometric Interpretation, Lossy Image Compression, Segmentation Type, Segment Sequence, Segment Number, Segment Label, Segment Algorithm Type, Segment Algorithm Name, Segmented Property Category/Type Code Sequences) plus the Pixel Data element and the PS3.10 File Meta Information; it now routes through Segmentation.buildDataSet (D37d) and DICOMFile.create, every segment carrying one Category (CID 7150) and one Type (CID 7151) Item; the 9 attributes it writes outside those tables are in the Patient, General Study, General Series, Image Pixel and SOP Common Modules of Table A.51-1; Enhanced General Equipment Type 1 rows added (Table A.51-1, M)
// NEMA-verified: 2026a, checked 2026-10-01 — classify/detect --format dicom-sr: the hand-built Comprehensive SR (title 129007/129008 DCM not in PS3.16 Table D-1; (121072, DCM) is "Impressions", retired; (121191, DCM) is "Referenced Segment"; confidence 0-1 written in %; no template) replaced by a TID 1500 Measurement Report from MeasurementReportBuilder, validated by TemplateValidator against PS3.16 2026a TID 1500/1501/300/301/320/1600/4019 (rows 1, 5, 6, 6b, 9; 1501 rows 1-3, 10, 12; 4019 rows 1-2): 7 concepts and units checked against Table D-1 and TID 4006 row 6 / TID 4104 row 12 / TID 4127 row 8 ((111012, DCM, "Certainty of Finding"), (%, UCUM, "Percent"), 0-100), $ImagePurpose (121112, DCM) from CID 7552; Content Template Sequence per PS3.3 Table C.18.8-1 (row 6b and the root template written by MeasurementReportBuilder.withAlgorithmIdentification since 2026-10-01, D199); enhance: Image Type per C.7.6.1.1.2, Source Image Sequence / Derivation Description per Table C.12-10 with CID 7202 (121322, DCM); GSPS through GrayscalePresentationStateBuilder (Table A.33.1-1); SR, enhance and SEG written as PS3.10 files
import Foundation
import DICOMKit
import DICOMCore

// MARK: - AI DICOM Output Generator

/// Generates DICOM output objects from AI inference results.
///
/// Supports creating:
/// - DICOM Structured Reports (SR) from classification/detection predictions
/// - DICOM Segmentation objects from segmentation masks
/// - Grayscale Softcopy Presentation State (GSPS) with AI annotations
/// - Enhanced DICOM files with AI-processed pixel data
/// - Text/JSON/Markdown reports from predictions
struct AIDICOMOutputGenerator {

    // MARK: - DICOM SR from Predictions

    /// Concept names and units of the SR content tree, with their PS3.16 2026a Table D-1 /
    /// template meanings
    enum SRConcept {
        /// (121071, DCM, "Finding") — the TEXT of TID 1501 row 12 ($QualType is not bound
        /// by TID 1500 row 9) that carries the model's class label, which has no code
        static let finding = CodedConcept(
            codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding")
        /// (111012, DCM, "Certainty of Finding") — the NUM of TID 1501 row 10 → TID 300 row 1
        /// ($Measurement, BCID 218); the concept and units the CAD Single Image Finding
        /// templates (TID 4006 row 6, TID 4104 row 12, TID 4127 row 8) use for a certainty
        static let certaintyOfFinding = CodedConcept(
            codeValue: "111012", codingSchemeDesignator: "DCM", codeMeaning: "Certainty of Finding")
        /// (%, UCUM, "Percent") — UNITS of Certainty of Finding, Value 0 - 100
        static let percent = CodedConcept(
            codeValue: "%", codingSchemeDesignator: "UCUM", codeMeaning: "Percent")
        /// (121112, DCM, "Source of Measurement") — $ImagePurpose (BCID 7551 → CID 7552),
        /// the purpose of the image / region the certainty was inferred from (TID 320 row 1/3)
        static let sourceOfMeasurement = CodedConcept(
            codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Source of Measurement")
    }

    /// Algorithm Version written when neither `--algorithm-version` nor the model's metadata
    /// gives one: TID 4019 row 2 is M, so the row is never left out
    static let unknownAlgorithmVersion = "unknown"

    /// Creates a DICOM Comprehensive SR from classification predictions, as a PS3.16 TID 1500
    /// Measurement Report built by DICOMKit's `MeasurementReportBuilder`:
    /// - root CONTAINER (126000, DCM, "Imaging Measurement Report") — CID 7021, row 1;
    /// - row 5 → TID 1600: Image Library with the source image;
    /// - row 6 CONTAINER (126010, DCM, "Imaging Measurements"), with row 6b → TID 4019
    ///   (Algorithm Name, Algorithm Version) and, per prediction, row 9 → TID 1501: a
    ///   Measurement Group with Tracking Identifier / Tracking Unique Identifier (rows 2, 3),
    ///   a NUM (111012, DCM, "Certainty of Finding") in (%, UCUM, "Percent") (row 10 → TID 300
    ///   row 1) INFERRED FROM the source IMAGE (TID 301 row 13 → TID 320 row 1), and a TEXT
    ///   (121071, DCM, "Finding") holding the label (row 12).
    /// - Parameters:
    ///   - predictions: Classification predictions with labels and confidence scores (0-1)
    ///   - sourceDataSet: The original DICOM DataSet for reference metadata
    ///   - modelName: Algorithm Name (TID 4019 row 1)
    ///   - algorithmVersion: Algorithm Version (TID 4019 row 2)
    ///   - frameIndex: The frame that was analysed (0-based), referenced for a multi-frame image
    /// - Returns: The SR data set (write it with `partTenFile(_:)`)
    static func createSRFromClassification(
        predictions: [Prediction],
        sourceDataSet: DataSet,
        modelName: String,
        algorithmVersion: String = unknownAlgorithmVersion,
        frameIndex: Int = 0
    ) throws -> DataSet {
        let image = sourceImageReference(sourceDataSet, frameIndex: frameIndex)
        let groups = predictions.enumerated().map { index, prediction in
            MeasurementGroupData(
                trackingIdentifier: "AI classification \(index + 1)",
                trackingUID: UIDGenerator.generateUID().value,
                contents: [
                    certainty(prediction.confidence, source: image.map {
                        .image(purpose: SRConcept.sourceOfMeasurement, image: $0)
                    }),
                    .text(conceptName: SRConcept.finding, value: prediction.label),
                ]
            )
        }
        return try measurementReport(
            groups: groups, sourceDataSet: sourceDataSet, image: image,
            modelName: modelName, algorithmVersion: algorithmVersion)
    }

    /// Creates a DICOM Comprehensive SR from detection results: the TID 1500 Measurement Report
    /// of `createSRFromClassification`, with each detection's certainty INFERRED FROM a SCOORD
    /// POLYLINE (the closed bounding box, column\row pairs per PS3.3 C.18.6.1.2) SELECTED FROM
    /// the source IMAGE (TID 320 rows 3, 4).
    static func createSRFromDetections(
        detections: [Detection],
        sourceDataSet: DataSet,
        modelName: String,
        algorithmVersion: String = unknownAlgorithmVersion,
        frameIndex: Int = 0
    ) throws -> DataSet {
        let image = sourceImageReference(sourceDataSet, frameIndex: frameIndex)
        let groups = detections.enumerated().map { index, detection in
            let source: MeasurementSource? = image.map {
                .spatialCoordinates(
                    purpose: SRConcept.sourceOfMeasurement,
                    graphicType: .polyline,
                    graphicData: boundingBoxPolyline(detection.bbox),
                    sourceImage: $0)
            }
            return MeasurementGroupData(
                trackingIdentifier: "AI detection \(index + 1)",
                trackingUID: UIDGenerator.generateUID().value,
                contents: [
                    certainty(detection.confidence, source: source),
                    .text(conceptName: SRConcept.finding, value: detection.label),
                ]
            )
        }
        return try measurementReport(
            groups: groups, sourceDataSet: sourceDataSet, image: image,
            modelName: modelName, algorithmVersion: algorithmVersion)
    }

    /// A closed 5-point POLYLINE (column\row pairs) around a bounding box
    static func boundingBoxPolyline(_ box: BoundingBox) -> [Float] {
        let (x, y, w, h) = (Float(box.x), Float(box.y), Float(box.width), Float(box.height))
        return [x, y, x + w, y, x + w, y + h, x, y + h, x, y]
    }

    /// TID 1501 row 10 → TID 300 row 1: NUM (111012, DCM, "Certainty of Finding"), UNITS
    /// (%, UCUM, "Percent"), Value 0 - 100, with the TID 301 row 13 source when there is one
    private static func certainty(_ confidence: Double, source: MeasurementSource?) -> MeasurementGroupContent {
        let value = min(max(confidence, 0), 1) * 100
        guard let source else {
            return .measurement(conceptName: SRConcept.certaintyOfFinding, value: value, units: SRConcept.percent)
        }
        return .measurementWithContent(
            conceptName: SRConcept.certaintyOfFinding, value: value, units: SRConcept.percent,
            content: MeasurementContent(sources: [source]))
    }

    /// The analysed image, or nil when the source has no SOP Instance UID
    private static func sourceImageReference(_ dataSet: DataSet, frameIndex: Int) -> ImageReference? {
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID), !sopInstanceUID.isEmpty,
              let sopClassUID = dataSet.string(for: .sopClassUID), !sopClassUID.isEmpty else {
            return nil
        }
        let frames = Int(dataSet.string(for: .numberOfFrames)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1
        return ImageReference(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frames > 1 ? [frameIndex + 1] : nil)
    }

    /// Builds the TID 1500 document through `MeasurementReportBuilder`, with TID 1500 row 6b
    /// → TID 4019 (`withAlgorithmIdentification`; the builder also writes the root's Content
    /// Template Sequence, PS3.3 Table C.18.8-1, since D199), serializes it, and copies the
    /// Type 2 Patient and General Study attributes from the source image and Manufacturer
    /// (Table A.35.3-1; the serializer writes them empty when unknown since D198).
    private static func measurementReport(
        groups: [MeasurementGroupData],
        sourceDataSet: DataSet,
        image: ImageReference?,
        modelName: String,
        algorithmVersion: String
    ) throws -> DataSet {
        var builder = MeasurementReportBuilder()
            .withStudyInstanceUID(sourceDataSet.string(for: .studyInstanceUID) ?? UIDGenerator.generateStudyInstanceUID().value)
            .withSeriesInstanceUID(UIDGenerator.generateSeriesInstanceUID().value)
            .withImagingMeasurementReportTitle()
            .withCompletionFlag(.complete)
            .withVerificationFlag(.unverified)
            .withAlgorithmIdentification(CADAlgorithmIdentification(
                name: modelName,
                version: algorithmVersion.isEmpty ? unknownAlgorithmVersion : algorithmVersion))
        if let image {
            builder = builder.addImageLibraryEntry(
                sopClassUID: image.sopReference.sopClassUID,
                sopInstanceUID: image.sopReference.sopInstanceUID,
                frameNumbers: image.frameNumbers)
        }
        for group in groups {
            builder = builder.addMeasurementGroup(group)
        }
        let document = try builder.build()

        var dataSet = try SRDocumentSerializer().serialize(document: document)
        for (tag, vr) in Self.patientAndStudyAttributes {
            dataSet.setString(sourceDataSet.string(for: tag) ?? "", for: tag, vr: vr)
        }
        dataSet.setString("DICOMKit", for: .manufacturer, vr: .LO)
        return dataSet
    }

    /// Wraps a data set in a PS3.10 file: preamble, "DICM", File Meta Information whose Media
    /// Storage SOP Class / Instance UIDs are the data set's (PS3.10 2026a Table 7.1-1)
    static func partTenFile(_ dataSet: DataSet) throws -> Data {
        guard let sopClassUID = dataSet.string(for: .sopClassUID),
              let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw AIError.invalidModelOutput("SOP Class UID and SOP Instance UID are required to write a DICOM file")
        }
        return try DICOMFile.create(dataSet: dataSet, sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID).write()
    }

    // MARK: - DICOM Segmentation Object

    /// Creates a DICOM Segmentation object (PS3.3 A.51, Segmentation Storage) from an AI
    /// segmentation mask, through DICOMKit's `SegmentationBuilder` and
    /// `Segmentation.buildDataSet(pixelData:)`, which writes the Type 1 attributes of
    /// Tables C.8.20-2 and C.8.20-4 and refuses a segment without Segmented Property
    /// Category / Type codes (D37d).
    ///
    /// Every segment carries the same Segmented Property Category Code Sequence (0062,0003)
    /// and Segmented Property Type Code Sequence (0062,000F) Item: an AI class label has no
    /// coded anatomy, so the caller picks one pair from PS3.16 CID 7150 / CID 7151
    /// (`SegmentPropertyCodes`), with `SegmentPropertyCodes.defaultCategory` /
    /// `.defaultType` when none is given.
    ///
    /// - Parameters:
    ///   - sourceDataSet: The original DICOM DataSet for reference metadata
    ///   - segmentationMask: The segmentation mask with class labels
    ///   - labels: Human-readable labels for each segment class
    ///   - modelName: Name of the AI model used (Segment Algorithm Name, Type 1C when the
    ///     Segment Algorithm Type is AUTOMATIC, Table C.8.20-2)
    ///   - category: Segmented Property Category (CID 7150) for every segment
    ///   - type: Segmented Property Type (CID 7151) for every segment
    /// - Returns: A complete DICOM Part 10 file (preamble, File Meta Information, data set)
    static func createSegmentationObject(
        sourceDataSet: DataSet,
        segmentationMask: SegmentationMask,
        labels: [String],
        modelName: String,
        category: CodedConcept = SegmentPropertyCodes.defaultCategory,
        type: CodedConcept = SegmentPropertyCodes.defaultType
    ) throws -> Data {
        let studyInstanceUID = sourceDataSet.string(for: .studyInstanceUID) ?? UIDGenerator.generateStudyInstanceUID().value
        let seriesInstanceUID = UIDGenerator.generateSeriesInstanceUID().value
        let sopClassUID = sourceDataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.2"
        let sopInstanceUID = sourceDataSet.string(for: .sopInstanceUID) ?? ""

        // Validate mask dimensions match expected pixel count
        let expectedPixelCount = segmentationMask.width * segmentationMask.height
        guard segmentationMask.data.count >= expectedPixelCount else {
            throw AIError.invalidModelOutput(
                "Segmentation mask data size (\(segmentationMask.data.count)) " +
                "is smaller than expected (\(expectedPixelCount) = \(segmentationMask.width)×\(segmentationMask.height))"
            )
        }

        let builder = SegmentationBuilder(
            rows: segmentationMask.height,
            columns: segmentationMask.width,
            segmentationType: .binary,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID
        )
        .setContentLabel("AI_SEGMENTATION")
        .setContentDescription("AI segmentation from \(modelName)")

        if let frameOfReferenceUID = sourceDataSet.string(for: .frameOfReferenceUID) {
            // Table A.51-1: Frame of Reference is required when no Derivation Image
            // Functional Group is present
            builder.setFrameOfReference(frameOfReferenceUID)
        }

        if !sopInstanceUID.isEmpty {
            builder.addSourceImage(
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID
            )
        }

        // Extract per-class binary masks and add as segments
        for classIndex in 0..<segmentationMask.numClasses {
            let label = classIndex < labels.count ? labels[classIndex] : "Class_\(classIndex)"
            let binaryMask = extractBinaryMask(
                from: segmentationMask,
                forClass: classIndex
            )

            try builder.addBinarySegment(
                number: classIndex + 1,
                label: label,
                mask: binaryMask,
                category: category,
                type: type,
                algorithmType: .automatic,
                algorithmName: modelName
            )
        }

        let (segmentation, pixelData) = try builder.build()
        var dataSet = try segmentation.buildDataSet(pixelData: pixelData)

        // Patient and General Study Modules (Table A.51-1, both M): the Type 2 rows are
        // copied from the source image, or written empty, so the object joins its study.
        for (tag, vr) in Self.patientAndStudyAttributes {
            dataSet.setString(sourceDataSet.string(for: tag) ?? "", for: tag, vr: vr)
        }
        // Enhanced General Equipment Module (Table A.51-1, M): Manufacturer, Manufacturer's
        // Model Name, Device Serial Number and Software Versions are Type 1 (Table C.7-8b).
        dataSet.setString("DICOMKit", for: .manufacturer, vr: .LO)
        dataSet.setString("dicom-ai", for: .manufacturerModelName, vr: .LO)
        dataSet.setString(modelName, for: .deviceSerialNumber, vr: .LO)
        dataSet.setString(DICOMFile.implementationVersionName, for: .softwareVersions, vr: .LO)

        let file = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: Segmentation.segmentationStorageUID,
            sopInstanceUID: segmentation.sopInstanceUID
        )
        return try file.write()
    }

    /// Type 2 attributes of the Patient (Table C.7-1) and General Study (Table C.7-3)
    /// Modules, copied from the source image into every object this generator creates
    private static let patientAndStudyAttributes: [(Tag, VR)] = [
        (.patientName, .PN), (.patientID, .LO), (.patientBirthDate, .DA), (.patientSex, .CS),
        (.studyDate, .DA), (.studyTime, .TM), (.referringPhysicianName, .PN),
        (.studyID, .SH), (.accessionNumber, .SH),
    ]

    /// Extracts a binary mask for a specific class from the segmentation mask.
    private static func extractBinaryMask(from mask: SegmentationMask, forClass classIndex: Int) -> [UInt8] {
        let pixelCount = mask.width * mask.height
        var binaryMask = [UInt8](repeating: 0, count: pixelCount)

        for i in 0..<min(pixelCount, mask.data.count) {
            if mask.data[i] == UInt8(classIndex) {
                binaryMask[i] = 1
            }
        }

        return binaryMask
    }

    // MARK: - GSPS with AI Annotations

    /// Creates a Grayscale Softcopy Presentation State (PS3.3 A.33.1) with the detections as
    /// graphic annotations, through DICOMKit's `GrayscalePresentationStateBuilder`, which
    /// writes the modules of Table A.33.1-1 (Presentation State Identification, Displayed
    /// Area, Graphic Annotation C.10.5, Graphic Layer C.10.7, …).
    ///
    /// Each detection is one Graphic Annotation Sequence Item on layer AI_DETECTIONS: a closed
    /// POLYLINE of 5 points in PIXEL Graphic Annotation Units (Table C.10-5) and a text object
    /// "<label> (<confidence>%)" whose bounding box (Bounding Box Annotation Units PIXEL) sits
    /// above the box. No subcommand writes this object yet.
    /// - Parameters:
    ///   - detections: AI detection results with bounding boxes
    ///   - sourceDataSet: The original DICOM DataSet
    ///   - modelName: Name of the AI model used
    /// - Returns: The GSPS data set
    static func createGSPSWithAnnotations(
        detections: [Detection],
        sourceDataSet: DataSet,
        modelName: String
    ) throws -> DataSet {
        let layer = "AI_DETECTIONS"
        var referencedImages: [ReferencedImage] = []
        if let sopInstanceUID = sourceDataSet.string(for: .sopInstanceUID), !sopInstanceUID.isEmpty {
            referencedImages.append(ReferencedImage(
                sopClassUID: sourceDataSet.string(for: .sopClassUID) ?? "",
                sopInstanceUID: sopInstanceUID))
        }
        let annotations = detections.map { detection in
            let box = detection.bbox
            return GraphicAnnotation(
                layer: layer,
                referencedImages: [],
                graphicObjects: [GraphicObject(
                    type: .polyline,
                    data: boundingBoxPolyline(box).map(Double.init),
                    units: .pixel)],
                textObjects: [TextObject(
                    text: "\(detection.label) (\(String(format: "%.0f%%", detection.confidence * 100)))",
                    boundingBoxTopLeft: (column: box.x, row: max(0, box.y - 10)),
                    boundingBoxBottomRight: (column: box.x + box.width, row: box.y),
                    boundingBoxUnits: .pixel)]
            )
        }
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let state = GrayscalePresentationState(
            sopInstanceUID: UIDGenerator.generateSOPInstanceUID().value,
            instanceNumber: 1,
            presentationLabel: "AI_ANNOTATIONS",
            presentationDescription: "AI annotations from \(modelName)",
            presentationCreationDate: DICOMDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1),
            presentationCreationTime: DICOMTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0),
            referencedSeries: referencedImages.isEmpty ? [] : [ReferencedSeries(
                seriesInstanceUID: sourceDataSet.string(for: .seriesInstanceUID) ?? "",
                referencedImages: referencedImages)],
            graphicLayers: [GraphicLayer(name: layer, order: 1, description: "AI Detection Results")],
            graphicAnnotations: annotations
        )
        var patient = PresentationStatePatientContext.make(from: sourceDataSet)
        if patient.studyInstanceUID.isEmpty {
            patient.studyInstanceUID = UIDGenerator.generateStudyInstanceUID().value
        }
        let imageSize: (columns: Int, rows: Int)? = {
            guard let columns = sourceDataSet.uint16(for: .columns), let rows = sourceDataSet.uint16(for: .rows) else { return nil }
            return (Int(columns), Int(rows))
        }()
        return GrayscalePresentationStateBuilder().buildDataSet(
            from: state,
            patient: patient,
            seriesInstanceUID: UIDGenerator.generateSeriesInstanceUID().value,
            seriesNumber: 1,
            imageSize: imageSize)
    }

    // MARK: - Enhanced DICOM File

    /// Creates a derived image from the AI-processed pixel data, as a PS3.10 file of the
    /// source's SOP Class: the source data set is kept (so the IOD's other modules stay), with
    /// - a new SOP Instance UID and Series Instance UID (PS3.3 C.7.6.1.1.2: a derived image
    ///   whose pixels differ "shall have a SOP Instance UID different than all the source
    ///   images");
    /// - Image Type (0008,0008) Value 1 DERIVED and Value 2 SECONDARY (C.7.6.1.1.2 Enumerated
    ///   Values), Values 3 and beyond kept;
    /// - the Image Pixel Module attributes of the processed image; Smallest / Largest Image
    ///   Pixel Value removed (they described the source pixels); a multi-frame source keeps
    ///   only the processed frame;
    /// - General Reference Module (Table C.12-10): Derivation Description (0008,2111) and a
    ///   Source Image Sequence (0008,2112) Item with Purpose of Reference (121322, DCM,
    ///   "Source image for image processing operation"), CID 7202.
    /// - Parameters:
    ///   - sourceDataSet: The original DICOM DataSet
    ///   - enhancedImage: The AI-enhanced processed image
    ///   - frameIndex: The frame that was enhanced (0-based, for multi-frame images)
    ///   - modelName: Name of the AI model, written in the Derivation Description
    /// - Returns: The PS3.10 file
    static func createEnhancedDICOMFile(
        sourceDataSet: DataSet,
        enhancedImage: ProcessedImage,
        frameIndex: Int,
        modelName: String = "AI model"
    ) throws -> Data {
        var dataSet = sourceDataSet
        for tag in dataSet.tags where tag.group == 0x0002 {
            dataSet[tag] = nil
        }
        let sourceSOPClassUID = sourceDataSet.string(for: .sopClassUID) ?? "1.2.840.10008.5.1.4.1.1.7"
        let sourceSOPInstanceUID = sourceDataSet.string(for: .sopInstanceUID)
        let sopInstanceUID = UIDGenerator.generateSOPInstanceUID().value
        dataSet.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        dataSet.setString(UIDGenerator.generateSeriesInstanceUID().value, for: .seriesInstanceUID, vr: .UI)

        // Image Type: Value 1 DERIVED, Value 2 SECONDARY (PS3.3 C.7.6.1.1.2)
        var imageType = sourceDataSet.strings(for: .imageType) ?? []
        while imageType.count < 2 { imageType.append("") }
        imageType[0] = "DERIVED"
        imageType[1] = "SECONDARY"
        dataSet.setString(imageType.joined(separator: "\\"), for: .imageType, vr: .CS)

        // Image Pixel Module of the processed image
        dataSet.setUInt16(UInt16(enhancedImage.height), for: .rows)
        dataSet.setUInt16(UInt16(enhancedImage.width), for: .columns)
        dataSet.setUInt16(UInt16(enhancedImage.bitsPerPixel), for: .bitsAllocated)
        dataSet.setUInt16(UInt16(enhancedImage.bitsPerPixel), for: .bitsStored)
        dataSet.setUInt16(UInt16(enhancedImage.bitsPerPixel - 1), for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(UInt16(enhancedImage.samplesPerPixel), for: .samplesPerPixel)
        dataSet.setString(enhancedImage.photometricInterpretation, for: .photometricInterpretation, vr: .CS)
        if enhancedImage.samplesPerPixel == 1 {
            dataSet[.planarConfiguration] = nil  // Type 1C, only when Samples per Pixel > 1
        }
        dataSet[.smallestImagePixelValue] = nil
        dataSet[.largestImagePixelValue] = nil
        let pixelVR: VR = enhancedImage.bitsPerPixel > 8 ? .OW : .OB
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: pixelVR, data: enhancedImage.pixelData)

        // One frame is written
        let sourceFrames = Int(sourceDataSet.string(for: .numberOfFrames)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1
        if sourceDataSet[.numberOfFrames] != nil {
            dataSet.setString("1", for: .numberOfFrames, vr: .IS)
        }
        if let perFrame = sourceDataSet.sequence(for: .perFrameFunctionalGroupsSequence), frameIndex < perFrame.count {
            dataSet.setSequence([perFrame[frameIndex]], for: .perFrameFunctionalGroupsSequence)
        }

        // General Reference Module (PS3.3 Table C.12-10)
        dataSet.setString("AI image enhancement by \(modelName)", for: .derivationDescription, vr: .ST)
        if let sourceSOPInstanceUID, !sourceSOPInstanceUID.isEmpty {
            var purpose = DataSet()
            purpose.setString("121322", for: .codeValue, vr: .SH)
            purpose.setString("DCM", for: .codingSchemeDesignator, vr: .SH)
            purpose.setString("Source image for image processing operation", for: .codeMeaning, vr: .LO)
            var item = DataSet()
            item.setString(sourceSOPClassUID, for: .referencedSOPClassUID, vr: .UI)
            item.setString(sourceSOPInstanceUID, for: .referencedSOPInstanceUID, vr: .UI)
            if sourceFrames > 1 {
                item.setString(String(frameIndex + 1), for: .referencedFrameNumber, vr: .IS)
            }
            item.setSequence([SequenceItem(elements: purpose.allElements)], for: .purposeOfReferenceCodeSequence)
            dataSet.setSequence([SequenceItem(elements: item.allElements)], for: .sourceImageSequence)
        }

        dataSet.setString("AI Enhanced Image", for: .imageComments, vr: .LT)

        return try DICOMFile.create(
            dataSet: dataSet, sopClassUID: sourceSOPClassUID, sopInstanceUID: sopInstanceUID
        ).write()
    }

    // MARK: - Report Generation

    /// Generates a text report from classification predictions.
    static func generateClassificationReport(
        predictions: [Prediction],
        filePath: String,
        modelName: String
    ) -> String {
        var report = """
        ═══════════════════════════════════════════════════
        AI Classification Report
        ═══════════════════════════════════════════════════
        Model: \(modelName)
        File:  \(filePath)
        Date:  \(ISO8601DateFormatter().string(from: Date()))
        ═══════════════════════════════════════════════════

        RESULTS:
        """

        if predictions.isEmpty {
            report += "\n  No predictions above confidence threshold.\n"
        } else {
            for (index, pred) in predictions.enumerated() {
                let bar = String(repeating: "█", count: Int(pred.confidence * 30))
                let space = String(repeating: "░", count: 30 - Int(pred.confidence * 30))
                report += "\n  \(index + 1). \(pred.label)"
                report += "\n     Confidence: \(String(format: "%.2f%%", pred.confidence * 100))"
                report += "\n     [\(bar)\(space)]"
                report += "\n"
            }
        }

        report += "\n═══════════════════════════════════════════════════\n"
        return report
    }

    /// Generates a text report from detection results.
    static func generateDetectionReport(
        detections: [Detection],
        filePath: String,
        modelName: String
    ) -> String {
        var report = """
        ═══════════════════════════════════════════════════
        AI Detection Report
        ═══════════════════════════════════════════════════
        Model:      \(modelName)
        File:       \(filePath)
        Date:       \(ISO8601DateFormatter().string(from: Date()))
        Detections: \(detections.count)
        ═══════════════════════════════════════════════════

        FINDINGS:
        """

        if detections.isEmpty {
            report += "\n  No detections above confidence threshold.\n"
        } else {
            for (index, det) in detections.enumerated() {
                report += "\n  \(index + 1). \(det.label)"
                report += "\n     Confidence: \(String(format: "%.2f%%", det.confidence * 100))"
                report += "\n     Location:   (x: \(String(format: "%.1f", det.bbox.x)), y: \(String(format: "%.1f", det.bbox.y)))"
                report += "\n     Size:       \(String(format: "%.1f", det.bbox.width)) × \(String(format: "%.1f", det.bbox.height))"
                report += "\n"
            }
        }

        report += "\n═══════════════════════════════════════════════════\n"
        return report
    }

    /// Generates a Markdown report from predictions.
    static func generateMarkdownReport(
        predictions: [Prediction],
        detections: [Detection],
        filePath: String,
        modelName: String
    ) -> String {
        var md = "# AI Analysis Report\n\n"
        md += "| Property | Value |\n|----------|-------|\n"
        md += "| Model | \(modelName) |\n"
        md += "| File | \(filePath) |\n"
        md += "| Date | \(ISO8601DateFormatter().string(from: Date())) |\n\n"

        if !predictions.isEmpty {
            md += "## Classifications\n\n"
            md += "| Rank | Label | Confidence |\n|------|-------|------------|\n"
            for (index, pred) in predictions.enumerated() {
                md += "| \(index + 1) | \(pred.label) | \(String(format: "%.2f%%", pred.confidence * 100)) |\n"
            }
            md += "\n"
        }

        if !detections.isEmpty {
            md += "## Detections\n\n"
            md += "| # | Label | Confidence | X | Y | Width | Height |\n"
            md += "|---|-------|------------|---|---|-------|--------|\n"
            for (index, det) in detections.enumerated() {
                md += "| \(index + 1) | \(det.label) | \(String(format: "%.2f%%", det.confidence * 100)) "
                md += "| \(String(format: "%.1f", det.bbox.x)) | \(String(format: "%.1f", det.bbox.y)) "
                md += "| \(String(format: "%.1f", det.bbox.width)) | \(String(format: "%.1f", det.bbox.height)) |\n"
            }
            md += "\n"
        }

        return md
    }
}
