// SRSerializationBridge.swift
// DICOMStudio
//
// DICOM Studio — Bidirectional bridge between DICOMStudio's UI SR model and DICOMKit's Part 10 SR engine.
// NEMA-verified: 2026a, checked 2026-11-19 — PS3.3 2026a Table 8.8-1a (Code Value SH <= 16 chars vs Long Code Value (0008,0119)), C.17.1 (SR Document Series Modality = "SR"), C.17.2 (SR Document General CompletionFlag, VerificationFlag, Type 1C VerifyingObserverSequence (0040,A073), Type 1C CurrentRequestedProcedureEvidenceSequence (0040,A375)), C.17.3 (SR Document Content 16 value types & 7 relationships), and C.17.6 (Key Object Document Series Modality = "KO" and Type 1 Evidence Sequence)

import Foundation
import DICOMCore
import DICOMKit

/// Bridges `DICOMStudio.SRDocument` and `DICOMKit.SRDocument` for Part 10 `.dcm` file I/O
/// and study series publishing.
public enum SRSerializationBridge {

    /// Explicit VR Little Endian transfer syntax UID (PS3.6 Table A-1).
    public static let explicitVRLittleEndianUID = "1.2.840.10008.1.2.1"

    // MARK: - Studio -> DICOMKit

    /// Converts a `DICOMStudio.CodedConcept` into a `DICOMCore.CodedConcept`, switching to
    /// `LongCodeValue (0008,0119)` whenever the code string exceeds 16 characters (PS3.3 Table 8.8-1a).
    public static func toCoreConcept(_ concept: CodedConcept) -> DICOMCore.CodedConcept {
        if concept.codeValue.count > 16 {
            return DICOMCore.CodedConcept(
                codeValue: "",
                codingSchemeDesignator: concept.codingSchemeDesignator,
                codeMeaning: concept.codeMeaning,
                codingSchemeVersion: concept.codingSchemeVersion,
                longCodeValue: concept.codeValue
            )
        }
        return DICOMCore.CodedConcept(
            codeValue: concept.codeValue,
            codingSchemeDesignator: concept.codingSchemeDesignator,
            codeMeaning: concept.codeMeaning,
            codingSchemeVersion: concept.codingSchemeVersion
        )
    }

    /// Converts a `DICOMCore.CodedConcept` into a `DICOMStudio.CodedConcept`.
    public static func toStudioConcept(_ concept: DICOMCore.CodedConcept) -> CodedConcept {
        let resolvedValue: String
        if !concept.codeValue.isEmpty {
            resolvedValue = concept.codeValue
        } else if let longVal = concept.longCodeValue, !longVal.isEmpty {
            resolvedValue = longVal
        } else if let urnVal = concept.urnCodeValue, !urnVal.isEmpty {
            resolvedValue = urnVal
        } else {
            resolvedValue = ""
        }
        return CodedConcept(
            codeValue: resolvedValue,
            codingSchemeDesignator: concept.codingSchemeDesignator,
            codeMeaning: concept.codeMeaning,
            codingSchemeVersion: concept.codingSchemeVersion
        )
    }

    /// Converts a `DICOMStudio.SRDocument` into a standards-conformant `DICOMKit.SRDocument`.
    public static func toDICOMKitDocument(
        _ studioDoc: SRDocument,
        verifyingObserverName: String = "STATELESS^VERIFIER",
        verifyingOrganization: String = "DICOMStudio",
        preliminaryFlag: PreliminaryFlag? = nil,
        studyDescription: String? = nil,
        seriesDescription: String? = nil
    ) -> DICOMKit.SRDocument {
        let sopInstanceUID = studioDoc.sopInstanceUID.isEmpty
            ? UIDGenerator.generateUID().value
            : studioDoc.sopInstanceUID
        let studyInstanceUID = studioDoc.studyInstanceUID.isEmpty
            ? UIDGenerator.generateStudyInstanceUID().value
            : studioDoc.studyInstanceUID
        let seriesInstanceUID = studioDoc.seriesInstanceUID.isEmpty
            ? UIDGenerator.generateSeriesInstanceUID().value
            : studioDoc.seriesInstanceUID

        let sopClassUID = studioDoc.documentType.sopClassUID
        let isKOS = studioDoc.documentType == .keyObjectSelection
        let modality = isKOS ? "KO" : "SR"
        let defaultSeriesNumber = isKOS ? "9003" : "9002"
        let defaultSeriesDesc = isKOS ? "Key Object Selection" : "Structured Reports"

        let now = currentDICOMTimestamp()
        let contentDate = studioDoc.contentDate.isEmpty ? now.date : studioDoc.contentDate
        let contentTime = studioDoc.contentTime.isEmpty ? now.time : studioDoc.contentTime

        let rootConcept = studioDoc.rootContentItem.conceptName.map(toCoreConcept)
            ?? toCoreConcept(studioDoc.title)
        let rootContinuity: DICOMCore.ContinuityOfContent =
            studioDoc.rootContentItem.continuityOfContent == .continuous ? .continuous : .separate
        let rootChildren = studioDoc.rootContentItem.children.map { toCoreItem($0, isKOS: isKOS) }

        let rootContainer = ContainerContentItem(
            conceptName: rootConcept,
            continuityOfContent: rootContinuity,
            contentItems: rootChildren,
            templateIdentifier: isKOS ? "2010" : (studioDoc.documentType == .measurementReport ? "1500" : nil),
            mappingResource: (isKOS || studioDoc.documentType == .measurementReport) ? "DCMR" : nil
        )

        var verifyingObservers: [VerifyingObserver] = []
        if !isKOS && studioDoc.isVerified {
            let trimmedVerifier = verifyingObserverName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOrg = verifyingOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
            verifyingObservers.append(
                VerifyingObserver(
                    name: trimmedVerifier.isEmpty ? "UNKNOWN^VERIFIER" : trimmedVerifier,
                    organization: trimmedOrg.isEmpty ? "DICOMStudio" : trimmedOrg,
                    verificationDateTime: "\(contentDate)\(contentTime)"
                )
            )
        }

        let evidence = collectEvidence(
            from: rootChildren,
            studyInstanceUID: studyInstanceUID,
            fallbackSeriesUID: seriesInstanceUID
        )

        return DICOMKit.SRDocument(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            patientID: studioDoc.patientID.isEmpty ? nil : studioDoc.patientID,
            patientName: studioDoc.patientName.isEmpty ? nil : studioDoc.patientName,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: defaultSeriesNumber,
            modality: modality,
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: "1",
            completionFlag: isKOS ? nil : (studioDoc.isComplete ? .complete : .partial),
            verificationFlag: isKOS ? nil : (studioDoc.isVerified ? .verified : .unverified),
            preliminaryFlag: isKOS ? nil : preliminaryFlag,
            verifyingObservers: verifyingObservers,
            documentTitle: rootConcept,
            rootContent: rootContainer,
            studyDescription: studyDescription,
            seriesDescription: seriesDescription ?? defaultSeriesDesc,
            evidenceReferences: evidence
        )
    }

    /// Serializes a `DICOMStudio.SRDocument` to DICOM Part 10 binary `Data`.
    public static func serialize(
        _ studioDoc: SRDocument,
        verifyingObserverName: String = "STATELESS^VERIFIER",
        verifyingOrganization: String = "DICOMStudio",
        preliminaryFlag: PreliminaryFlag? = nil
    ) throws -> Data {
        let kitDoc = toDICOMKitDocument(
            studioDoc,
            verifyingObserverName: verifyingObserverName,
            verifyingOrganization: verifyingOrganization,
            preliminaryFlag: preliminaryFlag
        )
        let dataSet = try SRDocumentSerializer().serialize(document: kitDoc)
        let dicomFile = DICOMFile.create(
            dataSet: dataSet,
            sopClassUID: kitDoc.sopClassUID,
            sopInstanceUID: kitDoc.sopInstanceUID,
            transferSyntaxUID: explicitVRLittleEndianUID
        )
        return try dicomFile.write()
    }

    // MARK: - DICOMKit -> Studio

    /// Converts a parsed `DICOMKit.SRDocument` into a `DICOMStudio.SRDocument`.
    public static func fromDICOMKitDocument(_ kitDoc: DICOMKit.SRDocument) -> SRDocument {
        let studioType = studioDocumentType(for: kitDoc)
        let rootItem = fromCoreContainer(kitDoc.rootContent, relationship: .contains)
        let title = kitDoc.documentTitle.map(toStudioConcept)
            ?? rootItem.conceptName
            ?? SRBuilderHelpers.documentTitle(for: studioType)

        return SRDocument(
            documentType: studioType,
            title: title,
            patientName: kitDoc.patientName ?? "",
            patientID: kitDoc.patientID ?? "",
            studyInstanceUID: kitDoc.studyInstanceUID ?? "",
            seriesInstanceUID: kitDoc.seriesInstanceUID ?? "",
            sopInstanceUID: kitDoc.sopInstanceUID,
            contentDate: kitDoc.contentDate ?? "",
            contentTime: kitDoc.contentTime ?? "",
            rootContentItem: rootItem,
            isComplete: kitDoc.completionFlag == .complete,
            isVerified: kitDoc.verificationFlag == .verified
        )
    }

    /// Reads a Part 10 `.dcm` file from disk and parses it into a `DICOMStudio.SRDocument`.
    public static func readDocument(from url: URL) throws -> SRDocument {
        let data = try Data(contentsOf: url)
        return try readDocument(from: data)
    }

    /// Parses Part 10 `.dcm` binary `Data` into a `DICOMStudio.SRDocument`.
    public static func readDocument(from data: Data) throws -> SRDocument {
        let file = try DICOMFile.read(from: data)
        let kitDoc = try SRDocumentParser().parse(dataSet: file.dataSet)
        return fromDICOMKitDocument(kitDoc)
    }

    // MARK: - Private Item Mapping

    private static func toCoreRelationship(_ rel: SRRelationshipType) -> RelationshipType {
        RelationshipType(rawValue: rel.rawValue) ?? .contains
    }

    private static func fromCoreRelationship(_ rel: RelationshipType?) -> SRRelationshipType {
        guard let rel else { return .contains }
        return SRRelationshipType(rawValue: rel.rawValue) ?? .contains
    }

    private static func toCoreItem(_ item: SRContentItem, isKOS: Bool) -> AnyContentItem {
        let rel = toCoreRelationship(item.relationshipType)
        let children = item.children.map { toCoreItem($0, isKOS: isKOS) }
        // Ensure non-KOS items whose relationship requires ConceptNameCodeSequence (Type 1C, PS3.3 C.17.3.2.2)
        // carry a fallback concept name if omitted in free-form editing.
        let concept: DICOMCore.CodedConcept?
        if let c = item.conceptName {
            concept = toCoreConcept(c)
        } else if isKOS && (item.valueType == .image || item.valueType == .composite || item.valueType == .waveform) {
            concept = nil
        } else if item.valueType == .spatialCoord || item.valueType == .spatialCoord3D || item.valueType == .temporalCoord {
            concept = nil
        } else if item.relationshipType == .selectedFrom || item.relationshipType == .inferredFrom {
            concept = nil
        } else {
            concept = DICOMCore.CodedConcept(codeValue: "121106", codingSchemeDesignator: "DCM", codeMeaning: "Comment")
        }

        switch item.valueType {
        case .container:
            let cont: DICOMCore.ContinuityOfContent = item.continuityOfContent == .continuous ? .continuous : .separate
            return AnyContentItem(ContainerContentItem(
                conceptName: concept,
                continuityOfContent: cont,
                contentItems: children,
                relationshipType: rel
            ))
        case .text:
            return AnyContentItem(TextContentItem(
                conceptName: concept,
                textValue: item.textValue ?? "",
                relationshipType: rel,
                contentItems: children
            ))
        case .code:
            let val = item.codeValue.map(toCoreConcept)
                ?? DICOMCore.CodedConcept(codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding")
            return AnyContentItem(CodeContentItem(
                conceptName: concept,
                conceptCode: val,
                relationshipType: rel,
                contentItems: children
            ))
        case .numeric:
            let val = item.numericValue ?? 0.0
            let unit = item.measurementUnit.map(toCoreConcept)
                ?? DICOMCore.CodedConcept(codeValue: "1", codingSchemeDesignator: "UCUM", codeMeaning: "no units")
            return AnyContentItem(NumericContentItem(
                conceptName: concept,
                value: val,
                units: unit,
                relationshipType: rel,
                contentItems: children
            ))
        case .date:
            return AnyContentItem(DateContentItem(
                conceptName: concept,
                dateValue: item.dateValue ?? currentDICOMTimestamp().date,
                relationshipType: rel,
                contentItems: children
            ))
        case .time:
            return AnyContentItem(TimeContentItem(
                conceptName: concept,
                timeValue: item.timeValue ?? currentDICOMTimestamp().time,
                relationshipType: rel,
                contentItems: children
            ))
        case .dateTime:
            let stamp = currentDICOMTimestamp()
            return AnyContentItem(DateTimeContentItem(
                conceptName: concept,
                dateTimeValue: item.dateTimeValue ?? "\(stamp.date)\(stamp.time)",
                relationshipType: rel,
                contentItems: children
            ))
        case .personName:
            return AnyContentItem(PersonNameContentItem(
                conceptName: concept,
                personName: item.personName ?? "UNKNOWN",
                relationshipType: rel,
                contentItems: children
            ))
        case .uidRef:
            return AnyContentItem(UIDRefContentItem(
                conceptName: concept,
                uidValue: item.uidValue ?? UIDGenerator.generateUID().value,
                relationshipType: rel,
                contentItems: children
            ))
        case .spatialCoord:
            let rawType = item.graphicType?.rawValue ?? "POINT"
            let coreType = DICOMCore.GraphicType(rawValue: rawType == "POLYGON" ? "POLYLINE" : rawType) ?? .point
            let coords = (item.graphicData ?? [0.0, 0.0]).map(Float.init)
            return AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: item.conceptName.map(toCoreConcept),
                graphicType: coreType,
                graphicData: coords,
                relationshipType: rel,
                contentItems: children
            ))
        case .spatialCoord3D:
            let coreType = DICOMCore.GraphicType3D(rawValue: item.graphicType3D?.rawValue ?? "POINT") ?? .point
            let coords = (item.graphicData3D ?? [0.0, 0.0, 0.0]).map(Float.init)
            return AnyContentItem(SpatialCoordinates3DContentItem(
                conceptName: item.conceptName.map(toCoreConcept),
                graphicType: coreType,
                graphicData: coords,
                frameOfReferenceUID: UIDGenerator.generateUID().value,
                relationshipType: rel,
                contentItems: children
            ))
        case .temporalCoord:
            let rangeType = DICOMCore.TemporalRangeType(rawValue: item.temporalRangeType?.rawValue ?? "POINT") ?? .point
            return AnyContentItem(TemporalCoordinatesContentItem(
                conceptName: item.conceptName.map(toCoreConcept),
                temporalRangeType: rangeType,
                samplePositions: [1],
                relationshipType: rel,
                contentItems: children
            ))
        case .composite:
            let sopRef = ReferencedSOP(
                sopClassUID: item.referencedSOPClassUID ?? "1.2.840.10008.5.1.4.1.1.88.33",
                sopInstanceUID: item.referencedSOPInstanceUID ?? UIDGenerator.generateUID().value
            )
            return AnyContentItem(CompositeContentItem(
                conceptName: isKOS ? item.conceptName.map(toCoreConcept) : concept,
                referencedSOPSequence: sopRef,
                relationshipType: rel,
                contentItems: children
            ))
        case .image:
            let imgRef = ImageReference(
                sopClassUID: item.referencedSOPClassUID ?? "1.2.840.10008.5.1.4.1.1.7",
                sopInstanceUID: item.referencedSOPInstanceUID ?? UIDGenerator.generateUID().value,
                frameNumbers: item.referencedFrameNumbers
            )
            return AnyContentItem(ImageContentItem(
                conceptName: isKOS ? item.conceptName.map(toCoreConcept) : concept,
                imageReference: imgRef,
                relationshipType: rel,
                contentItems: children
            ))
        case .waveform:
            let wfRef = WaveformReference(
                sopReference: ReferencedSOP(
                    sopClassUID: item.referencedSOPClassUID ?? "1.2.840.10008.5.1.4.1.1.9.1.1",
                    sopInstanceUID: item.referencedSOPInstanceUID ?? UIDGenerator.generateUID().value
                )
            )
            return AnyContentItem(WaveformContentItem(
                conceptName: isKOS ? item.conceptName.map(toCoreConcept) : concept,
                waveformReference: wfRef,
                relationshipType: rel,
                contentItems: children
            ))
        case .table:
            return AnyContentItem(TextContentItem(
                conceptName: concept,
                textValue: item.textValue ?? "Table",
                relationshipType: rel,
                contentItems: children
            ))
        }
    }

    private static func fromCoreContainer(
        _ container: ContainerContentItem,
        relationship: SRRelationshipType
    ) -> SRContentItem {
        SRContentItem(
            valueType: .container,
            conceptName: container.conceptName.map(toStudioConcept),
            relationshipType: relationship,
            continuityOfContent: container.continuityOfContent == .continuous ? .continuous : .separate,
            children: container.contentItems.map(fromCoreItem)
        )
    }

    private static func fromCoreItem(_ item: AnyContentItem) -> SRContentItem {
        let rel = fromCoreRelationship(item.relationshipType)
        let concept = item.conceptName.map(toStudioConcept)
        let children = item.contentItems.map(fromCoreItem)

        if let c = item.asContainer {
            return fromCoreContainer(c, relationship: rel)
        }
        if let t = item.asText {
            return SRContentItem(valueType: .text, conceptName: concept, relationshipType: rel, textValue: t.textValue, children: children)
        }
        if let c = item.asCode {
            return SRContentItem(valueType: .code, conceptName: concept, relationshipType: rel, codeValue: toStudioConcept(c.conceptCode), children: children)
        }
        if let n = item.asNumeric {
            return SRContentItem(
                valueType: .numeric,
                conceptName: concept,
                relationshipType: rel,
                numericValue: n.numericValues.first,
                measurementUnit: n.measurementUnits.map(toStudioConcept),
                children: children
            )
        }
        if let d = item.asDate {
            return SRContentItem(valueType: .date, conceptName: concept, relationshipType: rel, dateValue: d.dateValue, children: children)
        }
        if let tm = item.asTime {
            return SRContentItem(valueType: .time, conceptName: concept, relationshipType: rel, timeValue: tm.timeValue, children: children)
        }
        if let dt = item.asDateTime {
            return SRContentItem(valueType: .dateTime, conceptName: concept, relationshipType: rel, dateTimeValue: dt.dateTimeValue, children: children)
        }
        if let pn = item.asPersonName {
            return SRContentItem(valueType: .personName, conceptName: concept, relationshipType: rel, personName: pn.personName, children: children)
        }
        if let u = item.asUIDRef {
            return SRContentItem(valueType: .uidRef, conceptName: concept, relationshipType: rel, uidValue: u.uidValue, children: children)
        }
        if let sc = item.asSpatialCoordinates {
            return SRContentItem(
                valueType: .spatialCoord,
                conceptName: concept,
                relationshipType: rel,
                graphicType: SpatialCoordGraphicType(rawValue: sc.graphicType.rawValue) ?? .polyline,
                graphicData: sc.graphicData.map(Double.init),
                children: children
            )
        }
        if let sc3 = item.asSpatialCoordinates3D {
            return SRContentItem(
                valueType: .spatialCoord3D,
                conceptName: concept,
                relationshipType: rel,
                graphicType3D: SpatialCoord3DGraphicType(rawValue: sc3.graphicType.rawValue) ?? .polyline,
                graphicData3D: sc3.graphicData.map(Double.init),
                children: children
            )
        }
        if let tc = item.asTemporalCoordinates {
            return SRContentItem(
                valueType: .temporalCoord,
                conceptName: concept,
                relationshipType: rel,
                temporalRangeType: TemporalRangeType(rawValue: tc.temporalRangeType.rawValue) ?? .point,
                children: children
            )
        }
        if let comp = item.asComposite {
            return SRContentItem(
                valueType: .composite,
                conceptName: concept,
                relationshipType: rel,
                referencedSOPClassUID: comp.referencedSOPSequence.sopClassUID,
                referencedSOPInstanceUID: comp.referencedSOPSequence.sopInstanceUID,
                children: children
            )
        }
        if let img = item.asImage {
            return SRContentItem(
                valueType: .image,
                conceptName: concept,
                relationshipType: rel,
                referencedSOPClassUID: img.imageReference.sopReference.sopClassUID,
                referencedSOPInstanceUID: img.imageReference.sopReference.sopInstanceUID,
                referencedFrameNumbers: img.imageReference.frameNumbers,
                children: children
            )
        }
        if let wf = item.asWaveform {
            return SRContentItem(
                valueType: .waveform,
                conceptName: concept,
                relationshipType: rel,
                referencedSOPClassUID: wf.waveformReference.sopReference.sopClassUID,
                referencedSOPInstanceUID: wf.waveformReference.sopReference.sopInstanceUID,
                children: children
            )
        }
        if let tbl = item.asTable {
            return SRContentItem(
                valueType: .table,
                conceptName: concept,
                relationshipType: rel,
                textValue: "\(tbl.rows) × \(tbl.columns)",
                children: children
            )
        }
        return SRContentItem(valueType: .text, conceptName: concept, relationshipType: rel, textValue: "", children: children)
    }

    private static func studioDocumentType(for kitDoc: DICOMKit.SRDocument) -> SRDocumentType {
        if kitDoc.rootContent.templateIdentifier == "1500"
            || kitDoc.documentTitle?.codeValue == "126000" {
            return .measurementReport
        }
        switch kitDoc.sopClassUID {
        case "1.2.840.10008.5.1.4.1.1.88.11": return .basicText
        case "1.2.840.10008.5.1.4.1.1.88.22": return .enhanced
        case "1.2.840.10008.5.1.4.1.1.88.33": return .comprehensive
        case "1.2.840.10008.5.1.4.1.1.88.34", "1.2.840.10008.5.1.4.1.1.88.35": return .comprehensive3D
        case "1.2.840.10008.5.1.4.1.1.88.59": return .keyObjectSelection
        case "1.2.840.10008.5.1.4.1.1.88.50": return .mammographyCAD
        case "1.2.840.10008.5.1.4.1.1.88.65": return .chestCAD
        default: return .comprehensive
        }
    }

    private static func collectEvidence(
        from items: [AnyContentItem],
        studyInstanceUID: String,
        fallbackSeriesUID: String
    ) -> [HierarchicalSOPReference] {
        var refs: [HierarchicalSOPReference] = []
        var seen = Set<String>()

        func walk(_ list: [AnyContentItem]) {
            for item in list {
                if let img = item.asImage {
                    let uid = img.imageReference.sopReference.sopInstanceUID
                    if seen.insert(uid).inserted {
                        refs.append(HierarchicalSOPReference(
                            studyInstanceUID: studyInstanceUID,
                            seriesInstanceUID: fallbackSeriesUID,
                            sopClassUID: img.imageReference.sopReference.sopClassUID,
                            sopInstanceUID: uid
                        ))
                    }
                    if let pr = img.imageReference.presentationStateReference, seen.insert(pr.sopInstanceUID).inserted {
                        refs.append(HierarchicalSOPReference(
                            studyInstanceUID: studyInstanceUID,
                            seriesInstanceUID: fallbackSeriesUID,
                            sopClassUID: pr.sopClassUID,
                            sopInstanceUID: pr.sopInstanceUID
                        ))
                    }
                } else if let comp = item.asComposite {
                    let uid = comp.referencedSOPSequence.sopInstanceUID
                    if seen.insert(uid).inserted {
                        refs.append(HierarchicalSOPReference(
                            studyInstanceUID: studyInstanceUID,
                            seriesInstanceUID: fallbackSeriesUID,
                            sopClassUID: comp.referencedSOPSequence.sopClassUID,
                            sopInstanceUID: uid
                        ))
                    }
                } else if let wf = item.asWaveform {
                    let uid = wf.waveformReference.sopReference.sopInstanceUID
                    if seen.insert(uid).inserted {
                        refs.append(HierarchicalSOPReference(
                            studyInstanceUID: studyInstanceUID,
                            seriesInstanceUID: fallbackSeriesUID,
                            sopClassUID: wf.waveformReference.sopReference.sopClassUID,
                            sopInstanceUID: uid
                        ))
                    }
                }
                if !item.contentItems.isEmpty {
                    walk(item.contentItems)
                }
            }
        }
        walk(items)
        return refs
    }

    public static func currentDICOMTimestamp(date: Date = Date()) -> (date: String, time: String) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let d = String(format: "%04d%02d%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        let t = String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return (d, t)
    }
}
