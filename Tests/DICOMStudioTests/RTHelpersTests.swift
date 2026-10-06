// RTHelpersTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("RT Helpers Tests")
struct RTHelpersTests {

    // MARK: - colorForROIType

    @Test("colorForROIType returns red for PTV")
    func testColorForPTV() {
        let color = RTHelpers.colorForROIType(.ptv)
        #expect(color == .red)
    }

    @Test("colorForROIType returns yellow for OAR")
    func testColorForOAR() {
        let color = RTHelpers.colorForROIType(.oar)
        #expect(color == .yellow)
    }

    @Test("colorForROIType returns green for GTV")
    func testColorForGTV() {
        let color = RTHelpers.colorForROIType(.gtv)
        #expect(color == .green)
    }

    @Test("colorForROIType returns blue for CTV")
    func testColorForCTV() {
        let color = RTHelpers.colorForROIType(.ctv)
        #expect(color == .blue)
    }

    @Test("colorForROIType returns distinct colors for each type")
    func testColorDistinctForAllTypes() {
        let colors = RTROIType.allCases.map { RTHelpers.colorForROIType($0) }
        let unique = Set(colors)
        #expect(unique.count == RTROIType.allCases.count)
    }

    // MARK: - sfSymbolForROIType

    @Test("sfSymbolForROIType returns non-empty string for all types")
    func testSFSymbolNonEmptyForAllTypes() {
        for roiType in RTROIType.allCases {
            let symbol = RTHelpers.sfSymbolForROIType(roiType)
            #expect(!symbol.isEmpty)
        }
    }

    // MARK: - isodoseLevels

    @Test("isodoseLevels generates exactly 7 levels")
    func testIsodoseLevelsCount() {
        let levels = RTHelpers.isodoseLevels(for: 60.0)
        #expect(levels.count == 7)
    }

    @Test("isodoseLevels are sorted by ascending percentage")
    func testIsodoseLevelsSorted() {
        let levels = RTHelpers.isodoseLevels(for: 60.0)
        let percentages = levels.map(\.percentage)
        #expect(percentages == percentages.sorted())
    }

    @Test("isodoseLevels first level is 30%")
    func testIsodoseLevelsFirstLevel() {
        let levels = RTHelpers.isodoseLevels(for: 60.0)
        #expect(levels.first?.percentage == 30.0)
    }

    @Test("isodoseLevels last level is 100%")
    func testIsodoseLevelsLastLevel() {
        let levels = RTHelpers.isodoseLevels(for: 60.0)
        #expect(levels.last?.percentage == 100.0)
    }

    // MARK: - doseColorWash

    @Test("doseColorWash returns blue at zero dose")
    func testDoseColorWashZero() {
        let color = RTHelpers.doseColorWash(dose: 0, maxDose: 60.0)
        #expect(color == .blue)
    }

    @Test("doseColorWash returns red at max dose")
    func testDoseColorWashMax() {
        let color = RTHelpers.doseColorWash(dose: 60.0, maxDose: 60.0)
        #expect(color == .red)
    }

    @Test("doseColorWash clamps dose above max")
    func testDoseColorWashClampAbove() {
        let color = RTHelpers.doseColorWash(dose: 100.0, maxDose: 60.0)
        #expect(color == .red)
    }

    // MARK: - formattedDose

    @Test("formattedDose includes Gy unit")
    func testFormattedDoseGy() {
        let s = RTHelpers.formattedDose(60.0, units: .gy)
        #expect(s.contains("Gy"))
        #expect(s.contains("60"))
    }

    @Test("formattedDose(gray:scale:) shows a GY dose in cGy")
    func testFormattedDoseCGy() {
        #expect(RTHelpers.formattedDose(gray: 60.0, scale: .centigray) == "6000.00 cGy")
        #expect(RTHelpers.formattedDose(gray: 60.0, scale: .gray) == "60.00 Gy")
    }

    @Test("formattedDose marks RELATIVE and CODED doses")
    func testFormattedDoseRelativeCoded() {
        #expect(RTHelpers.formattedDose(0.95, units: .relative) == "0.95 (relative)")
        #expect(RTHelpers.formattedDose(1.0, units: .coded) == "1.00 (coded)")
    }

    // MARK: - dvhVolumeAtDose

    @Test("dvhVolumeAtDose returns nil for empty curve")
    func testDVHVolumeAtDoseEmptyCurve() {
        let curve = DVHCurve(roiName: "Test", structureColor: .red, points: [])
        let vol = RTHelpers.dvhVolumeAtDose(30.0, curve: curve)
        #expect(vol == nil)
    }

    @Test("dvhVolumeAtDose interpolates between points")
    func testDVHVolumeAtDoseInterpolation() {
        let points = [DVHPoint(dose: 0, volume: 100), DVHPoint(dose: 60, volume: 0)]
        let curve = DVHCurve(roiName: "PTV", structureColor: .red, points: points)
        let vol = RTHelpers.dvhVolumeAtDose(30.0, curve: curve)
        if let v = vol {
            #expect(abs(v - 50.0) < 0.1)
        } else {
            Issue.record("Expected interpolated volume")
        }
    }

    // MARK: - beamDisplayAngle

    @Test("beamDisplayAngle contains degree symbol")
    func testBeamDisplayAngleSymbol() {
        let s = RTHelpers.beamDisplayAngle(45.0)
        #expect(s.contains("°"))
    }

    @Test("beamDisplayAngle formats whole number without decimal")
    func testBeamDisplayAngleWholeNumber() {
        let s = RTHelpers.beamDisplayAngle(180.0)
        #expect(s == "180°")
    }

    // MARK: - totalPlanDose

    @Test("totalPlanDose sums across all fraction groups")
    func testTotalPlanDose() {
        let groups: [RTFractionGroup] = [
            RTFractionGroup(fractionGroupID: 1, numberOfFractions: 25,
                            beamDoses: [(beamID: 1, dose: 2.0), (beamID: 2, dose: 1.5)]),
            RTFractionGroup(fractionGroupID: 2, numberOfFractions: 5,
                            beamDoses: [(beamID: 3, dose: 0.5)]),
        ]
        let total = RTHelpers.totalPlanDose(fractionGroups: groups)
        #expect(abs(total - 4.0) < 0.001)
    }

    @Test("totalPlanDose returns zero for empty list")
    func testTotalPlanDoseEmpty() {
        #expect(RTHelpers.totalPlanDose(fractionGroups: []) == 0.0)
    }
}
