// NEMA-verified: 2026a, checked 2026-10-06 — pins the rules lifted from dicom-pixedit (D270): stored range from Bits Stored (0028,0101) / Pixel Representation (0028,0103) (PS3.3 2026a C.7.6.3.1, Table C.7-11c), --fill-value outside it refused (P-PIXEDIT-RANGE); Window Width (0028,1051) below 1 refused (C.11.2.1.2)
import XCTest
import DICOMCore
import DICOMKit

/// `PixelEditInputChecks` in DICOMKit (lifted from the dicom-pixedit CLI, D270). The
/// refusal texts are the CLI's and must not drift (CLI parity).
final class PixelEditInputChecksTests: XCTestCase {

    func test_storedRange_followsBitsStoredAndPixelRepresentation() {
        XCTAssertEqual(PixelEditInputChecks.storedRange(bitsStored: 12, signed: false), 0...4095)
        XCTAssertEqual(PixelEditInputChecks.storedRange(bitsStored: 12, signed: true), -2048...2047)
        XCTAssertEqual(PixelEditInputChecks.storedRange(bitsStored: 16, signed: true), -32768...32767)
        XCTAssertEqual(PixelEditInputChecks.storedRange(bitsStored: 8, signed: false), 0...255)
        XCTAssertEqual(PixelEditInputChecks.storedRange(bitsStored: 0, signed: false), 0...1, "clamped to 1 bit")

        var ds = DataSet()
        ds.setInt(16, for: .bitsAllocated, vr: .US)
        ds.setInt(12, for: .bitsStored, vr: .US)
        ds.setInt(1, for: .pixelRepresentation, vr: .US)
        XCTAssertEqual(PixelEditInputChecks.storedRange(of: ds), -2048...2047)
        XCTAssertEqual(PixelEditInputChecks.storedRange(of: DataSet()), 0...65535, "defaults: 16 allocated, unsigned")
    }

    func test_fillValue_outsideTheStoredRange_isRefusedWithTheCLIText() {
        XCTAssertNil(PixelEditInputChecks.fillValueViolation(4095, range: 0...4095))
        XCTAssertNil(PixelEditInputChecks.fillValueViolation(-2048, range: -2048...2047))
        XCTAssertEqual(PixelEditInputChecks.fillValueViolation(4096, range: 0...4095),
                       "--fill-value 4096 is outside the stored range 0...4095 given by Bits Stored (0028,0101) "
                       + "and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1)")
    }

    func test_windowWidth_below1_isRefused() {
        XCTAssertNil(PixelEditInputChecks.windowWidthViolation(1))
        XCTAssertNil(PixelEditInputChecks.windowWidthViolation(400))
        XCTAssertEqual(PixelEditInputChecks.windowWidthViolation(0.5),
                       "--window-width 0.5 is below 1; Window Width (0028,1051) shall always be greater than "
                       + "or equal to 1 (PS3.3 C.11.2.1.2)")
        XCTAssertNotNil(PixelEditInputChecks.windowWidthViolation(0))
        XCTAssertNotNil(PixelEditInputChecks.windowWidthViolation(-3))
        XCTAssertNotNil(PixelEditInputChecks.windowWidthViolation(.nan))
    }
}
