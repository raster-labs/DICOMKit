//
// PrintGSDFTests.swift
// DICOMPrintKit
//
// The calibrated rendering (DensityMapping.gsdf, P-GSDF) held against PS3.14
// 2026a: the GSDF's own Table B-1 end points, and Table D.2-1 — the optical
// density a conforming 8-bit transmissive printer lays down for every P-Value
// at L0 = 2000 cd/m², La = 10 cd/m², Dmin 0.20, Dmax 3.00 (Annex D.2). The
// array below is Table D.2-1 as  reads it from the
// DocBook, and the script checks it still is.
//

import XCTest
import DICOMNetwork
@testable import DICOMPrintKit

final class PrintGSDFTests: XCTestCase {

    /// PS3.14 2026a Table D.2-1, P-Value 0 … 255.
    static let tableD21: [Double] = [
        3.000, 2.936, 2.880, 2.828, 2.782, 2.739, 2.700, 2.662, 2.628, 2.595, 2.564, 2.534,
        2.506, 2.479, 2.454, 2.429, 2.405, 2.382, 2.360, 2.338, 2.317, 2.297, 2.277, 2.258,
        2.239, 2.221, 2.203, 2.185, 2.168, 2.152, 2.135, 2.119, 2.103, 2.088, 2.073, 2.058,
        2.043, 2.028, 2.014, 2.000, 1.986, 1.973, 1.959, 1.946, 1.933, 1.920, 1.907, 1.894,
        1.882, 1.870, 1.857, 1.845, 1.833, 1.821, 1.810, 1.798, 1.787, 1.775, 1.764, 1.753,
        1.742, 1.731, 1.720, 1.709, 1.698, 1.688, 1.677, 1.667, 1.656, 1.646, 1.636, 1.626,
        1.616, 1.605, 1.595, 1.586, 1.576, 1.566, 1.556, 1.547, 1.537, 1.527, 1.518, 1.508,
        1.499, 1.490, 1.480, 1.471, 1.462, 1.453, 1.444, 1.434, 1.425, 1.416, 1.407, 1.398,
        1.390, 1.381, 1.372, 1.363, 1.354, 1.346, 1.337, 1.328, 1.320, 1.311, 1.303, 1.294,
        1.286, 1.277, 1.269, 1.260, 1.252, 1.244, 1.235, 1.227, 1.219, 1.211, 1.202, 1.194,
        1.186, 1.178, 1.170, 1.162, 1.154, 1.146, 1.138, 1.130, 1.122, 1.114, 1.106, 1.098,
        1.090, 1.082, 1.074, 1.066, 1.058, 1.051, 1.043, 1.035, 1.027, 1.020, 1.012, 1.004,
        0.996, 0.989, 0.981, 0.973, 0.966, 0.958, 0.951, 0.943, 0.935, 0.928, 0.920, 0.913,
        0.905, 0.898, 0.890, 0.883, 0.875, 0.868, 0.860, 0.853, 0.845, 0.838, 0.831, 0.823,
        0.816, 0.808, 0.801, 0.794, 0.786, 0.779, 0.772, 0.764, 0.757, 0.750, 0.742, 0.735,
        0.728, 0.721, 0.713, 0.706, 0.699, 0.692, 0.684, 0.677, 0.670, 0.663, 0.656, 0.648,
        0.641, 0.634, 0.627, 0.620, 0.613, 0.606, 0.598, 0.591, 0.584, 0.577, 0.570, 0.563,
        0.556, 0.549, 0.542, 0.534, 0.527, 0.520, 0.513, 0.506, 0.499, 0.492, 0.485, 0.478,
        0.471, 0.464, 0.457, 0.450, 0.443, 0.436, 0.429, 0.422, 0.415, 0.408, 0.401, 0.394,
        0.387, 0.380, 0.373, 0.366, 0.359, 0.352, 0.345, 0.338, 0.331, 0.324, 0.317, 0.311,
        0.304, 0.297, 0.290, 0.283, 0.276, 0.269, 0.262, 0.255, 0.248, 0.241, 0.234, 0.228,
        0.221, 0.214, 0.207, 0.200
    ]

    /// Table B-1: j = 1 → 0.0500 cd/m², j = 1023 → 3993.4040 cd/m².
    func test_gsdfEndPointsMatchTableB1() {
        XCTAssertEqual(GrayscaleStandardDisplayFunction.gsdfLuminance(jndIndex: 1), 0.0500, accuracy: 0.0001)
        XCTAssertEqual(GrayscaleStandardDisplayFunction.gsdfLuminance(jndIndex: 1023), 3993.404, accuracy: 0.5)
    }

    /// Annex D.2's worked range: Lmin 12.0 cd/m², Lmax 1271.9 cd/m², j_min 233.32.
    func test_transmissiveRangeMatchesAnnexD2() {
        let viewing = HardcopyViewing.transmissive(minDensity: 0.2, maxDensity: 3.0)
        XCTAssertEqual(viewing.luminanceRange.min, 12.0, accuracy: 0.05)
        XCTAssertEqual(viewing.luminanceRange.max, 1271.9, accuracy: 0.05)
        XCTAssertEqual(GrayscaleStandardDisplayFunction.jndIndex(luminance: 12.0), 233.32, accuracy: 0.05)
    }

    /// Every P-Value's density within 0.0015 OD of Table D.2-1 (printed to
    /// three decimals). D.2's prose quotes j_max 848.75, which would put P-Value
    /// 255 at 0.196 OD; the table's 0.200 is what j(Lmax) gives, and is what
    /// is matched.
    func test_densitiesReproduceTableD21() {
        let viewing = HardcopyViewing.transmissive(minDensity: 0.2, maxDensity: 3.0)
        XCTAssertEqual(Self.tableD21.count, 256)
        for (p, expected) in Self.tableD21.enumerated() {
            XCTAssertEqual(viewing.density(pValue: Double(p)), expected, accuracy: 0.0015, "P-Value \(p)")
        }
    }

    /// PS3.14 7.3: a reflective print has no ambient term, L = L0·10^−D.
    func test_reflectivePrintHasNoAmbientTerm() {
        let paper = HardcopyViewing.reflective(minDensity: 0.1, maxDensity: 2.0)
        XCTAssertEqual(paper.luminance(density: 1), 15, accuracy: 1e-9)
        XCTAssertEqual(paper.density(pValue: 0), 2.0, accuracy: 0.002)
        XCTAssertEqual(paper.density(pValue: 255), 0.1, accuracy: 0.002)
    }

    // MARK: - The composer's calibrated mapping

    private func film(shape: PresentationLUTShape? = nil, medium: MediumType = .clearFilm) -> ReceivedFilm {
        ReceivedFilm(
            printJobUID: "1.2.3", filmSession: FilmSession(sopInstanceUID: "1.2.3.1", mediumType: medium),
            filmBox: FilmBox(sopInstanceUID: "1.2.3.2", imageBoxSOPInstanceUIDs: []),
            layout: PrintLayout(rows: 1, columns: 1), imageBoxes: [],
            presentationLUTShape: shape, callingAETitle: "TEST")
    }

    func test_gsdfCurveIsMonotonicAndSpansTheSheet() throws {
        let composer = FilmComposer(configuration: FilmComposerConfiguration(densityMapping: .gsdf))
        let curve = try XCTUnwrap(composer.displayTransfer(film: film()))
        XCTAssertEqual(curve.count, 256)
        XCTAssertEqual(curve[255], 255, "the brightest P-Value is the sheet's brightest luminance")
        XCTAssertLessThan(curve[0], 40, "Dmax 3.0 under 10 cd/m² ambient is near black")
        XCTAssertEqual(zip(curve, curve.dropFirst()).allSatisfy { $0 <= $1 }, true)
    }

    func test_paperIsReflectiveAndDarkerAtMaxDensity() throws {
        let composer = FilmComposer(configuration: FilmComposerConfiguration(densityMapping: .gsdf))
        let onFilm = try XCTUnwrap(composer.displayTransfer(film: film()))
        let onPaper = try XCTUnwrap(composer.displayTransfer(film: film(medium: .paper)))
        // No ambient light reflected off the print: its Dmax is darker.
        XCTAssertLessThan(onPaper[0], onFilm[0])
    }

    func test_otherMappingsKeepTheirCurves() {
        let paper = FilmComposer(configuration: FilmComposerConfiguration(densityMapping: .paperDirect))
        XCTAssertNil(paper.displayTransfer(film: film()), "IDENTITY under paper is drawn unchanged")
        XCTAssertEqual(paper.displayTransfer(film: film(shape: .linearOpticalDensity)),
                       paper.linODTransfer(film: film(shape: .linearOpticalDensity)))
    }

    func test_numericDensityUnderGSDFIsAPhysicalDensity() {
        let composer = FilmComposer(configuration: FilmComposerConfiguration(densityMapping: .gsdf))
        let received = film()
        let black = composer.luminance(forDensity: "BLACK", film: received, default: 0)
        let white = composer.luminance(forDensity: "WHITE", film: received, default: 0)
        let od150 = composer.luminance(forDensity: "150", film: received, default: 0)
        XCTAssertEqual(white, 1, accuracy: 1e-9)
        XCTAssertLessThan(black, od150)
        XCTAssertLessThan(od150, white)
        XCTAssertEqual(composer.luminance(forDensity: "300", film: received, default: 0), black, accuracy: 1e-9)
    }

    func test_catalogOffersTheCalibratedMapping() {
        XCTAssertEqual(PrintOptionCatalog.densityMapping(forToken: "gsdf"), .gsdf)
        XCTAssertEqual(DensityMapping(rawValue: "GSDF"), .gsdf)
    }
}
