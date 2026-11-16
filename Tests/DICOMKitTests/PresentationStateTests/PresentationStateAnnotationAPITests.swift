import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit

@Suite("GSPS, CSPS, and Pseudo-CSPS Public API & SR Bridge Tests")
struct PresentationStateAnnotationAPITests {

    // MARK: - Helpers

    private func makeMockImageDataSet(
        studyInstanceUID: String = "1.2.840.113619.2.55.3.100",
        seriesInstanceUID: String = "1.2.840.113619.2.55.3.101",
        sopInstanceUID: String = "1.2.840.113619.2.55.3.102",
        sopClassUID: String = "1.2.840.10008.5.1.4.1.1.2",
        photometricInterpretation: String = "MONOCHROME2",
        columns: UInt16 = 512,
        rows: UInt16 = 512,
        bitsAllocated: UInt16 = 16,
        bitsStored: UInt16 = 12,
        pixelRepresentation: UInt16 = 0
    ) -> DataSet {
        var ds = DataSet()
        ds.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        ds.setString(sopInstanceUID, for: .sopInstanceUID, vr: .UI)
        ds.setString(studyInstanceUID, for: .studyInstanceUID, vr: .UI)
        ds.setString(seriesInstanceUID, for: .seriesInstanceUID, vr: .UI)
        ds.setString("DOE^JANE", for: .patientName, vr: .PN)
        ds.setString("PAT-001", for: .patientID, vr: .LO)
        ds.setString("19800101", for: .patientBirthDate, vr: .DA)
        ds.setString("F", for: .patientSex, vr: .CS)
        ds.setString("20261114", for: .studyDate, vr: .DA)
        ds.setString("120000", for: .studyTime, vr: .TM)
        ds.setString("ACC-100", for: .accessionNumber, vr: .SH)
        ds.setString(photometricInterpretation, for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(columns, for: .columns)
        ds.setUInt16(rows, for: .rows)
        ds.setUInt16(bitsAllocated, for: .bitsAllocated)
        ds.setUInt16(bitsStored, for: .bitsStored)
        ds.setUInt16(pixelRepresentation, for: .pixelRepresentation)
        return ds
    }

    // MARK: - 1. Automatic SOP Class Selection (GSPS, CSPS, Pseudo-CSPS)

    @Test("PresentationStateManager automatically selects GSPS, CSPS, or Pseudo-CSPS per DICOM IOD rules")
    func testAutomaticSOPClassSelection() throws {
        // 1. Monochrome image without palette -> GSPS (1.2.840.10008.5.1.4.1.1.11.1)
        let ctDataSet = makeMockImageDataSet(photometricInterpretation: "MONOCHROME2")
        let gspsPackage = try PresentationStateManager.create(
            forImage: ctDataSet,
            configuration: PresentationStateConfiguration(
                presentationLabel: "GSPS_TEST",
                voiLUT: .window(center: 40, width: 400, explanation: "Soft Tissue", function: .linear)
            )
        )
        #expect(gspsPackage.document.kind == PresentationStateKind.grayscale)
        #expect(gspsPackage.document.sopClassUID == String.grayscaleSoftcopyPresentationStateStorage)
        #expect(gspsPackage.prDataSet.string(for: .sopClassUID) == "1.2.840.10008.5.1.4.1.1.11.1")

        // 2. Monochrome image with Hot Iron palette -> Pseudo-CSPS (1.2.840.10008.5.1.4.1.1.11.3)
        let petDataSet = makeMockImageDataSet(photometricInterpretation: "MONOCHROME2")
        let pcspsPackage = try PresentationStateManager.create(
            forImage: petDataSet,
            configuration: PresentationStateConfiguration(
                presentationLabel: "HOT_IRON",
                voiLUT: .window(center: 2048, width: 4096, explanation: nil, function: .linear),
                palette: .hotIron
            )
        )
        #expect(pcspsPackage.document.kind == PresentationStateKind.pseudoColor)
        #expect(pcspsPackage.document.sopClassUID == String.pseudoColorSoftcopyPresentationStateStorage)
        #expect(pcspsPackage.prDataSet.string(for: .sopClassUID) == "1.2.840.10008.5.1.4.1.1.11.3")
        #expect(pcspsPackage.prDataSet[.redPaletteColorLookupTableDescriptor] != nil)
        #expect(pcspsPackage.prDataSet[.iccProfile] != nil)
        #expect(pcspsPackage.prDataSet[.presentationLUTShape] == nil)

        // 3. RGB color image -> CSPS (1.2.840.10008.5.1.4.1.1.11.2)
        let usColorDataSet = makeMockImageDataSet(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.6.1",
            photometricInterpretation: "RGB",
            bitsAllocated: 8,
            bitsStored: 8
        )
        let cspsPackage = try PresentationStateManager.create(
            forImage: usColorDataSet,
            configuration: PresentationStateConfiguration(
                presentationLabel: "COLOR_ANNOT"
            )
        )
        #expect(cspsPackage.document.kind == PresentationStateKind.color)
        #expect(cspsPackage.document.sopClassUID == String.colorSoftcopyPresentationStateStorage)
        #expect(cspsPackage.prDataSet.string(for: .sopClassUID) == "1.2.840.10008.5.1.4.1.1.11.2")
        #expect(cspsPackage.prDataSet[.iccProfile] != nil)
        #expect(cspsPackage.prDataSet[.softcopyVOILUTSequence] == nil)
        #expect(cspsPackage.prDataSet[.presentationLUTShape] == nil)
    }

    // MARK: - 2. All 11 DICOMAnnotation Kinds & Compound Fallback Round-Trip

    @Test("All 11 DICOMAnnotation kinds encode with PS3.3 C.10.5.1.3.1 compound fallbacks and survive round-trip")
    func testAllAnnotationKindsRoundTrip() throws {
        let imgUID = "1.2.840.113619.2.55.3.200"
        let ctDataSet = makeMockImageDataSet(sopInstanceUID: imgUID, columns: 512, rows: 512)

        let annotations: [DICOMAnnotation] = [
            .text("Lesion A", at: .init(x: 100, y: 120), color: .yellow),
            .arrow(from: .init(x: 80, y: 80), to: .init(x: 150, y: 160), color: .red),
            .arrow(from: .init(x: 60, y: 60), to: .init(x: 120, y: 140), text: "Callout Note", color: .cyan),
            .ruler(from: .init(x: 200, y: 200), to: .init(x: 300, y: 200), distanceMM: 25.4, color: .green),
            .angle(
                start: .init(x: 100, y: 300),
                vertex: .init(x: 150, y: 350),
                end: .init(x: 220, y: 300),
                degrees: 95.0,
                color: .orange
            ),
            .rectangle(
                topLeft: .init(x: 50, y: 50),
                bottomRight: .init(x: 150, y: 120),
                filled: true,
                color: .magenta,
                measurements: [.areaMM2(420.0)]
            ),
            .ellipse(
                topLeft: .init(x: 220, y: 220),
                bottomRight: .init(x: 340, y: 300),
                filled: false,
                color: .green,
                measurements: [.meanHU(48.5), .standardDeviationHU(12.1)]
            ),
            .circle(
                center: .init(x: 400, y: 400),
                perimeterPoint: .init(x: 430, y: 400),
                filled: false,
                color: .cyan,
                measurements: [.areaMM2(180.0)]
            ),
            DICOMAnnotation(
                kind: .polyline,
                points: [.init(x: 10, y: 10), .init(x: 30, y: 20), .init(x: 40, y: 50)],
                color: .white
            ),
            DICOMAnnotation(
                kind: .crosshair,
                points: [.init(x: 256, y: 256)],
                color: .yellow
            ),
            DICOMAnnotation(
                kind: .point,
                points: [.init(x: 310, y: 410)],
                color: .red
            )
        ]

        let package = try PresentationStateManager.create(
            forImage: ctDataSet,
            configuration: PresentationStateConfiguration(
                presentationLabel: "ALL_SHAPES",
                annotations: annotations
            )
        )

        // Verify PS3.3 C.10.5.1.3.1 fallback rule: compound graphics (arrow, ruler, rectangle, crosshair)
        // must also emit fallback GraphicObject / TextObject items tied by CompoundGraphicInstanceID
        let graphicAnnotations = package.document.graphicAnnotations
        #expect(!graphicAnnotations.isEmpty)
        let firstGroup = graphicAnnotations[0]
        #expect(!firstGroup.compoundGraphics.isEmpty)
        for compound in firstGroup.compoundGraphics {
            #expect(compound.instanceID > 0)
            let linkedFallbackCount = firstGroup.graphicObjects.filter {
                $0.compoundGraphicInstanceID == compound.instanceID
            }.count + firstGroup.textObjects.filter {
                $0.compoundGraphicInstanceID == compound.instanceID
            }.count
            #expect(linkedFallbackCount > 0)
        }

        // Round-trip parse from serialized Part 10 DICOMFile bytes
        let fileData = try package.prFile.write()
        let parsedFile = try DICOMFile.read(from: fileData)
        let loaded = try PresentationStateManager.load(
            from: parsedFile.dataSet,
            imageWidth: 512,
            imageHeight: 512
        )

        let decodedKinds = Set(loaded.annotations.map(\.kind))
        #expect(decodedKinds.contains(.text))
        #expect(decodedKinds.contains(.arrow))
        #expect(decodedKinds.contains(.annotation))
        #expect(decodedKinds.contains(.ruler))
        #expect(decodedKinds.contains(.angle))
        #expect(decodedKinds.contains(.rectangle))
        #expect(decodedKinds.contains(.ellipse))
        #expect(decodedKinds.contains(.circle))
        #expect(decodedKinds.contains(.polyline))
        #expect(decodedKinds.contains(.crosshair))
        #expect(decodedKinds.contains(.point))
    }

    // MARK: - 3. Study / Series / Image / Frame Scoping (VOI LUT, Displayed Area, Annotations)

    @Test("Per-image and per-frame Softcopy VOI LUT, Displayed Area, and Graphic Annotations round-trip")
    func testStudySeriesImageFrameScoping() throws {
        let studyUID = "1.2.840.113619.2.55.3.500"
        let series1UID = "1.2.840.113619.2.55.3.501"
        let series2UID = "1.2.840.113619.2.55.3.502"
        let img1UID = "1.2.840.113619.2.55.3.511"
        let img2UID = "1.2.840.113619.2.55.3.512"

        let img1 = makeMockImageDataSet(
            studyInstanceUID: studyUID,
            seriesInstanceUID: series1UID,
            sopInstanceUID: img1UID
        )
        let img2 = makeMockImageDataSet(
            studyInstanceUID: studyUID,
            seriesInstanceUID: series2UID,
            sopInstanceUID: img2UID
        )

        let refImg1Frame1 = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: img1UID,
            referencedFrameNumbers: [1]
        )
        let refImg1Frame2 = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: img1UID,
            referencedFrameNumbers: [2]
        )
        let refImg2All = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: img2UID
        )

        let scopedVOIs: [ScopedVOILUT] = [
            ScopedVOILUT(
                voiLUT: .window(center: 40, width: 400, explanation: "Frame 1 Window", function: .linear),
                referencedImages: [refImg1Frame1]
            ),
            ScopedVOILUT(
                voiLUT: .window(center: -600, width: 1500, explanation: "Frame 2 Lung Window", function: .linear),
                referencedImages: [refImg1Frame2]
            ),
            ScopedVOILUT(
                voiLUT: .window(center: 300, width: 1500, explanation: "Series 2 Bone Window", function: .linear),
                referencedImages: [refImg2All]
            )
        ]

        let scopedAreas: [ScopedDisplayedArea] = [
            ScopedDisplayedArea(
                displayedArea: DisplayedArea(
                    topLeft: (column: 1, row: 1),
                    bottomRight: (column: 256, row: 256),
                    sizeMode: .magnify,
                    magnificationRatio: 2.0
                ),
                referencedImages: [refImg1Frame1]
            ),
            ScopedDisplayedArea(
                displayedArea: DisplayedArea(
                    topLeft: (column: 1, row: 1),
                    bottomRight: (column: 512, row: 512),
                    sizeMode: .scaleToFit
                )
            )
        ]

        let frame1Note = DICOMAnnotation.text(
            "Frame 1 Finding",
            at: .init(x: 100, y: 100),
            referencedSOPInstanceUID: img1UID,
            referencedFrameNumbers: [1]
        )
        let img2Note = DICOMAnnotation.text(
            "Series 2 Finding",
            at: .init(x: 200, y: 200),
            referencedSOPInstanceUID: img2UID
        )

        let package = try PresentationStateManager.create(
            forImages: [img1, img2],
            configuration: PresentationStateConfiguration(
                presentationLabel: "STUDY_SCOPED",
                annotations: [frame1Note, img2Note],
                scopedVOILUTs: scopedVOIs,
                scopedDisplayedAreas: scopedAreas
            )
        )

        let loaded = try PresentationStateManager.load(from: package.prDataSet)

        // Multi-series Study-level PR references both series
        #expect(loaded.referencedSeriesInstanceUIDs == [series1UID, series2UID])
        #expect(loaded.referencedImageSOPInstanceUIDs == [img1UID, img2UID])

        // Check per-frame VOI LUT resolution
        if case let .window(c1, w1, _, _) = loaded.document.effectiveVOILUT(forImage: img1UID, frameNumber: 1) {
            #expect(c1 == 40)
            #expect(w1 == 400)
        } else {
            Issue.record("Expected Frame 1 window")
        }

        if case let .window(c2, w2, _, _) = loaded.document.effectiveVOILUT(forImage: img1UID, frameNumber: 2) {
            #expect(c2 == -600)
            #expect(w2 == 1500)
        } else {
            Issue.record("Expected Frame 2 window")
        }

        if case let .window(cSeries2, _, _, _) = loaded.document.effectiveVOILUT(forImage: img2UID, frameNumber: 1) {
            #expect(cSeries2 == 300)
        } else {
            Issue.record("Expected Series 2 window")
        }

        // Check per-frame DisplayedArea resolution
        let areaFrame1 = loaded.document.effectiveDisplayedArea(forImage: img1UID, frameNumber: 1)
        #expect(areaFrame1?.bottomRight.column == 256)
        #expect(areaFrame1?.bottomRight.row == 256)
        let areaFrame2 = loaded.document.effectiveDisplayedArea(forImage: img1UID, frameNumber: 2)
        #expect(areaFrame2?.bottomRight.column == 512)
        #expect(areaFrame2?.bottomRight.row == 512)

        // Check per-image/per-frame annotation filtering
        let f1Annotations = loaded.annotations(forImage: img1UID, frameNumber: 1)
        #expect(f1Annotations.count == 1)
        #expect(f1Annotations.first?.text == "Frame 1 Finding")

        let f2Annotations = loaded.annotations(forImage: img1UID, frameNumber: 2)
        #expect(f2Annotations.isEmpty)

        let s2Annotations = loaded.annotations(forImage: img2UID, frameNumber: 1)
        #expect(s2Annotations.count == 1)
        #expect(s2Annotations.first?.text == "Series 2 Finding")
    }

    // MARK: - 4. SR Nested Presentation State Reference & Bidirectional PR <-> SR Bridge

    @Test("PresentationStateSRBridge round-trips TID 1500 Measurement Report and TID 2010 KOS with nested PR reference (PS3.3 C.18.4-1)")
    func testSRBridgeAndNestedPRReferenceRoundTrip() throws {
        let imgUID = "1.2.840.113619.2.55.3.700"
        let ctDataSet = makeMockImageDataSet(sopInstanceUID: imgUID)

        let ruler = DICOMAnnotation.ruler(
            from: .init(x: 100, y: 150),
            to: .init(x: 200, y: 150),
            distanceMM: 34.8,
            referencedSOPInstanceUID: imgUID,
            referencedFrameNumbers: [1]
        )
        let roi = DICOMAnnotation.ellipse(
            topLeft: .init(x: 220, y: 200),
            bottomRight: .init(x: 320, y: 280),
            measurements: [.areaMM2(612.5), .meanHU(55.2)],
            referencedSOPInstanceUID: imgUID,
            referencedFrameNumbers: [1]
        )

        let package = try PresentationStateManager.create(
            forImage: ctDataSet,
            frameNumbers: [1],
            configuration: PresentationStateConfiguration(
                presentationLabel: "PR_WITH_SR",
                annotations: [ruler, roi],
                voiLUT: .window(center: 50, width: 350, explanation: nil, function: .linear),
                palette: .pet,
                companionSROptions: .both
            )
        )

        // Verify Pseudo-CSPS was chosen and both companion SR documents were generated
        #expect(package.document.kind == PresentationStateKind.pseudoColor)
        let prSOPUID = package.document.sopInstanceUID
        let prSOPClass = package.document.sopClassUID
        #expect(prSOPClass == String.pseudoColorSoftcopyPresentationStateStorage)

        let srDataSet = try #require(package.measurementReportDataSet)
        let kosDataSet = try #require(package.keyObjectSelectionDataSet)

        // Parse back the TID 1500 Measurement Report SR from serialized DataSet
        let parsedSR = try SRDocumentParser().parse(dataSet: srDataSet)
        let extractedSR = PresentationStateSRBridge.extract(from: parsedSR)

        // Verify nested Softcopy Presentation State reference (0008,1199) inside IMAGE items survived serialization & parsing!
        let srHasPRRef = extractedSR.presentationStateReferences.contains { ref in
            ref.sopClassUID == prSOPClass && ref.sopInstanceUID == prSOPUID
        }
        #expect(srHasPRRef)
        #expect(extractedSR.annotations.count == 2)

        let allMeasuredValues = extractedSR.annotations.flatMap { $0.measurements.map(\.value) }
        let hasLength = allMeasuredValues.contains { abs($0 - 34.8) < 0.01 }
        let hasArea = allMeasuredValues.contains { abs($0 - 612.5) < 0.01 }
        let hasMean = allMeasuredValues.contains { abs($0 - 55.2) < 0.01 }
        #expect(hasLength)
        #expect(hasArea)
        #expect(hasMean)

        // Parse back the TID 2010 Key Object Selection Document from serialized DataSet
        let parsedKOS = try SRDocumentParser().parse(dataSet: kosDataSet)
        let extractedKOS = PresentationStateSRBridge.extract(from: parsedKOS)
        let kosHasPRRef = extractedKOS.presentationStateReferences.contains { ref in
            ref.sopClassUID == prSOPClass && ref.sopInstanceUID == prSOPUID
        }
        #expect(kosHasPRRef)

        let kosHasImgWithPR = extractedKOS.imageReferences.contains { imgRef in
            imgRef.sopReference.sopInstanceUID == imgUID &&
            imgRef.presentationStateReference?.sopInstanceUID == prSOPUID
        }
        #expect(kosHasImgWithPR)
    }

    // MARK: - 5. Disk Persistence & Directory Discovery

    @Test("PresentationStateManager saves and discovers PR, SR, and KOS files on disk")
    func testSaveAndDiscoverOnDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOMKit_PR_Test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imgUID = "1.2.840.113619.2.55.3.900"
        let imgDataSet = makeMockImageDataSet(sopInstanceUID: imgUID)
        let arrow = DICOMAnnotation.arrow(
            from: .init(x: 50, y: 50),
            to: .init(x: 120, y: 130),
            text: "Target Nodule",
            referencedSOPInstanceUID: imgUID
        )

        let package = try PresentationStateManager.create(
            forImage: imgDataSet,
            configuration: PresentationStateConfiguration(
                presentationLabel: "DISK_TEST",
                annotations: [arrow],
                companionSROptions: .both
            )
        )

        let savedFiles = try PresentationStateManager.save(package, to: tempDir)
        #expect(FileManager.default.fileExists(atPath: savedFiles.presentationStateURL.path))
        #expect(savedFiles.measurementReportURL != nil)
        #expect(savedFiles.keyObjectSelectionURL != nil)

        let discovered = try PresentationStateManager.discover(in: tempDir)
        #expect(discovered.presentationStates.count == 1)
        #expect(discovered.srAnnotationSets.count == 2)

        let matchedStates = discovered.presentationStates(sopInstanceUID: imgUID)
        #expect(matchedStates.count == 1)
        #expect(matchedStates.first?.annotations.first?.kind == .annotation)
        #expect(matchedStates.first?.annotations.first?.text == "Target Nodule")
    }

    // MARK: - 6. Viewport Bridge & Blending Softcopy Presentation State

    @Test("PresentationStateViewportBridge captures and restores GSPS, CSPS, and Pseudo-CSPS viewport state")
    func testViewportBridgeCaptureAndRestore() throws {
        let imgUID = "1.2.840.113619.2.55.3.1001"
        let seriesUID = "1.2.840.113619.2.55.2.1001"
        let note = DICOMAnnotation.text(
            "Viewport Note",
            at: .init(x: 128, y: 128),
            referencedSOPInstanceUID: imgUID
        )
        let viewport = PresentationStateViewportState(
            windowCenter: 60,
            windowWidth: 360,
            rescaleSlope: 1.0,
            rescaleIntercept: -1024.0,
            rescaleType: "HU",
            zoom: 2.0,
            panX: 0.0,
            panY: 0.0,
            rotationDegrees: 90,
            flipHorizontal: false,
            flipVertical: true,
            invert: true,
            palette: .hotIron,
            annotations: [note]
        )

        let doc = PresentationStateViewportBridge.capture(
            viewport: viewport,
            seriesInstanceUID: seriesUID,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: imgUID,
            photometricInterpretation: "MONOCHROME2",
            imageWidth: 512,
            imageHeight: 512,
            presentationLabel: "VIEWPORT_TEST"
        )
        #expect(doc.kind == .pseudoColor)

        let restored = PresentationStateViewportBridge.restore(
            doc,
            forImage: imgUID,
            imageWidth: 512,
            imageHeight: 512,
            photometricInterpretation: "MONOCHROME2"
        )
        #expect(restored.windowCenter == 60)
        #expect(restored.windowWidth == 360)
        #expect(restored.rescaleIntercept == -1024.0)
        #expect(restored.palette == .hotIron)
        // 90° + vertical flip encodes as 270° + horizontal flip per PS3.3 C.10.6
        #expect(restored.rotationDegrees == 270)
        #expect(restored.flipHorizontal == true)
        #expect(abs(restored.zoom - 2.0) < 0.05)
        #expect(restored.annotations.count == 1)
    }

    @Test("BlendingPresentationStateBuilder, Parser, and Applicator round-trip Blending Softcopy Presentation State (PS3.3 A.33.4)")
    func testBlendingPresentationStateRoundTripAndRendering() throws {
        let studyUID = "1.2.840.113619.2.55.1.2000"
        let ctSeriesUID = "1.2.840.113619.2.55.2.2001"
        let petSeriesUID = "1.2.840.113619.2.55.2.2002"
        let ctImgUID = "1.2.840.113619.2.55.3.2001"
        let petImgUID = "1.2.840.113619.2.55.3.2002"

        let ctImg = makeMockImageDataSet(
            studyInstanceUID: studyUID,
            seriesInstanceUID: ctSeriesUID,
            sopInstanceUID: ctImgUID,
            columns: 16,
            rows: 16
        )
        let petImg = makeMockImageDataSet(
            studyInstanceUID: studyUID,
            seriesInstanceUID: petSeriesUID,
            sopInstanceUID: petImgUID,
            columns: 16,
            rows: 16
        )

        let package = try PresentationStateManager.create(
            forImages: [ctImg, petImg],
            configuration: PresentationStateConfiguration(
                preferredKind: .blending,
                presentationLabel: "PET_CT_FUSION",
                voiLUT: .window(center: 128, width: 256, explanation: nil, function: .linear),
                palette: .hotIron
            )
        )

        #expect(package.document.kind == PresentationStateKind.blending)
        #expect(package.document.sopClassUID == String.blendingSoftcopyPresentationStateStorage)

        let parsedDoc = try PresentationStateParser().parse(dataSet: package.prDataSet)
        guard case .blending(let parsedBlending) = parsedDoc else {
            Issue.record("Expected .blending document")
            return
        }
        #expect(parsedBlending.underlaySeries.first?.seriesInstanceUID == ctSeriesUID)
        #expect(parsedBlending.overlaySeries.first?.seriesInstanceUID == petSeriesUID)
        #expect(abs(parsedBlending.relativeOpacity - 0.5) < 0.001)
        #expect(parsedBlending.palette == PseudoColorPalette.hotIron)

        #if canImport(CoreGraphics)
        let desc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let uPixel = PixelData(data: Data(repeating: 100, count: 16 * 16), descriptor: desc)
        let oPixel = PixelData(data: Data(repeating: 200, count: 16 * 16), descriptor: desc)
        let cgImage = PresentationStateApplicator.apply(
            parsedBlending,
            underlayPixelData: uPixel,
            overlayPixelData: oPixel
        )
        #expect(cgImage != nil)
        #expect(cgImage?.width == 16)
        #expect(cgImage?.height == 16)
        #endif
    }
}
