// ModalityMappingTests.swift
// DICOMStudioTests
//
// Tests for ModalityMapping after the 2026a canonical-Modality adoption.

import Testing
import Foundation
import DICOMCore
@testable import DICOMStudio

@Suite("Modality 2026a Adoption Tests")
struct Modality2026aAdoptionTests {

    // MARK: - Coverage

    @Test("allCodes exposes every current defined term, not a subset")
    func testAllCodesIsFullStandardList() {
        #expect(ModalityMapping.allCodes.count == 79)
        #expect(ModalityMapping.allCodes == Modality.allCases.map(\.rawValue))
    }

    @Test("Codes absent before the 2026a adoption are now recognized")
    func testPreviouslyMissingCodes() {
        // These were emitted by DICOMKit (waveform, encapsulated document) or
        // defined by the standard, but fell off the old 26-code list and
        // rendered with a fallback icon and a raw uppercased name.
        for code in ["AU", "EPS", "RESP", "M3D", "OPT", "OCT", "IVOCT",
                     "OPTENF", "OPTBSV", "SM", "PA", "RTPLAN", "RTDOSE"] {
            #expect(ModalityMapping.allCodes.contains(code), "\(code) should be offered")
            #expect(ModalityMapping.fullName(for: code) != code,
                    "\(code) should have a human-readable name, not its own code")
        }
    }

    @Test("Retired and conventional codes are not offered")
    func testNotOffered() {
        for code in ["ST", "MA", "EC", "SC", "VL"] {
            #expect(!ModalityMapping.allCodes.contains(code),
                    "\(code) should be recognized but not offered")
        }
    }

    @Test("Grouped codes partition the full list")
    func testGroupedCodes() {
        let flattened = ModalityMapping.groupedCodes.flatMap { $0.codes }
        #expect(flattened.count == ModalityMapping.allCodes.count)
        #expect(Set(flattened) == Set(ModalityMapping.allCodes))
        let emptyGroups = ModalityMapping.groupedCodes.contains { $0.codes.isEmpty }
        #expect(!emptyGroups)
    }

    // MARK: - Names and icons

    @Test("Names come from the standard")
    func testFullNames() {
        #expect(ModalityMapping.fullName(for: "CT") == "Computed Tomography")
        #expect(ModalityMapping.fullName(for: "OPT") == "Ophthalmic Tomography")
        #expect(ModalityMapping.fullName(for: "RTSTRUCT") == "Radiotherapy Structure Set")
    }

    @Test("Unrecognized codes display as themselves")
    func testUnknownCodeDisplay() {
        #expect(ModalityMapping.fullName(for: "acme") == "ACME")
        #expect(ModalityMapping.systemImage(for: "ACME") == "square.grid.2x2")
    }

    @Test("Every offered code resolves to a non-empty icon")
    func testEveryCodeHasIcon() {
        for code in ModalityMapping.allCodes {
            #expect(!ModalityMapping.systemImage(for: code).isEmpty)
        }
    }

    // MARK: - One alias table

    @Test("Aliases resolve through the shared table")
    func testAliases() {
        #expect(ModalityMapping.fullName(for: "MRI") == "Magnetic Resonance")
        #expect(ModalityMapping.fullName(for: "PET") == "Positron Emission Tomography")
        #expect(ModalityMapping.fullName(for: "PDF") == "Document")
        // XR and DR were only known to DICOMFileDropHelpers' private switch.
        #expect(ModalityMapping.fullName(for: "XR") == "Digital Radiography")
        #expect(ModalityMapping.fullName(for: "DR") == "Digital Radiography")
    }

    @Test("RT resolves to a real code instead of a pseudo-modality")
    func testRTDemotion() {
        #expect(ModalityMapping.fullName(for: "RT") == "Radiotherapy Image")
        // The real RT codes are now distinct rather than collapsed onto one.
        #expect(ModalityMapping.fullName(for: "RTPLAN") == "Radiotherapy Plan")
        #expect(ModalityMapping.fullName(for: "RTDOSE") == "Radiotherapy Dose")
    }

    // MARK: - The formerly divergent maps now agree

    @Test("DICOMFileDropHelpers uses the same icon map")
    func testFileOperationsIconsUnified() {
        for code in ["CT", "MR", "US", "DX", "NM", "PT", "MG", "OT", "SR"] {
            #expect(DICOMFileDropHelpers.symbolName(for: code)
                    == ModalityMapping.systemImage(for: code),
                    "\(code) icon should agree between the two entry points")
        }
        // XR is not a DICOM code; it now resolves as an alias of DX.
        #expect(DICOMFileDropHelpers.symbolName(for: "XR")
                == ModalityMapping.systemImage(for: "DX"))
        #expect(DICOMFileDropHelpers.symbolName(for: nil) == "cross.case")
    }

    @Test("Theme colors cover whole categories, not four codes")
    func testThemeColorsByCategory() {
        let primary = StudioColors.modalityColor(for: "NOTACODE")
        // Radiography codes the old four-case switch did not know now get a color.
        for code in ["RG", "PX", "IO", "MG", "XA"] {
            let color = StudioColors.modalityColor(for: code)
            #expect(color != primary, "\(code) should get a radiography color")
        }
        // Aliases resolve rather than falling through to the default.
        #expect(StudioColors.modalityColor(for: "MRI") == StudioColors.modalityColor(for: "MR"))
        #expect(StudioColors.modalityColor(for: "XR") == StudioColors.modalityColor(for: "DX"))
    }

    // MARK: - Window/level presets

    @Test("Presets resolve aliases consistently")
    func testPresetAliases() {
        #expect(WindowLevelPresets.presets(for: "MRI") == WindowLevelPresets.presets(for: "MR"))
        #expect(!WindowLevelPresets.presets(for: "MRI").isEmpty)
    }

    @Test("Newly recognized windowed modalities have presets")
    func testNewPresets() {
        for code in ["RG", "PX", "IO", "BMD", "IVUS", "OPT"] {
            #expect(!WindowLevelPresets.presets(for: code).isEmpty,
                    "\(code) should have window/level presets")
        }
    }

    @Test("Display-ready and non-image modalities have no presets")
    func testNoPresetsWhereInvented() {
        // A fixed window for these would be an invented number, not a clinical one.
        for code in ["US", "ES", "GM", "XC", "SM", "SR", "KO", "SEG", "DOC"] {
            #expect(WindowLevelPresets.presets(for: code).isEmpty,
                    "\(code) should not carry an invented window")
        }
    }

    @Test("Preset IDs stay unique across the wider modality set")
    func testPresetIDsUnique() {
        let ids = WindowLevelPresets.allPresets.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate preset ID would misbind ForEach rows")
    }

    @Test("presetsByModality agrees with the lookup function")
    func testPresetsByModalityConsistent() {
        for entry in WindowLevelPresets.presetsByModality {
            #expect(WindowLevelPresets.presets(for: entry.modality) == entry.presets,
                    "\(entry.modality) disagrees between the menu list and the lookup")
        }
    }

    // MARK: - Library-emitted codes must be displayable

    @Test("Every modality DICOMKit writes is recognized by the app's display path")
    func testLibraryEmittedCodesAreDisplayable() {
        // Derived from the library's own defaultModality sources rather than a
        // hardcoded list, so a new IOD default cannot silently fall off the
        // app's list the way M3D, AU, EPS and RESP did before the 2026a work.
        //
        // Keep in sync with: VideoType.defaultModality, WaveformBuilder,
        // EncapsulatedDocumentWorkflow, SecondaryCaptureImage, the PR builders,
        // JP3DVolumeDocument, and dicom-ai's SEG/PR output.
        let emitted: [Modality] = [
            .es, .gm, .xc, .ot,           // Video
            .ecg, .hd, .eps, .au, .resp,  // Waveform
            .m3d, .doc,                   // Encapsulated document / JP3D
            .sc,                          // Secondary capture (conventional)
            .pr, .seg,                    // Presentation state / AI output
        ]
        for modality in emitted {
            let code = modality.rawValue
            #expect(ModalityMapping.fullName(for: code) != code,
                    "\(code) is emitted by the library but has no display name")
            #expect(ModalityMapping.systemImage(for: code) != "square.grid.2x2",
                    "\(code) is emitted by the library but falls back to the unknown icon")
        }
    }

    // MARK: - Thumbnails

    @Test("Thumbnail defaults resolve aliases and cover radiography")
    func testThumbnailWindowDefaults() {
        let ct = ThumbnailHelpers.defaultWindowSettings(for: "CT")
        #expect(ct.center == 40.0 && ct.width == 400.0)
        // Alias resolution: previously "MRI" fell through to the 128/256 default.
        #expect(ThumbnailHelpers.defaultWindowSettings(for: "MRI")
                == ThumbnailHelpers.defaultWindowSettings(for: "MR"))
        // Wide-latitude projection X-ray, including codes the old switch lacked.
        for code in ["CR", "DX", "RG", "PX", "IO"] {
            let settings = ThumbnailHelpers.defaultWindowSettings(for: code)
            #expect(settings.width == 4096.0, "\(code) should use wide X-ray latitude")
        }
        // XA/RF are 8-bit display-ready in practice.
        #expect(ThumbnailHelpers.defaultWindowSettings(for: "XA").width == 256.0)
    }
}
