// WindowLevelPresetsTests.swift
// DICOMStudioTests
//
// Tests for WindowLevelPresets

import Testing
@testable import DICOMStudio
import Foundation

@Suite("WindowLevelPreset Tests")
struct WindowLevelPresetTests {

    @Test("Preset has correct properties")
    func testPresetProperties() {
        let preset = WindowLevelPreset(name: "Bone", center: 300, width: 1500, modality: "CT")
        #expect(preset.name == "Bone")
        #expect(preset.center == 300)
        #expect(preset.width == 1500)
        #expect(preset.modality == "CT")
    }

    @Test("Preset id carries the modality — names repeat across modalities")
    func testPresetId() {
        let preset = WindowLevelPreset(name: "Brain", center: 40, width: 80, modality: "CT")
        #expect(preset.id == "CT/Brain")
    }

    /// "Bone" is a CT, CR and DX preset; "Standard" belongs to three
    /// modalities. A menu spanning all presets feeds these ids to `ForEach`,
    /// and duplicate identities wire rows to the wrong actions.
    @Test("Every preset in the all-modalities list has a distinct id")
    func testAllPresetIdsAreUnique() {
        let ids = WindowLevelPresets.allPresets.map(\.id)
        #expect(Set(ids).count == ids.count,
                "duplicate ids: \(Dictionary(grouping: ids) { $0 }.filter { $1.count > 1 }.keys)")
    }

    @Test("Presets are equatable")
    func testPresetEquality() {
        let a = WindowLevelPreset(name: "Bone", center: 300, width: 1500, modality: "CT")
        let b = WindowLevelPreset(name: "Bone", center: 300, width: 1500, modality: "CT")
        #expect(a == b)
    }

    @Test("Presets are hashable")
    func testPresetHashable() {
        let preset = WindowLevelPreset(name: "Lung", center: -600, width: 1500, modality: "CT")
        var set: Set<WindowLevelPreset> = []
        set.insert(preset)
        #expect(set.contains(preset))
    }
}

@Suite("WindowLevelPresets Tests")
struct WindowLevelPresetsTests {

    // MARK: - CT Presets

    @Test("CT presets include 8 entries")
    func testCTPresetsCount() {
        #expect(WindowLevelPresets.ctPresets.count == 8)
    }

    @Test("CT Abdomen preset values")
    func testCTAbdomen() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Abdomen" }
        #expect(preset != nil)
        #expect(preset?.center == 40)
        #expect(preset?.width == 400)
    }

    @Test("CT Bone preset values")
    func testCTBone() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Bone" }
        #expect(preset != nil)
        #expect(preset?.center == 300)
        #expect(preset?.width == 1500)
    }

    @Test("CT Brain preset values")
    func testCTBrain() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Brain" }
        #expect(preset != nil)
        #expect(preset?.center == 40)
        #expect(preset?.width == 80)
    }

    @Test("CT Lung preset values")
    func testCTLung() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Lung" }
        #expect(preset != nil)
        #expect(preset?.center == -600)
        #expect(preset?.width == 1500)
    }

    @Test("CT Liver preset values")
    func testCTLiver() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Liver" }
        #expect(preset != nil)
        #expect(preset?.center == 60)
        #expect(preset?.width == 150)
    }

    @Test("CT Mediastinum preset values")
    func testCTMediastinum() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Mediastinum" }
        #expect(preset != nil)
        #expect(preset?.center == 50)
        #expect(preset?.width == 350)
    }

    @Test("CT Stroke preset values")
    func testCTStroke() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Stroke" }
        #expect(preset != nil)
        #expect(preset?.center == 40)
        #expect(preset?.width == 40)
    }

    @Test("CT Chest preset values")
    func testCTChest() {
        let preset = WindowLevelPresets.ctPresets.first { $0.name == "Chest" }
        #expect(preset != nil)
        #expect(preset?.center == 40)
        #expect(preset?.width == 400)
    }

    // MARK: - MR Presets

    @Test("MR presets include 3 entries")
    func testMRPresetsCount() {
        #expect(WindowLevelPresets.mrPresets.count == 3)
    }

    @Test("MR T1 preset values")
    func testMRT1() {
        let preset = WindowLevelPresets.mrPresets.first { $0.name == "T1" }
        #expect(preset != nil)
        #expect(preset?.center == 500)
        #expect(preset?.width == 1000)
    }

    @Test("MR T2 preset values")
    func testMRT2() {
        let preset = WindowLevelPresets.mrPresets.first { $0.name == "T2" }
        #expect(preset != nil)
        #expect(preset?.center == 400)
        #expect(preset?.width == 800)
    }

    @Test("MR FLAIR preset values")
    func testMRFLAIR() {
        let preset = WindowLevelPresets.mrPresets.first { $0.name == "FLAIR" }
        #expect(preset != nil)
        #expect(preset?.center == 600)
        #expect(preset?.width == 1200)
    }

    // MARK: - presets(for:)

    @Test("Presets for CT returns CT presets")
    func testPresetsForCT() {
        let presets = WindowLevelPresets.presets(for: "CT")
        #expect(presets.count == 8)
        #expect(presets.allSatisfy { $0.modality == "CT" })
    }

    @Test("Presets for MR returns MR presets")
    func testPresetsForMR() {
        let presets = WindowLevelPresets.presets(for: "MR")
        #expect(presets.count == 3)
        #expect(presets.allSatisfy { $0.modality == "MR" })
    }

    @Test("Presets for MRI alias returns MR presets")
    func testPresetsForMRI() {
        let presets = WindowLevelPresets.presets(for: "MRI")
        #expect(presets.count == 3)
    }

    @Test("Presets for unknown modality returns empty")
    func testPresetsForUnknown() {
        #expect(WindowLevelPresets.presets(for: "US").isEmpty)
        #expect(WindowLevelPresets.presets(for: "UNKNOWN").isEmpty)
    }

    @Test("Case insensitive modality lookup")
    func testCaseInsensitive() {
        let ct = WindowLevelPresets.presets(for: "ct")
        #expect(ct.count == 8)
        let mr = WindowLevelPresets.presets(for: "mr")
        #expect(mr.count == 3)
    }

    // MARK: - allPresets

    @Test("All presets includes every modality's list")
    func testAllPresets() {
        let all = WindowLevelPresets.allPresets
        // 8 CT + 3 MR + 3 CR + 3 DX + 2 MG + 2 PT + 2 NM + 2 XA (FR-004), plus
        // the modalities added with the 2026a defined-term adoption:
        // 3 RG + 2 PX + 2 IO + 1 BMD + 2 IVUS + 2 OPT.
        #expect(all.count == 37)
        #expect(all.contains { $0.modality == "CT" })
        #expect(all.contains { $0.modality == "MR" })
        #expect(all.contains { $0.modality == "CR" })
        #expect(all.contains { $0.modality == "PT" })
    }

    // MARK: - preset(named:modality:)

    @Test("Find preset by name and modality")
    func testPresetNamed() {
        let preset = WindowLevelPresets.preset(named: "Bone", modality: "CT")
        #expect(preset != nil)
        #expect(preset?.center == 300)
    }

    @Test("Find preset case insensitive name")
    func testPresetNamedCaseInsensitive() {
        let preset = WindowLevelPresets.preset(named: "bone", modality: "CT")
        #expect(preset != nil)
    }

    @Test("Find preset returns nil for wrong modality")
    func testPresetNamedWrongModality() {
        let preset = WindowLevelPresets.preset(named: "Bone", modality: "MR")
        #expect(preset == nil)
    }

    @Test("Find preset returns nil for unknown name")
    func testPresetNamedUnknown() {
        let preset = WindowLevelPresets.preset(named: "Unknown", modality: "CT")
        #expect(preset == nil)
    }

    // MARK: - defaultPreset(for:)

    @Test("Default CT preset is Abdomen")
    func testDefaultCTPreset() {
        let preset = WindowLevelPresets.defaultPreset(for: "CT")
        #expect(preset?.name == "Abdomen")
    }

    @Test("Default MR preset is T1")
    func testDefaultMRPreset() {
        let preset = WindowLevelPresets.defaultPreset(for: "MR")
        #expect(preset?.name == "T1")
    }

    @Test("Default for unknown modality is nil")
    func testDefaultUnknownPreset() {
        let preset = WindowLevelPresets.defaultPreset(for: "US")
        #expect(preset == nil)
    }

    // MARK: - All presets have positive widths

    @Test("All presets have positive widths")
    func testAllPresetsPositiveWidth() {
        for preset in WindowLevelPresets.allPresets {
            #expect(preset.width > 0, "Preset \(preset.name) has non-positive width")
        }
    }
}
