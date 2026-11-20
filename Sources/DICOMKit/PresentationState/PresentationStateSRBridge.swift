// NEMA-verified: 2026a, checked 2026-11-16 — PS3.16 2026a TID 1500 (Measurement Report), TID 1410 (Planar ROI Measurements), TID 1411 (Volumetric ROI Measurements), TID 300 (Measurement), TID 320 (Image or Spatial Coordinates), TID 2010 (Key Object Selection), and PS3.3 Table C.18.4-1 (Image Reference Macro nested Referenced SOP Sequence (0008,1199))
//
// PresentationStateSRBridge.swift
// DICOMKit
//
// Bidirectional bridge between Softcopy Presentation States (GSPS, CSPS, Pseudo-CSPS)
// + high-level DICOMAnnotations and DICOM Structured Reporting (SR):
// - TID 1500 Imaging Measurement Report (PS3.16 TID 1500 / TID 1600 / TID 1501 / TID 300 / TID 320)
// - Comprehensive SR (PS3.3 A.35.3)
// - TID 2010 Key Object Selection (PS3.16 TID 2010)
// - PS3.3 Table C.18.4-1 Image Reference Macro with nested Softcopy Presentation State reference (0008,1199)
//

import Foundation
import DICOMCore

/// Result of extracting annotations, measurements, and Softcopy Presentation State references from an `SRDocument`.
public struct ExtractedSRAnnotations: Sendable, Equatable {
    /// Annotations and ROI measurements reconstructed from `SCOORD`, `NUM`, and `TEXT` items in the SR tree.
    public let annotations: [DICOMAnnotation]
    /// Softcopy Presentation State SOP references (GSPS `.11.1`, CSPS `.11.2`, Pseudo-CSPS `.11.3`, Blending `.11.4`)
    /// found in nested `IMAGE` `ReferencedSOPSequence (0008,1199)` items or standalone `COMPOSITE` items.
    public let presentationStateReferences: [ReferencedSOP]
    /// Image references found in the SR document.
    public let imageReferences: [ImageReference]

    public init(
        annotations: [DICOMAnnotation],
        presentationStateReferences: [ReferencedSOP],
        imageReferences: [ImageReference]
    ) {
        self.annotations = annotations
        self.presentationStateReferences = presentationStateReferences
        self.imageReferences = imageReferences
    }
}

/// Bidirectional bridge between DICOM Presentation States (GSPS, CSPS, Pseudo-CSPS) / `DICOMAnnotation`
/// and DICOM Structured Reporting (`SRDocument`).
public enum PresentationStateSRBridge {

    // MARK: - PR / Annotations -> TID 1500 Measurement Report SR

    /// Builds a DICOM PS3.16 **TID 1500 Imaging Measurement Report** (`Comprehensive SR`) from a
    /// `PresentationStateDocument` (GSPS, CSPS, or Pseudo-CSPS) and/or high-level `[DICOMAnnotation]`.
    ///
    /// Every `IMAGE` reference in the TID 1600 Image Library and in each TID 1501 / TID 320 `SCOORD`
    /// carries the nested `ReferencedSOPSequence (0008,1199)` pointing to `presentationState.referencedSOP`
    /// per DICOM PS3.3 Table C.18.4-1.
    public static func buildMeasurementReport(
        from presentationState: PresentationStateDocument? = nil,
        annotations: [DICOMAnnotation]? = nil,
        patient: PresentationStatePatientContext,
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        sopInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        presentationStateSeriesUID: String? = nil,
        seriesNumber: Int = 9002,
        procedureReported: CodedConcept = CodedConcept(
            codeValue: "363679005",
            codingSchemeDesignator: "SCT",
            codeMeaning: "Imaging procedure"
        )
    ) throws -> SRDocument {
        let resolvedAnnotations: [DICOMAnnotation]
        if let annotations {
            resolvedAnnotations = annotations
        } else if let presentationState {
            resolvedAnnotations = DICOMAnnotationConverter.annotations(
                from: presentationState,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                targetCoordinateSpace: .pixel
            )
        } else {
            resolvedAnnotations = []
        }

        let prReference = presentationState?.referencedSOP
        let allReferencedImages = presentationState?.referencedSeries.flatMap(\.referencedImages) ?? []
        let fallbackImage = allReferencedImages.first
        let finalSeriesUID = seriesInstanceUID ?? UIDGenerator.generateUID().value

        var builder = MeasurementReportBuilder(validateOnBuild: true)
            .withSOPInstanceUID(sopInstanceUID ?? UIDGenerator.generateUID().value)
            .withStudyInstanceUID(patient.studyInstanceUID)
            .withSeriesInstanceUID(finalSeriesUID)
            .withSeriesNumber(String(seriesNumber))
            .withSeriesDescription(presentationState?.presentationDescription ?? "Presentation State Measurements")
            .withImagingMeasurementReportTitle()
            .addProcedureReported(procedureReported)

        // TID 1500 Row 3 (DTID 1001 Observation Context, M): include creator person or device observer
        if let creator = presentationState?.presentationCreatorsName?.dicomString, !creator.isEmpty {
            builder = builder.addObserver(.person(name: creator))
        } else {
            builder = builder.addObserver(.device(uid: UIDGenerator.defaultRoot, name: "DICOMKit"))
        }

        if let patientID = patient.patientID { builder = builder.withPatientID(patientID) }
        if let patientName = patient.patientName { builder = builder.withPatientName(patientName) }
        if let birthDate = patient.patientBirthDate { builder = builder.withPatientBirthDate(birthDate) }
        if let sex = patient.patientSex { builder = builder.withPatientSex(sex) }
        if let studyDate = patient.studyDate { builder = builder.withStudyDate(studyDate) }
        if let studyTime = patient.studyTime { builder = builder.withStudyTime(studyTime) }
        if let accession = patient.accessionNumber { builder = builder.withAccessionNumber(accession) }
        if let referring = patient.referringPhysicianName { builder = builder.withReferringPhysicianName(referring) }

        // Populate TID 1600 Image Library with nested Softcopy Presentation State reference (PS3.3 C.18.4-1)
        for refImg in allReferencedImages {
            builder = builder.addImageLibraryEntry(
                sopClassUID: refImg.sopClassUID,
                sopInstanceUID: refImg.sopInstanceUID,
                frameNumbers: refImg.referencedFrameNumbers,
                presentationStateReference: prReference
            )
        }

        // Convert each annotation into a TID 1501 Measurement Group
        for (index, annotation) in resolvedAnnotations.enumerated() {
            let trackingID = annotation.trackingIdentifier
                ?? (!annotation.text.isEmpty ? annotation.text : "\(annotation.kind.rawValue.uppercased())-\(index + 1)")
            let trackingUID = annotation.trackingUID ?? UIDGenerator.generateUID().value

            let targetSOPClass = annotation.referencedSOPClassUID
                ?? fallbackImage?.sopClassUID
                ?? "1.2.840.10008.5.1.4.1.1.2"
            let targetSOPInstance = annotation.referencedSOPInstanceUID
                ?? fallbackImage?.sopInstanceUID
                ?? UIDGenerator.generateUID().value
            let targetFrames = annotation.referencedFrameNumbers ?? fallbackImage?.referencedFrameNumbers

            let sourceImageRef = ImageReference(
                sopClassUID: targetSOPClass,
                sopInstanceUID: targetSOPInstance,
                frameNumbers: targetFrames,
                presentationStateReference: prReference
            )

            let (graphicType, graphicData) = scoordGeometry(
                for: annotation,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )

            var groupContents: [MeasurementGroupContent] = []

            var effectiveMeasurements = annotation.measurements
            if annotation.kind == .angle, annotation.points.count == 3, effectiveMeasurements.isEmpty {
                let v1x = annotation.points[0].x - annotation.points[1].x
                let v1y = annotation.points[0].y - annotation.points[1].y
                let v2x = annotation.points[2].x - annotation.points[1].x
                let v2y = annotation.points[2].y - annotation.points[1].y
                let denom = hypot(v1x, v1y) * hypot(v2x, v2y)
                if denom > 1e-9 {
                    let cosTheta = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / denom))
                    let deg = acos(cosTheta) * 180.0 / .pi
                    effectiveMeasurements = [.angleDegrees(deg)]
                }
            }

            if !effectiveMeasurements.isEmpty {
                for m in effectiveMeasurements {
                    let source: [MeasurementSource]
                    if !graphicData.isEmpty {
                        source = [
                            .spatialCoordinates(
                                purpose: CodedConcept(codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Source of Measurement"),
                                graphicType: graphicType,
                                graphicData: graphicData,
                                sourceImage: sourceImageRef
                            )
                        ]
                    } else {
                        source = [
                            .image(
                                purpose: CodedConcept(codeValue: "121112", codingSchemeDesignator: "DCM", codeMeaning: "Source of Measurement"),
                                image: sourceImageRef
                            )
                        ]
                    }
                    groupContents.append(.measurementWithContent(
                        conceptName: m.concept,
                        value: m.value,
                        units: m.units,
                        content: MeasurementContent(sources: source)
                    ))
                }
            }

            if !graphicData.isEmpty {
                groupContents.append(.spatialCoordinatesOnImage(
                    conceptName: CodedConcept(codeValue: "111030", codingSchemeDesignator: "DCM", codeMeaning: "Image Region"),
                    graphicType: graphicType,
                    graphicData: graphicData,
                    sourceImage: sourceImageRef
                ))
            }

            if !annotation.text.isEmpty {
                groupContents.append(.text(
                    conceptName: CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment"),
                    value: annotation.text
                ))
            }

            if !groupContents.isEmpty {
                let group = MeasurementGroupData(
                    trackingIdentifier: trackingID,
                    trackingUID: trackingUID,
                    contents: groupContents
                )
                builder = builder.addMeasurementGroup(group)
            }
        }

        var srDoc = try builder.build()
        let evidence = collectEvidenceReferences(
            from: presentationState,
            studyInstanceUID: patient.studyInstanceUID,
            presentationStateSeriesUID: presentationStateSeriesUID,
            fallbackSeriesUID: finalSeriesUID
        )
        if !evidence.isEmpty {
            srDoc = srDoc.withEvidenceReferences(evidence)
        }
        return srDoc
    }

    private static func collectEvidenceReferences(
        from presentationState: PresentationStateDocument?,
        studyInstanceUID: String,
        presentationStateSeriesUID: String?,
        fallbackSeriesUID: String
    ) -> [HierarchicalSOPReference] {
        guard let presentationState, !studyInstanceUID.isEmpty else { return [] }
        var refs: [HierarchicalSOPReference] = []
        for series in presentationState.referencedSeries {
            let sUID = series.seriesInstanceUID.isEmpty ? fallbackSeriesUID : series.seriesInstanceUID
            for img in series.referencedImages {
                refs.append(HierarchicalSOPReference(
                    studyInstanceUID: studyInstanceUID,
                    seriesInstanceUID: sUID,
                    sopClassUID: img.sopClassUID,
                    sopInstanceUID: img.sopInstanceUID
                ))
            }
        }
        let prSeriesUID = (presentationStateSeriesUID?.isEmpty == false)
            ? presentationStateSeriesUID!
            : fallbackSeriesUID
        refs.append(HierarchicalSOPReference(
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: prSeriesUID,
            sopClassUID: presentationState.sopClassUID,
            sopInstanceUID: presentationState.sopInstanceUID
        ))
        return refs
    }

    // MARK: - PR / Annotations -> Key Object Selection (TID 2010)

    /// Builds a DICOM PS3.16 **TID 2010 Key Object Selection (KOS)** document referencing all images
    /// in the given `PresentationStateDocument` with the nested Softcopy Presentation State reference
    /// (`(0008,1199)`) attached to each `IMAGE` content item per PS3.3 Table C.18.4-1.
    public static func buildKeyObjectSelection(
        from presentationState: PresentationStateDocument,
        patient: PresentationStatePatientContext,
        purpose: DocumentTitle = .ofInterest,
        description: String? = nil,
        includeStandalonePresentationStateReference: Bool = false,
        sopInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        presentationStateSeriesUID: String? = nil,
        seriesNumber: Int = 9003
    ) throws -> SRDocument {
        var builder = KeyObjectSelectionBuilder(validateOnBuild: true)
            .withSOPInstanceUID(sopInstanceUID ?? UIDGenerator.generateUID().value)
            .withStudyInstanceUID(patient.studyInstanceUID)
            .withSeriesInstanceUID(seriesInstanceUID ?? UIDGenerator.generateUID().value)
            .withSeriesNumber(String(seriesNumber))
            .withDocumentTitle(purpose)

        if let patientID = patient.patientID { builder = builder.withPatientID(patientID) }
        if let patientName = patient.patientName { builder = builder.withPatientName(patientName) }
        if let birthDate = patient.patientBirthDate { builder = builder.withPatientBirthDate(birthDate) }
        if let sex = patient.patientSex { builder = builder.withPatientSex(sex) }
        if let studyDate = patient.studyDate { builder = builder.withStudyDate(studyDate) }
        if let studyTime = patient.studyTime { builder = builder.withStudyTime(studyTime) }
        if let accession = patient.accessionNumber { builder = builder.withAccessionNumber(accession) }
        if let referring = patient.referringPhysicianName { builder = builder.withReferringPhysicianName(referring) }

        let prRef = presentationState.referencedSOP
        let desc = description ?? presentationState.presentationDescription ?? presentationState.presentationLabel
        if let desc, !desc.isEmpty {
            builder = builder.withSelectionDescription(desc)
        }

        for series in presentationState.referencedSeries {
            for image in series.referencedImages {
                builder = builder.addKeyObject(
                    sopClassUID: image.sopClassUID,
                    sopInstanceUID: image.sopInstanceUID,
                    description: nil,
                    frames: image.referencedFrameNumbers,
                    presentationStateReference: prRef
                )
            }
        }

        if includeStandalonePresentationStateReference {
            builder = builder.addKeyObject(
                sopClassUID: presentationState.sopClassUID,
                sopInstanceUID: presentationState.sopInstanceUID,
                description: nil
            )
        }

        var kosDoc = try builder.build()
        let evidence = collectEvidenceReferences(
            from: presentationState,
            studyInstanceUID: patient.studyInstanceUID,
            presentationStateSeriesUID: presentationStateSeriesUID,
            fallbackSeriesUID: kosDoc.seriesInstanceUID ?? patient.studyInstanceUID
        )
        if !evidence.isEmpty {
            kosDoc = kosDoc.withEvidenceReferences(evidence)
        }
        return kosDoc
    }

    // MARK: - SR -> Annotations & Presentation State References

    /// Extracts high-level `[DICOMAnnotation]` (from `SCOORD`, `NUM`, and `TEXT` items) and all
    /// referenced Softcopy Presentation State SOP instances (GSPS, CSPS, Pseudo-CSPS, Blending)
    /// from a parsed `SRDocument`.
    public static func extract(
        from document: SRDocument,
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        targetCoordinateSpace: DICOMAnnotationCoordinateSpace = .pixel
    ) -> ExtractedSRAnnotations {
        var annotations: [DICOMAnnotation] = []
        var prRefs: [ReferencedSOP] = []
        var seenPRUIDs = Set<String>()
        var imageRefs: [ImageReference] = []

        let presentationStateSOPClasses: Set<String> = [
            .grayscaleSoftcopyPresentationStateStorage,
            .colorSoftcopyPresentationStateStorage,
            .pseudoColorSoftcopyPresentationStateStorage,
            .blendingSoftcopyPresentationStateStorage
        ]

        func recordPR(_ ref: ReferencedSOP) {
            if seenPRUIDs.insert(ref.sopInstanceUID).inserted {
                prRefs.append(ref)
            }
        }

        func walk(_ item: AnyContentItem, groupTrackingID: String?, groupTrackingUID: String?, groupText: String?, groupMeasurements: [DICOMAnnotationMeasurement]) {
            if let imageItem = item.asImage {
                imageRefs.append(imageItem.imageReference)
                if let pr = imageItem.imageReference.presentationStateReference {
                    recordPR(pr)
                }
            } else if let compositeItem = item.asComposite {
                let ref = compositeItem.referencedSOPSequence
                if presentationStateSOPClasses.contains(ref.sopClassUID) {
                    recordPR(ref)
                }
            }

            if let container = item.asContainer {
                var trackingID = groupTrackingID
                var trackingUID = groupTrackingUID
                var textComment = groupText
                var measurements = groupMeasurements
                var containerSCOORDs: [SpatialCoordinatesContentItem] = []

                for child in container.contentItems {
                    if let textItem = child.asText {
                        let codeVal = textItem.conceptName?.codeValue
                        if codeVal == "112039" {
                            trackingID = textItem.textValue
                        } else if codeVal == "121106" || (codeVal != "C67447" && codeVal != "C2348792") {
                            textComment = textItem.textValue
                        }
                    } else if let uidItem = child.asUIDRef, uidItem.conceptName?.codeValue == "112040" {
                        trackingUID = uidItem.uidValue
                    } else if let numItem = child.asNumeric,
                              let val = numItem.numericValues.first,
                              let concept = numItem.conceptName,
                              let units = numItem.measurementUnits {
                        let m = DICOMAnnotationMeasurement(concept: concept, value: val, units: units)
                        measurements.append(m)
                        // Check if this NUM has a child INFERRED FROM SCOORD (TID 300 -> TID 320)
                        for numChild in numItem.contentItems {
                            if let scoord = numChild.asSpatialCoordinates {
                                containerSCOORDs.append(scoord)
                            }
                            walk(numChild, groupTrackingID: trackingID, groupTrackingUID: trackingUID, groupText: textComment, groupMeasurements: [m])
                        }
                    } else if let scoord = child.asSpatialCoordinates {
                        containerSCOORDs.append(scoord)
                    }
                }

                // Convert unique SCOORDs in this container into DICOMAnnotations
                var seenGeometries = Set<[Float]>()
                for scoord in containerSCOORDs {
                    guard seenGeometries.insert(scoord.graphicData).inserted else { continue }
                    if let ann = annotationFromSCOORD(
                        scoord,
                        trackingID: trackingID,
                        trackingUID: trackingUID,
                        text: textComment,
                        measurements: measurements,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        targetSpace: targetCoordinateSpace,
                        recordPR: recordPR,
                        recordImage: { imageRefs.append($0) }
                    ) {
                        annotations.append(ann)
                    }
                }

                for child in container.contentItems {
                    if child.asSpatialCoordinates == nil && child.asNumeric == nil {
                        walk(child, groupTrackingID: trackingID, groupTrackingUID: trackingUID, groupText: textComment, groupMeasurements: measurements)
                    }
                }
            } else {
                for child in item.contentItems {
                    walk(child, groupTrackingID: groupTrackingID, groupTrackingUID: groupTrackingUID, groupText: groupText, groupMeasurements: groupMeasurements)
                }
            }
        }

        walk(AnyContentItem(document.rootContent), groupTrackingID: nil, groupTrackingUID: nil, groupText: nil, groupMeasurements: [])

        return ExtractedSRAnnotations(
            annotations: annotations,
            presentationStateReferences: prRefs,
            imageReferences: imageRefs
        )
    }

    // MARK: - Private Geometry Helpers

    private static func scoordGeometry(
        for annotation: DICOMAnnotation,
        imageWidth: Int,
        imageHeight: Int
    ) -> (GraphicType, [Float]) {
        let pixelPts = annotation.points.map {
            $0.toPixel(space: annotation.coordinateSpace, imageWidth: imageWidth, imageHeight: imageHeight)
        }
        guard !pixelPts.isEmpty else { return (.point, []) }

        switch annotation.kind {
        case .point, .crosshair, .text:
            let p = pixelPts[0]
            return (.point, [Float(p.column), Float(p.row)])

        case .arrow, .annotation, .ruler:
            guard pixelPts.count >= 2 else {
                let p = pixelPts[0]
                return (.point, [Float(p.column), Float(p.row)])
            }
            return (.polyline, [
                Float(pixelPts[0].column), Float(pixelPts[0].row),
                Float(pixelPts[1].column), Float(pixelPts[1].row)
            ])

        case .angle, .polyline:
            let floats = pixelPts.flatMap { [Float($0.column), Float($0.row)] }
            return (.polyline, floats)

        case .rectangle:
            // PS3.3 C.18.6.1.2: closed polygon in 2D SCOORD is POLYLINE with first vertex repeated at the end
            guard pixelPts.count >= 2 else { return (.point, []) }
            let minCol = Float(min(pixelPts[0].column, pixelPts[1].column))
            let maxCol = Float(max(pixelPts[0].column, pixelPts[1].column))
            let minRow = Float(min(pixelPts[0].row, pixelPts[1].row))
            let maxRow = Float(max(pixelPts[0].row, pixelPts[1].row))
            return (.polyline, [
                minCol, minRow,
                maxCol, minRow,
                maxCol, maxRow,
                minCol, maxRow,
                minCol, minRow
            ])

        case .circle:
            guard pixelPts.count >= 2 else { return (.point, []) }
            return (.circle, [
                Float(pixelPts[0].column), Float(pixelPts[0].row),
                Float(pixelPts[1].column), Float(pixelPts[1].row)
            ])

        case .ellipse:
            if pixelPts.count >= 4 {
                let floats = pixelPts.prefix(4).flatMap { [Float($0.column), Float($0.row)] }
                return (.ellipse, floats)
            } else if pixelPts.count >= 2 {
                let minCol = min(pixelPts[0].column, pixelPts[1].column)
                let maxCol = max(pixelPts[0].column, pixelPts[1].column)
                let minRow = min(pixelPts[0].row, pixelPts[1].row)
                let maxRow = max(pixelPts[0].row, pixelPts[1].row)
                let midCol = (minCol + maxCol) / 2.0
                let midRow = (minRow + maxRow) / 2.0
                let floats: [Double]
                if (maxCol - minCol) >= (maxRow - minRow) {
                    floats = [minCol, midRow, maxCol, midRow, midCol, minRow, midCol, maxRow]
                } else {
                    floats = [midCol, minRow, midCol, maxRow, minCol, midRow, maxCol, midRow]
                }
                return (.ellipse, floats.map(Float.init))
            }
            return (.point, [])
        }
    }

    private static func annotationFromSCOORD(
        _ scoord: SpatialCoordinatesContentItem,
        trackingID: String?,
        trackingUID: String?,
        text: String?,
        measurements: [DICOMAnnotationMeasurement],
        imageWidth: Int,
        imageHeight: Int,
        targetSpace: DICOMAnnotationCoordinateSpace,
        recordPR: (ReferencedSOP) -> Void,
        recordImage: (ImageReference) -> Void
    ) -> DICOMAnnotation? {
        guard scoord.graphicData.count >= 2 else { return nil }
        var pts: [DICOMAnnotationPoint] = []
        for idx in stride(from: 0, to: scoord.graphicData.count - 1, by: 2) {
            pts.append(.fromPixel(
                column: Double(scoord.graphicData[idx]),
                row: Double(scoord.graphicData[idx + 1]),
                targetSpace: targetSpace,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            ))
        }

        var selectedImage: ImageReference?
        for child in scoord.contentItems {
            if let imgItem = child.asImage {
                selectedImage = imgItem.imageReference
                recordImage(imgItem.imageReference)
                if let pr = imgItem.imageReference.presentationStateReference {
                    recordPR(pr)
                }
            }
        }

        let kind: DICOMAnnotationKind
        var outputPoints = pts
        switch scoord.graphicType {
        case .point, .multipoint:
            kind = .point
        case .circle:
            kind = .circle
        case .ellipse:
            kind = .ellipse
        case .polyline, .polygon:
            if pts.count == 2, measurements.contains(where: { $0.concept.codeValue == "410668003" || $0.concept.codeMeaning.lowercased().contains("length") }) {
                kind = .ruler
            } else if pts.count == 3, measurements.contains(where: {
                $0.concept.codeValue == "1483009" || $0.concept.codeValue == "364499001" || $0.concept.codeMeaning.lowercased().contains("angle")
            }) {
                kind = .angle
            } else if pts.count == 5, pts.first == pts.last, Self.isAxisAlignedRectangle(pts) {
                kind = .rectangle
                let xs = pts.map(\.x)
                let ys = pts.map(\.y)
                if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                    outputPoints = [
                        DICOMAnnotationPoint(x: minX, y: minY),
                        DICOMAnnotationPoint(x: maxX, y: maxY)
                    ]
                }
            } else {
                kind = .polyline
            }
        }

        let label = text ?? measurements.first?.formattedString ?? trackingID ?? ""

        return DICOMAnnotation(
            kind: kind,
            coordinateSpace: targetSpace,
            points: outputPoints,
            text: label,
            referencedSOPClassUID: selectedImage?.sopReference.sopClassUID,
            referencedSOPInstanceUID: selectedImage?.sopReference.sopInstanceUID,
            referencedFrameNumbers: selectedImage?.frameNumbers,
            measurements: measurements,
            trackingIdentifier: trackingID,
            trackingUID: trackingUID
        )
    }

    private static func isAxisAlignedRectangle(_ pts: [DICOMAnnotationPoint]) -> Bool {
        guard pts.count == 5 else { return false }
        let eps = 1e-4
        let horizontalFirst = abs(pts[0].y - pts[1].y) <= eps
            && abs(pts[1].x - pts[2].x) <= eps
            && abs(pts[2].y - pts[3].y) <= eps
            && abs(pts[3].x - pts[0].x) <= eps
        let verticalFirst = abs(pts[0].x - pts[1].x) <= eps
            && abs(pts[1].y - pts[2].y) <= eps
            && abs(pts[2].x - pts[3].x) <= eps
            && abs(pts[3].y - pts[0].y) <= eps
        return horizontalFirst || verticalFirst
    }
}
