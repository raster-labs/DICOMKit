import Testing
import Foundation
@testable import DICOMKit
@testable import DICOMCore

/// D50: PS3.16 2026a TID 4000 (Mammography CAD Document Root) and TID 4100 (Chest CAD Document
/// Root) are in the template registry with the templates they include, so the trees the CAD
/// builders write are checked row by row with `TemplateValidator`.
@Suite("CAD SR builder output validates against TID 4000 / TID 4100 (D50)")
struct CADTemplateValidationTests {

    private let mammogram = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.1.2", sopInstanceUID: "1.2.3.4.5.6.7.8.9")
    private let chestImage = ImageReference(sopClassUID: "1.2.840.10008.5.1.4.1.1.1.1", sopInstanceUID: "1.2.3.4.5.6.7.8.10")

    private func sct(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "SCT", codeMeaning: meaning)
    }

    private func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    private func validate(_ document: SRDocument, against template: TemplateIdentifier) -> TemplateValidationResult {
        TemplateValidator(mode: .strict).validate(AnyContentItem(document.rootContent), against: template)
    }

    private func describe(_ result: TemplateValidationResult) -> Comment {
        Comment(rawValue: result.violations.map(\.description).joined(separator: "\n"))
    }

    // MARK: - Mammography CAD (TID 4000)

    private func mammographyBuilder() -> MammographyCADSRBuilder {
        MammographyCADSRBuilder()
            .withPatientID("P1")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(algorithmName: "MammoCAD", algorithmVersion: "2.1.0",
                                      manufacturer: "Example Medical Systems")
    }

    private var mammographyDocuments: [(String, () throws -> SRDocument)] {
        let shape = CADDescriptor(conceptName: sct("107644003", "Shape"), value: sct("129734002", "Irregular"))
        let entry = CADImageLibraryEntry(
            image: mammogram,
            laterality: sct("80248007", "Left breast"),
            view: sct("399368009", "medio-lateral oblique"),
            viewModifiers: [sct("399163009", "Magnification")],
            patientOrientationRow: "A", patientOrientationColumn: "FR",
            studyDate: "20240115", studyTime: "143000", contentDate: "20240115", contentTime: "143001",
            horizontalPixelSpacingMM: 0.07, verticalPixelSpacingMM: 0.07
        )
        let analysis = CADAlgorithmRun(code: sct("133887000", "Image quality analysis"), seriesInstanceUIDs: ["1.2.3.4.5.6"])
        return [
            ("point finding", {
                try mammographyBuilder()
                    .addFinding(type: .mass, probability: 0.85, location: .point2D(x: 128.5, y: 256.3, imageReference: mammogram))
                    .build()
            }),
            ("circle, ROI, certainty, rendering intent, descriptors", {
                try mammographyBuilder()
                    .addFinding(CADFinding(type: .mass, probability: 0.5,
                                           location: .circle2D(centerX: 200, centerY: 300, radius: 25, imageReference: mammogram),
                                           renderingIntent: .notForPresentation, certainty: 0.9, descriptors: [shape]))
                    .addFinding(type: .calcification, probability: 0.4,
                                location: .roi2D(points: [0, 0, 10, 0, 10, 10, 0, 10], imageReference: mammogram))
                    .addFinding(type: .architecturalDistortion, probability: 0.3,
                                location: .point2D(x: 5, y: 5, imageReference: mammogram))
                    .build()
            }),
            ("non-lesion", {
                try mammographyBuilder()
                    .addFinding(type: .custom(dcm("111102", "Non-lesion")), probability: 0.5,
                                location: .point2D(x: 1, y: 1, imageReference: mammogram))
                    .build()
            }),
            ("image library entry, failed detection, analysis", {
                try mammographyBuilder()
                    .addImageLibraryEntry(entry)
                    .addDetectionPerformed(CADAlgorithmRun(code: FindingType.mass.concept, images: [mammogram]))
                    .addDetectionPerformed(CADAlgorithmRun(code: FindingType.calcification.concept, images: [mammogram],
                                                           succeeded: false))
                    .addAnalysisPerformed(analysis)
                    .addFinding(type: .mass, probability: 0.5, location: .point2D(x: 1, y: 1, imageReference: mammogram))
                    .withLanguage(CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English"),
                                  country: CodedConcept(codeValue: "US", codingSchemeDesignator: "ISO3166_1",
                                                        codeMeaning: "United States"))
                    .build()
            }),
        ]
    }

    @Test("MammographyCADSRBuilder output validates against TID 4000 with no violations")
    func mammographyValidates() throws {
        for (name, build) in mammographyDocuments {
            let result = validate(try build(), against: .mammographyCADDocumentRoot)
            #expect(result.isFullyCompliant, Comment(rawValue: name + "\n" + describe(result).rawValue))
        }
        // …and after a dataset round trip
        let (_, build) = mammographyDocuments[1]
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: try build()))
        let result = validate(parsed, against: .mammographyCADDocumentRoot)
        #expect(result.isFullyCompliant, describe(result))
    }

    @Test("A Mammography CAD tree without its Image Library or with a finding lacking TID 4019 is reported")
    func mammographyBrokenTreeIsReported() throws {
        let document = try mammographyDocuments[0].1()
        let root = AnyContentItem(document.rootContent)

        // TID 4000 row 3 (M): drop the (111028, DCM, "Image Library") CONTAINER
        let withoutLibrary = root.withContentItems(root.contentItems.filter { $0.conceptName?.codeValue != "111028" })
        let missing = TemplateValidator(mode: .strict).validate(withoutLibrary, against: .mammographyCADDocumentRoot)
        #expect(missing.errors.contains { $0.templateRowID == "3" }, describe(missing))

        // TID 4006 row 5 (M, INCLUDE TID 4019) → TID 4019 row 1 (Algorithm Name): strip the
        // Algorithm Name/Version from the Single Image Finding
        func strip(_ item: AnyContentItem) -> AnyContentItem {
            let kept = item.contentItems.filter {
                !(item.conceptName?.codeValue == "111059" && ["111001", "111003"].contains($0.conceptName?.codeValue ?? ""))
            }
            return item.withContentItems(kept.map(strip))
        }
        let broken = TemplateValidator(mode: .strict).validate(strip(root), against: .mammographyCADDocumentRoot)
        #expect(!broken.isCompliant, describe(broken))
        #expect(broken.errors.contains { $0.message.contains("Algorithm Name") }, describe(broken))

        // An extra item under the non-extensible TID 4000 root is unexpected content
        let extra = root.addingContentItems([.text(conceptName: dcm("121106", "Comment"), value: "x", relationshipType: .contains)])
        let unexpected = TemplateValidator(mode: .strict).validate(extra, against: .mammographyCADDocumentRoot)
        #expect(unexpected.warnings.contains { $0.message.contains("Comment") }, describe(unexpected))
    }

    // MARK: - Chest CAD (TID 4100)

    private func chestBuilder() -> ChestCADSRBuilder {
        ChestCADSRBuilder()
            .withPatientID("P1")
            .withStudyInstanceUID("1.2.3.4.5")
            .withCADProcessingSummary(algorithmName: "ChestCAD", algorithmVersion: "3.2.0",
                                      manufacturer: "Example Medical Systems")
    }

    private var chestDocuments: [(String, () throws -> SRDocument)] {
        let size = CADDescriptor(conceptName: dcm("112025", "Size Descriptor"), value: sct("255507004", "Small"))
        let location = CADDescriptor(conceptName: dcm("112013", "Location in Chest"), value: sct("39607008", "Lung"))
        return [
            ("no findings", { try chestBuilder().build() }),
            ("point, circle and ROI findings", {
                try chestBuilder()
                    .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 256.5, y: 384.7, imageReference: chestImage))
                    .addFinding(type: .mass, probability: 0.75,
                                location: .circle2D(centerX: 10, centerY: 20, radius: 5, imageReference: chestImage))
                    .addFinding(type: .treeInBud, probability: 0.88,
                                location: .roi2D(points: [0, 0, 1, 0, 1, 1], imageReference: chestImage))
                    .build()
            }),
            ("descriptors and rendering intent", {
                try chestBuilder()
                    .addFinding(ChestCADFinding(type: .nodule, probability: 0.5,
                                                location: .point2D(x: 1, y: 1, imageReference: chestImage),
                                                renderingIntent: .presentationOptional, descriptors: [size, location]))
                    .build()
            }),
            ("image quality finding", {
                try chestBuilder()
                    .addFinding(type: .custom(dcm("111101", "Image quality")), probability: 0.5,
                                location: .point2D(x: 1, y: 1, imageReference: chestImage))
                    .build()
            }),
            ("image library entry and analysis", {
                try chestBuilder()
                    .addImageLibraryEntry(CADImageLibraryEntry(
                        image: chestImage,
                        laterality: sct("51440002", "Bilateral"),
                        view: sct("272479007", "postero-anterior"),
                        studyDate: "20240101", studyTime: "120000"
                    ))
                    .addAnalysisPerformed(CADAlgorithmRun(code: sct("133886009", "Temporal correlation")))
                    .addFinding(type: .nodule, probability: 0.92, location: .point2D(x: 1, y: 1, imageReference: chestImage))
                    .build()
            }),
        ]
    }

    @Test("ChestCADSRBuilder output validates against TID 4100 with no violations")
    func chestValidates() throws {
        for (name, build) in chestDocuments {
            let result = validate(try build(), against: .chestCADDocumentRoot)
            #expect(result.isFullyCompliant, Comment(rawValue: name + "\n" + describe(result).rawValue))
        }
        let (_, build) = chestDocuments[1]
        let parsed = try SRDocumentParser().parse(dataSet: try SRDocumentSerializer().serialize(document: try build()))
        let result = validate(parsed, against: .chestCADDocumentRoot)
        #expect(result.isFullyCompliant, describe(result))
    }

    @Test("A Chest CAD tree without Summary of Detections is reported")
    func chestBrokenTreeIsReported() throws {
        let root = AnyContentItem(try chestDocuments[1].1().rootContent)
        // TID 4100 row 6 (M): (111064, DCM, "Summary of Detections")
        let broken = root.withContentItems(root.contentItems.filter { $0.conceptName?.codeValue != "111064" })
        let result = TemplateValidator(mode: .strict).validate(broken, against: .chestCADDocumentRoot)
        #expect(result.errors.map(\.templateRowID) == ["6"], describe(result))
    }

    @Test("The CAD roots and their includes are registered")
    func registered() {
        for tid in [4000, 4001, 4003, 4006, 4015, 4016, 4017, 4018, 4020, 4021, 4100, 4101, 4104, 4105, 4107] {
            let found = TemplateRegistry.shared.template(tid: tid) != nil
            #expect(found, Comment(rawValue: "TID \(tid)"))
        }
        #expect(TID4000MammographyCADDocumentRoot.isRoot)
        #expect(!TID4000MammographyCADDocumentRoot.isExtensible)
        #expect(TID4100ChestCADDocumentRoot.displayName == "Chest CAD Document Root")
    }
}
