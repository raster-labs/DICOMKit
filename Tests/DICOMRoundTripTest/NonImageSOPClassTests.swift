import XCTest
@testable import DICOMKit
@testable import DICOMCore

/// `tryPixelData` explains a missing pixel module as "non-image" exactly for the SOP
/// Classes whose IOD has none (PS3.4 2026a Tables B.5-1 / GG.3-1 with the PS3.3 IOD module
/// tables; `Scripts/diff_kit.py` checks the whole set).
final class NonImageSOPClassTests: XCTestCase {

    private func fileWithoutPixels(sopClassUID: String) -> DICOMFile {
        var ds = DataSet()
        ds.setString(sopClassUID, for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        return DICOMFile.create(dataSet: ds, sopClassUID: sopClassUID)
    }

    private func isNonImageError(_ file: DICOMFile) -> Bool {
        do {
            _ = try file.tryPixelData()
            return false
        } catch PixelDataError.nonImageSOPClass {
            return true
        } catch {
            return false
        }
    }

    func testClassesWithoutAPixelModuleAreNonImage() {
        // Previously missing from the set: RT Physician Intent (A.86.1.2), Waveform
        // Presentation State (A.92.1), Inventory (A.88, Table GG.3-1).
        for uid in ["1.2.840.10008.5.1.4.1.1.481.10", "1.2.840.10008.5.1.4.1.1.9.100.1",
                    "1.2.840.10008.5.1.4.1.1.201.1", "1.2.840.10008.5.1.4.1.1.88.11"] {
            XCTAssertTrue(isNonImageError(fileWithoutPixels(sopClassUID: uid)), uid)
        }
    }

    func testImageAndRTDoseClassesAreNot() {
        // CT Image (Image Pixel M), RT Dose (Image Pixel C), Parametric Map (floating point).
        for uid in ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.481.2",
                    "1.2.840.10008.5.1.4.1.1.30"] {
            XCTAssertFalse(isNonImageError(fileWithoutPixels(sopClassUID: uid)), uid)
        }
    }
}
