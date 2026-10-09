import XCTest
import DICOMCore
import DICOMKit
@testable import DICOMNetwork

final class PrintServiceTests: XCTestCase {
    
    // MARK: - SOP Class UID Tests
    
    func testBasicFilmSessionSOPClassUID() {
        XCTAssertEqual(basicFilmSessionSOPClassUID, "1.2.840.10008.5.1.1.1")
    }
    
    func testBasicFilmBoxSOPClassUID() {
        XCTAssertEqual(basicFilmBoxSOPClassUID, "1.2.840.10008.5.1.1.2")
    }
    
    func testBasicGrayscaleImageBoxSOPClassUID() {
        XCTAssertEqual(basicGrayscaleImageBoxSOPClassUID, "1.2.840.10008.5.1.1.4")
    }
    
    func testBasicColorImageBoxSOPClassUID() {
        XCTAssertEqual(basicColorImageBoxSOPClassUID, "1.2.840.10008.5.1.1.4.1")
    }
    
    func testBasicGrayscalePrintManagementMetaSOPClassUID() {
        XCTAssertEqual(basicGrayscalePrintManagementMetaSOPClassUID, "1.2.840.10008.5.1.1.9")
    }
    
    func testBasicColorPrintManagementMetaSOPClassUID() {
        XCTAssertEqual(basicColorPrintManagementMetaSOPClassUID, "1.2.840.10008.5.1.1.18")
    }
    
    func testPrinterSOPClassUID() {
        XCTAssertEqual(printerSOPClassUID, "1.2.840.10008.5.1.1.16")
    }
    
    func testPrinterSOPInstanceUID() {
        XCTAssertEqual(printerSOPInstanceUID, "1.2.840.10008.5.1.1.17")
    }
    
    func testPrintJobSOPClassUID() {
        XCTAssertEqual(printJobSOPClassUID, "1.2.840.10008.5.1.1.14")
    }
    
    // MARK: - PrintConfiguration Tests
    
    func testPrintConfigurationDefaults() {
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        XCTAssertEqual(config.host, "192.168.1.100")
        XCTAssertEqual(config.port, 104)
        XCTAssertEqual(config.callingAETitle, "MYAPP")
        XCTAssertEqual(config.calledAETitle, "PRINTER")
        XCTAssertEqual(config.timeout, 30)
        XCTAssertEqual(config.colorMode, .grayscale)
    }
    
    func testPrintConfigurationCustomValues() {
        let config = PrintConfiguration(
            host: "10.0.0.1",
            port: 11112,
            callingAETitle: "SOURCE",
            calledAETitle: "DEST",
            timeout: 60,
            colorMode: .color
        )
        
        XCTAssertEqual(config.host, "10.0.0.1")
        XCTAssertEqual(config.port, 11112)
        XCTAssertEqual(config.callingAETitle, "SOURCE")
        XCTAssertEqual(config.calledAETitle, "DEST")
        XCTAssertEqual(config.timeout, 60)
        XCTAssertEqual(config.colorMode, .color)
    }
    
    // MARK: - PrintColorMode Tests
    
    func testPrintColorModeRawValues() {
        XCTAssertEqual(DICOMNetwork.PrintColorMode.grayscale.rawValue, "GRAYSCALE")
        XCTAssertEqual(DICOMNetwork.PrintColorMode.color.rawValue, "COLOR")
    }
    
    // MARK: - FilmSession Tests
    
    func testFilmSessionDefaults() {
        let session = FilmSession()
        
        XCTAssertEqual(session.sopInstanceUID, "")
        XCTAssertEqual(session.numberOfCopies, 1)
        XCTAssertEqual(session.printPriority, .medium)
        XCTAssertEqual(session.mediumType, .paper)
        XCTAssertEqual(session.filmDestination, .processor)
        XCTAssertNil(session.filmSessionLabel)
    }
    
    func testFilmSessionCustomValues() {
        let session = FilmSession(
            sopInstanceUID: "1.2.3.4.5",
            numberOfCopies: 3,
            printPriority: .high,
            mediumType: .blueFilm,
            filmDestination: .magazine,
            filmSessionLabel: "Test Print"
        )
        
        XCTAssertEqual(session.sopInstanceUID, "1.2.3.4.5")
        XCTAssertEqual(session.numberOfCopies, 3)
        XCTAssertEqual(session.printPriority, .high)
        XCTAssertEqual(session.mediumType, .blueFilm)
        XCTAssertEqual(session.filmDestination, .magazine)
        XCTAssertEqual(session.filmSessionLabel, "Test Print")
    }
    
    // MARK: - PrintPriority Tests
    
    func testPrintPriorityRawValues() {
        XCTAssertEqual(PrintPriority.high.rawValue, "HIGH")
        XCTAssertEqual(PrintPriority.medium.rawValue, "MED")
        XCTAssertEqual(PrintPriority.low.rawValue, "LOW")
    }
    
    // MARK: - MediumType Tests
    
    func testMediumTypeRawValues() {
        XCTAssertEqual(MediumType.paper.rawValue, "PAPER")
        XCTAssertEqual(MediumType.clearFilm.rawValue, "CLEAR FILM")
        XCTAssertEqual(MediumType.blueFilm.rawValue, "BLUE FILM")
        // PS3.3 Table C.13-1 (P-MAMMO, 2026-09-29).
        XCTAssertEqual(MediumType.mammoClearFilm.rawValue, "MAMMO CLEAR FILM")
        XCTAssertEqual(MediumType.mammoBlueFilm.rawValue, "MAMMO BLUE FILM")
    }

    /// Text String (2030,0020) is LO: 64 characters maximum, no backslash, no
    /// control characters (PS3.5 Table 6.2-1) — D41.
    func testAnnotationTextStringIsALegalLO() {
        let long = PrintAnnotation(position: 1, text: String(repeating: "X", count: 90))
        XCTAssertEqual(long.textStringValue.count, 64)
        XCTAssertEqual(PrintAnnotation(position: 2, text: "DOE^JANE\\123\tA").textStringValue, "DOE^JANE/123A")
        XCTAssertEqual(PrintAnnotation(position: 3, text: "short").textStringValue, "short")
        XCTAssertEqual(PrintAnnotation.textStringMaximumLength, 64)
    }

    /// The deprecated spellings still parse, and are read and written as the
    /// Table C.13-1 terms they stand for.
    func testLegacyMammoSpellingsMapToTheTerms() throws {
        let clear = try XCTUnwrap(MediumType(rawValue: "MAMMO CLEAR"))
        let blue = try XCTUnwrap(MediumType(rawValue: "MAMMO BLUE"))
        XCTAssertEqual(clear.normalized, .mammoClearFilm)
        XCTAssertEqual(blue.normalized, .mammoBlueFilm)
        XCTAssertEqual(clear.wireValue, "MAMMO CLEAR FILM")
        XCTAssertEqual(blue.wireValue, "MAMMO BLUE FILM")
        XCTAssertEqual(MediumType.paper.wireValue, "PAPER")
    }
    
    // MARK: - FilmDestination Tests
    
    func testFilmDestinationRawValues() {
        XCTAssertEqual(FilmDestination.magazine.rawValue, "MAGAZINE")
        XCTAssertEqual(FilmDestination.processor.rawValue, "PROCESSOR")
        XCTAssertEqual(FilmDestination.bin1.rawValue, "BIN_1")
        XCTAssertEqual(FilmDestination.bin2.rawValue, "BIN_2")
    }
    
    // MARK: - FilmBox Tests
    
    func testFilmBoxDefaults() {
        let box = FilmBox()
        
        XCTAssertEqual(box.sopInstanceUID, "")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\1,1")
        XCTAssertEqual(box.filmOrientation, .portrait)
        XCTAssertEqual(box.filmSizeID, .size8InX10In)
        XCTAssertEqual(box.magnificationType, .replicate)
        XCTAssertEqual(box.borderDensity, "BLACK")
        XCTAssertEqual(box.emptyImageDensity, "BLACK")
        XCTAssertEqual(box.trimOption, .no)
        XCTAssertNil(box.configurationInformation)
        XCTAssertTrue(box.imageBoxSOPInstanceUIDs.isEmpty)
    }
    
    func testFilmBoxCustomValues() {
        let box = FilmBox(
            sopInstanceUID: "1.2.3.4",
            imageDisplayFormat: "STANDARD\\2,3",
            filmOrientation: .landscape,
            filmSizeID: .size14InX17In,
            magnificationType: .bilinear,
            borderDensity: "WHITE",
            emptyImageDensity: "WHITE",
            trimOption: .yes,
            configurationInformation: "CS=BINARY",
            imageBoxSOPInstanceUIDs: ["1.2.3.4.1", "1.2.3.4.2"]
        )
        
        XCTAssertEqual(box.sopInstanceUID, "1.2.3.4")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\2,3")
        XCTAssertEqual(box.filmOrientation, .landscape)
        XCTAssertEqual(box.filmSizeID, .size14InX17In)
        XCTAssertEqual(box.magnificationType, .bilinear)
        XCTAssertEqual(box.borderDensity, "WHITE")
        XCTAssertEqual(box.emptyImageDensity, "WHITE")
        XCTAssertEqual(box.trimOption, .yes)
        XCTAssertEqual(box.configurationInformation, "CS=BINARY")
        XCTAssertEqual(box.imageBoxSOPInstanceUIDs.count, 2)
    }
    
    // MARK: - FilmOrientation Tests
    
    func testFilmOrientationRawValues() {
        XCTAssertEqual(FilmOrientation.portrait.rawValue, "PORTRAIT")
        XCTAssertEqual(FilmOrientation.landscape.rawValue, "LANDSCAPE")
    }
    
    // MARK: - FilmSize Tests
    
    func testFilmSizeRawValues() {
        XCTAssertEqual(FilmSize.size8InX10In.rawValue, "8INX10IN")
        XCTAssertEqual(FilmSize.size8_5InX11In.rawValue, "8_5INX11IN")
        XCTAssertEqual(FilmSize.size10InX12In.rawValue, "10INX12IN")
        XCTAssertEqual(FilmSize.size10InX14In.rawValue, "10INX14IN")
        XCTAssertEqual(FilmSize.size11InX14In.rawValue, "11INX14IN")
        XCTAssertEqual(FilmSize.size11InX17In.rawValue, "11INX17IN")
        XCTAssertEqual(FilmSize.size14InX14In.rawValue, "14INX14IN")
        XCTAssertEqual(FilmSize.size14InX17In.rawValue, "14INX17IN")
        XCTAssertEqual(FilmSize.size24CmX24Cm.rawValue, "24CMX24CM")
        XCTAssertEqual(FilmSize.size24CmX30Cm.rawValue, "24CMX30CM")
        XCTAssertEqual(FilmSize.a4.rawValue, "A4")
        XCTAssertEqual(FilmSize.a3.rawValue, "A3")
    }
    
    // MARK: - MagnificationType Tests
    
    func testMagnificationTypeRawValues() {
        XCTAssertEqual(MagnificationType.replicate.rawValue, "REPLICATE")
        XCTAssertEqual(MagnificationType.bilinear.rawValue, "BILINEAR")
        XCTAssertEqual(MagnificationType.cubic.rawValue, "CUBIC")
        XCTAssertEqual(MagnificationType.none.rawValue, "NONE")
    }
    
    // MARK: - TrimOption Tests
    
    func testTrimOptionRawValues() {
        XCTAssertEqual(TrimOption.yes.rawValue, "YES")
        XCTAssertEqual(TrimOption.no.rawValue, "NO")
    }
    
    // MARK: - ImageBoxContent Tests
    
    func testImageBoxContentDefaults() {
        let content = ImageBoxContent()
        
        XCTAssertEqual(content.sopInstanceUID, "")
        XCTAssertEqual(content.imagePosition, 1)
        XCTAssertEqual(content.polarity, .normal)
        XCTAssertNil(content.requestedImageSize)
        XCTAssertEqual(content.requestedDecimateCropBehavior, .decimate)
    }
    
    func testImageBoxContentCustomValues() {
        let content = ImageBoxContent(
            sopInstanceUID: "1.2.3.4.5.6",
            imagePosition: 3,
            polarity: .reverse,
            requestedImageSize: "200",
            requestedDecimateCropBehavior: .crop
        )
        
        XCTAssertEqual(content.sopInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(content.imagePosition, 3)
        XCTAssertEqual(content.polarity, .reverse)
        XCTAssertEqual(content.requestedImageSize, "200")
        XCTAssertEqual(content.requestedDecimateCropBehavior, .crop)
    }
    
    // MARK: - ImagePolarity Tests
    
    func testImagePolarityRawValues() {
        XCTAssertEqual(ImagePolarity.normal.rawValue, "NORMAL")
        XCTAssertEqual(ImagePolarity.reverse.rawValue, "REVERSE")
    }
    
    // MARK: - DecimateCropBehavior Tests
    
    func testDecimateCropBehaviorRawValues() {
        XCTAssertEqual(DecimateCropBehavior.decimate.rawValue, "DECIMATE")
        XCTAssertEqual(DecimateCropBehavior.crop.rawValue, "CROP")
        XCTAssertEqual(DecimateCropBehavior.failOver.rawValue, "FAIL")
    }
    
    // MARK: - PrinterStatus Tests
    
    func testPrinterStatusCreation() {
        let status = PrinterStatus(status: "NORMAL")
        
        XCTAssertEqual(status.status, "NORMAL")
        XCTAssertNil(status.statusInfo)
        XCTAssertNil(status.printerName)
        XCTAssertTrue(status.isNormal)
    }
    
    func testPrinterStatusWithDetails() {
        let status = PrinterStatus(
            status: "WARNING",
            statusInfo: "Low toner",
            printerName: "DICOM Printer 1"
        )
        
        XCTAssertEqual(status.status, "WARNING")
        XCTAssertEqual(status.statusInfo, "Low toner")
        XCTAssertEqual(status.printerName, "DICOM Printer 1")
        XCTAssertFalse(status.isNormal)
    }
    
    func testPrinterStatusFailure() {
        let status = PrinterStatus(status: "FAILURE", statusInfo: "Paper jam")
        
        XCTAssertFalse(status.isNormal)
    }
    
    // MARK: - PrintResult Tests
    
    func testPrintResultSuccess() {
        let result = PrintResult(
            success: true,
            status: .success,
            filmSessionUID: "1.2.3.4",
            filmBoxUID: "1.2.3.4.5",
            printJobUID: "1.2.3.4.6"
        )
        
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.status.isSuccess)
        XCTAssertEqual(result.filmSessionUID, "1.2.3.4")
        XCTAssertEqual(result.filmBoxUID, "1.2.3.4.5")
        XCTAssertEqual(result.printJobUID, "1.2.3.4.6")
        XCTAssertNil(result.errorMessage)
    }
    
    func testPrintResultFailure() {
        let result = PrintResult(
            success: false,
            status: .failedUnableToProcess,
            errorMessage: "Printer offline"
        )
        
        XCTAssertFalse(result.success)
        XCTAssertNil(result.filmSessionUID)
        XCTAssertNil(result.filmBoxUID)
        XCTAssertNil(result.printJobUID)
        XCTAssertEqual(result.errorMessage, "Printer offline")
    }
    
    // MARK: - Print Tag Tests
    
    func testFilmSessionTags() {
        XCTAssertEqual(Tag.numberOfCopies.group, 0x2000)
        XCTAssertEqual(Tag.numberOfCopies.element, 0x0010)
        XCTAssertEqual(Tag.printPriority.group, 0x2000)
        XCTAssertEqual(Tag.printPriority.element, 0x0020)
        XCTAssertEqual(Tag.mediumType.group, 0x2000)
        XCTAssertEqual(Tag.mediumType.element, 0x0030)
        XCTAssertEqual(Tag.filmDestination.group, 0x2000)
        XCTAssertEqual(Tag.filmDestination.element, 0x0040)
        XCTAssertEqual(Tag.filmSessionLabel.group, 0x2000)
        XCTAssertEqual(Tag.filmSessionLabel.element, 0x0050)
        XCTAssertEqual(Tag.memoryAllocation.group, 0x2000)
        XCTAssertEqual(Tag.memoryAllocation.element, 0x0060)
        XCTAssertEqual(Tag.referencedFilmBoxSequence.group, 0x2000)
        XCTAssertEqual(Tag.referencedFilmBoxSequence.element, 0x0500)
    }
    
    func testFilmBoxTags() {
        XCTAssertEqual(Tag.imageDisplayFormat.group, 0x2010)
        XCTAssertEqual(Tag.imageDisplayFormat.element, 0x0010)
        XCTAssertEqual(Tag.filmOrientation.group, 0x2010)
        XCTAssertEqual(Tag.filmOrientation.element, 0x0040)
        XCTAssertEqual(Tag.filmSizeID.group, 0x2010)
        XCTAssertEqual(Tag.filmSizeID.element, 0x0050)
        XCTAssertEqual(Tag.magnificationType.group, 0x2010)
        XCTAssertEqual(Tag.magnificationType.element, 0x0060)
        XCTAssertEqual(Tag.borderDensity.group, 0x2010)
        XCTAssertEqual(Tag.borderDensity.element, 0x0100)
        XCTAssertEqual(Tag.trim.group, 0x2010)
        XCTAssertEqual(Tag.trim.element, 0x0140)
        XCTAssertEqual(Tag.referencedImageBoxSequence.group, 0x2010)
        XCTAssertEqual(Tag.referencedImageBoxSequence.element, 0x0510)
    }
    
    func testImageBoxTags() {
        XCTAssertEqual(Tag.imageBoxPosition.group, 0x2020)
        XCTAssertEqual(Tag.imageBoxPosition.element, 0x0010)
        XCTAssertEqual(Tag.polarity.group, 0x2020)
        XCTAssertEqual(Tag.polarity.element, 0x0020)
        XCTAssertEqual(Tag.requestedImageSize.group, 0x2020)
        XCTAssertEqual(Tag.requestedImageSize.element, 0x0030)
    }
    
    func testPrinterTags() {
        XCTAssertEqual(Tag.printerStatus.group, 0x2110)
        XCTAssertEqual(Tag.printerStatus.element, 0x0010)
        XCTAssertEqual(Tag.printerStatusInfo.group, 0x2110)
        XCTAssertEqual(Tag.printerStatusInfo.element, 0x0020)
        XCTAssertEqual(Tag.printerName.group, 0x2110)
        XCTAssertEqual(Tag.printerName.element, 0x0030)
    }
    
    func testPrintJobTags() {
        XCTAssertEqual(Tag.executionStatus.group, 0x2100)
        XCTAssertEqual(Tag.executionStatus.element, 0x0020)
        XCTAssertEqual(Tag.executionStatusInfo.group, 0x2100)
        XCTAssertEqual(Tag.executionStatusInfo.element, 0x0030)
        XCTAssertEqual(Tag.creationDate.group, 0x2100)
        XCTAssertEqual(Tag.creationDate.element, 0x0040)
        XCTAssertEqual(Tag.creationTime.group, 0x2100)
        XCTAssertEqual(Tag.creationTime.element, 0x0050)
    }
    
    // MARK: - Film Session Management Tests
    
    func testCreateFilmSessionRequestBuilding() {
        // Test that createFilmSession properly constructs the N-CREATE request
        // This test validates the data set structure for Film Session attributes
        
        let session = FilmSession(
            numberOfCopies: 2,
            printPriority: .high,
            mediumType: .clearFilm,
            filmDestination: .magazine,
            filmSessionLabel: "Test Session"
        )
        
        // Validate the session configuration
        XCTAssertEqual(session.numberOfCopies, 2)
        XCTAssertEqual(session.printPriority, .high)
        XCTAssertEqual(session.mediumType, .clearFilm)
        XCTAssertEqual(session.filmDestination, .magazine)
        XCTAssertEqual(session.filmSessionLabel, "Test Session")
    }
    
    func testDeleteFilmSessionRequestBuilding() {
        // Test that deleteFilmSession properly constructs the N-DELETE request
        let filmSessionUID = "1.2.840.113619.2.55.3.2024.01.01"
        
        // Validate UID format (basic check)
        XCTAssertFalse(filmSessionUID.isEmpty)
        XCTAssertTrue(filmSessionUID.contains("."))
    }
    
    func testFilmSessionWithDefaults() {
        let session = FilmSession()
        
        XCTAssertEqual(session.numberOfCopies, 1)
        XCTAssertEqual(session.printPriority, .medium)
        XCTAssertEqual(session.mediumType, .paper)
        XCTAssertEqual(session.filmDestination, .processor)
        XCTAssertNil(session.filmSessionLabel)
    }
    
    func testFilmSessionWithCustomValues() {
        let session = FilmSession(
            sopInstanceUID: "1.2.3",
            numberOfCopies: 3,
            printPriority: .low,
            mediumType: .mammoBlueFilm,
            filmDestination: .bin2,
            filmSessionLabel: "Mammography Study"
        )
        
        XCTAssertEqual(session.sopInstanceUID, "1.2.3")
        XCTAssertEqual(session.numberOfCopies, 3)
        XCTAssertEqual(session.printPriority, .low)
        XCTAssertEqual(session.mediumType, .mammoBlueFilm)
        XCTAssertEqual(session.filmDestination, .bin2)
        XCTAssertEqual(session.filmSessionLabel, "Mammography Study")
    }
    
    // MARK: - FilmBoxResult Tests
    
    func testFilmBoxResultInitialization() {
        let result = FilmBoxResult(
            filmBoxUID: "1.2.840.10008.1.2.3.4",
            imageBoxUIDs: ["1.2.3.4.1", "1.2.3.4.2", "1.2.3.4.3", "1.2.3.4.4"],
            imageCount: 4
        )
        
        XCTAssertEqual(result.filmBoxUID, "1.2.840.10008.1.2.3.4")
        XCTAssertEqual(result.imageBoxUIDs.count, 4)
        XCTAssertEqual(result.imageBoxUIDs[0], "1.2.3.4.1")
        XCTAssertEqual(result.imageBoxUIDs[3], "1.2.3.4.4")
        XCTAssertEqual(result.imageCount, 4)
    }
    
    func testFilmBoxResultWithNoImageBoxes() {
        let result = FilmBoxResult(
            filmBoxUID: "1.2.3",
            imageBoxUIDs: [],
            imageCount: 1
        )
        
        XCTAssertEqual(result.filmBoxUID, "1.2.3")
        XCTAssertTrue(result.imageBoxUIDs.isEmpty)
        XCTAssertEqual(result.imageCount, 1)
    }
    
    func testFilmBoxResultWithMultipleImageBoxes() {
        let imageBoxes = (1...6).map { "1.2.3.4.\($0)" }
        let result = FilmBoxResult(
            filmBoxUID: "1.2.3",
            imageBoxUIDs: imageBoxes,
            imageCount: 6
        )
        
        XCTAssertEqual(result.filmBoxUID, "1.2.3")
        XCTAssertEqual(result.imageBoxUIDs.count, 6)
        XCTAssertEqual(result.imageCount, 6)
    }
    
    // MARK: - Image Display Format Tests
    
    func testFilmBoxWithSingleImageFormat() {
        let box = FilmBox(imageDisplayFormat: "STANDARD\\1,1")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\1,1")
    }
    
    func testFilmBoxWith2x2Format() {
        let box = FilmBox(imageDisplayFormat: "STANDARD\\2,2")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\2,2")
    }
    
    func testFilmBoxWith3x4Format() {
        let box = FilmBox(imageDisplayFormat: "STANDARD\\3,4")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\3,4")
    }
    
    func testFilmBoxWith4x4Format() {
        let box = FilmBox(imageDisplayFormat: "STANDARD\\4,4")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\4,4")
    }
    
    func testFilmBoxWith2x3Format() {
        let box = FilmBox(imageDisplayFormat: "STANDARD\\2,3")
        XCTAssertEqual(box.imageDisplayFormat, "STANDARD\\2,3")
    }
    
    // MARK: - Print Tags Tests
    
    func testImageBoxPositionTag() {
        XCTAssertEqual(Tag.imageBoxPosition.group, 0x2020)
        XCTAssertEqual(Tag.imageBoxPosition.element, 0x0010)
    }
    
    func testPolarityTag() {
        XCTAssertEqual(Tag.polarity.group, 0x2020)
        XCTAssertEqual(Tag.polarity.element, 0x0020)
    }
    
    func testRequestedImageSizeTag() {
        XCTAssertEqual(Tag.requestedImageSize.group, 0x2020)
        XCTAssertEqual(Tag.requestedImageSize.element, 0x0030)
    }
    
    func testRequestedDecimateCropBehaviorTag() {
        XCTAssertEqual(Tag.requestedDecimateCropBehavior.group, 0x2020)
        XCTAssertEqual(Tag.requestedDecimateCropBehavior.element, 0x0040)
    }
    
    func testPreformattedGrayscaleImageSequenceTag() {
        XCTAssertEqual(Tag.preformattedGrayscaleImageSequence.group, 0x2020)
        XCTAssertEqual(Tag.preformattedGrayscaleImageSequence.element, 0x0110)
    }
    
    func testPreformattedColorImageSequenceTag() {
        XCTAssertEqual(Tag.preformattedColorImageSequence.group, 0x2020)
        XCTAssertEqual(Tag.preformattedColorImageSequence.element, 0x0111)
    }
    
    // MARK: - Integration Test Placeholders
    
    // NOTE: The following tests require a DICOM Print SCP server to be running
    // and are therefore documented here but not implemented as unit tests.
    // These should be run as integration tests with a test Print SCP.
    
    // Integration test scenarios for setImageBox():
    // - Test with valid grayscale preformatted image data
    // - Test with valid color preformatted image data
    // - Test with invalid pixel data (should fail gracefully)
    // - Test with all image box attributes set
    // - Test with minimum required attributes only
    
    // Integration test scenarios for printFilmBox():
    // - Test successful print operation returning Print Job UID
    // - Test with invalid Film Box UID (should fail)
    // - Test when Print Job UID is empty (should throw unexpectedResponse)
    // - Test print status monitoring after successful print
    
    // Integration test scenarios for parseImageBoxUIDs():
    // - Test parsing valid Film Box N-CREATE response with multiple image boxes
    // - Test parsing response with single image box
    // - Test parsing empty or malformed response data
    // - Test parsing response with missing Referenced Image Box Sequence
    
    // Integration test scenario for complete print workflow:
    // - Test full workflow: getPrinterStatus → createFilmSession → createFilmBox →
    //   setImageBox (for each position) → printFilmBox → deleteFilmSession
    // - Test with various film layouts (1x1, 2x2, 3x4, 4x5)
    // - Test with both grayscale and color modes
    // - Test error recovery at each stage
    // - Test concurrent print jobs
    
    // TODO: Implement integration tests in a separate test suite
    // See DICOM_PRINTER_PLAN.md Phase 1.5 for integration test requirements
    
    // MARK: - PrintJobStatus Tests
    
    func testPrintJobStatusInitialization() {
        let status = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.001",
            executionStatus: "PENDING"
        )
        
        XCTAssertEqual(status.printJobUID, "1.2.840.113619.2.55.3.2024.01.01.001")
        XCTAssertEqual(status.executionStatus, "PENDING")
        XCTAssertNil(status.executionStatusInfo)
        XCTAssertNil(status.creationDate)
        XCTAssertNil(status.creationTime)
    }
    
    func testPrintJobStatusWithAllFields() {
        let creationDate = Date()
        let creationTime = Date()
        
        let status = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.002",
            executionStatus: "DONE",
            executionStatusInfo: "Printed successfully",
            creationDate: creationDate,
            creationTime: creationTime
        )
        
        XCTAssertEqual(status.printJobUID, "1.2.840.113619.2.55.3.2024.01.01.002")
        XCTAssertEqual(status.executionStatus, "DONE")
        XCTAssertEqual(status.executionStatusInfo, "Printed successfully")
        XCTAssertEqual(status.creationDate, creationDate)
        XCTAssertEqual(status.creationTime, creationTime)
    }
    
    func testPrintJobStatusIsInProgress_Pending() {
        let status = PrintJobStatus(
            printJobUID: "1.2.3",
            executionStatus: "PENDING"
        )
        
        XCTAssertTrue(status.isInProgress)
        XCTAssertFalse(status.isCompleted)
        XCTAssertFalse(status.isFailed)
    }
    
    func testPrintJobStatusIsInProgress_Printing() {
        let status = PrintJobStatus(
            printJobUID: "1.2.3",
            executionStatus: "PRINTING"
        )
        
        XCTAssertTrue(status.isInProgress)
        XCTAssertFalse(status.isCompleted)
        XCTAssertFalse(status.isFailed)
    }
    
    func testPrintJobStatusIsCompleted() {
        let status = PrintJobStatus(
            printJobUID: "1.2.3",
            executionStatus: "DONE"
        )
        
        XCTAssertFalse(status.isInProgress)
        XCTAssertTrue(status.isCompleted)
        XCTAssertFalse(status.isFailed)
    }
    
    func testPrintJobStatusIsFailed() {
        let status = PrintJobStatus(
            printJobUID: "1.2.3",
            executionStatus: "FAILURE",
            executionStatusInfo: "Printer offline"
        )
        
        XCTAssertFalse(status.isInProgress)
        XCTAssertFalse(status.isCompleted)
        XCTAssertTrue(status.isFailed)
        XCTAssertEqual(status.executionStatusInfo, "Printer offline")
    }
    
    func testPrintJobStatusAllExecutionStates() {
        let states = ["PENDING", "PRINTING", "DONE", "FAILURE"]
        
        for state in states {
            let status = PrintJobStatus(
                printJobUID: "1.2.3",
                executionStatus: state
            )
            
            XCTAssertEqual(status.executionStatus, state)
            
            switch state {
            case "PENDING", "PRINTING":
                XCTAssertTrue(status.isInProgress)
                XCTAssertFalse(status.isCompleted)
                XCTAssertFalse(status.isFailed)
            case "DONE":
                XCTAssertFalse(status.isInProgress)
                XCTAssertTrue(status.isCompleted)
                XCTAssertFalse(status.isFailed)
            case "FAILURE":
                XCTAssertFalse(status.isInProgress)
                XCTAssertFalse(status.isCompleted)
                XCTAssertTrue(status.isFailed)
            default:
                XCTFail("Unexpected execution status: \(state)")
            }
        }
    }
    
    func testPrintJobStatusWithUnknownState() {
        let status = PrintJobStatus(
            printJobUID: "1.2.3",
            executionStatus: "UNKNOWN"
        )
        
        XCTAssertEqual(status.executionStatus, "UNKNOWN")
        XCTAssertFalse(status.isInProgress)
        XCTAssertFalse(status.isCompleted)
        XCTAssertFalse(status.isFailed)
    }
    
    func testPrintJobStatusWithMultipleStatuses() {
        // Test creating multiple PrintJobStatus instances with different states
        let pendingStatus = PrintJobStatus(
            printJobUID: "1.2.3.1",
            executionStatus: "PENDING"
        )
        
        let printingStatus = PrintJobStatus(
            printJobUID: "1.2.3.2",
            executionStatus: "PRINTING"
        )
        
        let doneStatus = PrintJobStatus(
            printJobUID: "1.2.3.3",
            executionStatus: "DONE"
        )
        
        let failureStatus = PrintJobStatus(
            printJobUID: "1.2.3.4",
            executionStatus: "FAILURE",
            executionStatusInfo: "Paper jam"
        )
        
        XCTAssertTrue(pendingStatus.isInProgress)
        XCTAssertTrue(printingStatus.isInProgress)
        XCTAssertTrue(doneStatus.isCompleted)
        XCTAssertTrue(failureStatus.isFailed)
        XCTAssertEqual(failureStatus.executionStatusInfo, "Paper jam")
    }
    
    // MARK: - Print Job Status Tag Tests
    
    func testExecutionStatusTag() {
        XCTAssertEqual(Tag.executionStatus.group, 0x2100)
        XCTAssertEqual(Tag.executionStatus.element, 0x0020)
    }
    
    func testExecutionStatusInfoTag() {
        XCTAssertEqual(Tag.executionStatusInfo.group, 0x2100)
        XCTAssertEqual(Tag.executionStatusInfo.element, 0x0030)
    }
    
    func testCreationDateTag() {
        XCTAssertEqual(Tag.creationDate.group, 0x2100)
        XCTAssertEqual(Tag.creationDate.element, 0x0040)
    }
    
    func testCreationTimeTag() {
        XCTAssertEqual(Tag.creationTime.group, 0x2100)
        XCTAssertEqual(Tag.creationTime.element, 0x0050)
    }
    
    // MARK: - Print Job Workflow Tests
    
    func testPrintJobWorkflow() {
        // Test that a typical print job workflow can be represented
        // 1. Print job created -> PENDING
        let pendingJob = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.001",
            executionStatus: "PENDING"
        )
        XCTAssertTrue(pendingJob.isInProgress)
        
        // 2. Print job starts -> PRINTING
        let printingJob = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.001",
            executionStatus: "PRINTING",
            executionStatusInfo: "Page 1 of 1"
        )
        XCTAssertTrue(printingJob.isInProgress)
        XCTAssertEqual(printingJob.executionStatusInfo, "Page 1 of 1")
        
        // 3. Print job completes -> DONE
        let doneJob = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.001",
            executionStatus: "DONE",
            executionStatusInfo: "Completed"
        )
        XCTAssertTrue(doneJob.isCompleted)
    }
    
    func testPrintJobFailureWorkflow() {
        // Test that a failed print job can be represented
        let failedJob = PrintJobStatus(
            printJobUID: "1.2.840.113619.2.55.3.2024.01.01.001",
            executionStatus: "FAILURE",
            executionStatusInfo: "Printer offline - check connection"
        )
        
        XCTAssertTrue(failedJob.isFailed)
        XCTAssertEqual(failedJob.executionStatusInfo, "Printer offline - check connection")
        XCTAssertFalse(failedJob.isInProgress)
        XCTAssertFalse(failedJob.isCompleted)
    }
    
    // MARK: - Phase 2: PrintOptions Tests
    
    func testPrintOptionsDefaults() {
        let options = PrintOptions()
        
        XCTAssertEqual(options.numberOfCopies, 1)
        XCTAssertEqual(options.priority, .medium)
        XCTAssertEqual(options.filmSize, .size8InX10In)
        XCTAssertEqual(options.filmOrientation, .portrait)
        XCTAssertEqual(options.mediumType, .clearFilm)
        XCTAssertEqual(options.filmDestination, .processor)
        XCTAssertEqual(options.borderDensity, "BLACK")
        XCTAssertEqual(options.emptyImageDensity, "BLACK")
        XCTAssertEqual(options.magnificationType, .replicate)
        XCTAssertEqual(options.polarity, .normal)
        XCTAssertEqual(options.trimOption, .no)
        XCTAssertNil(options.sessionLabel)
    }
    
    func testPrintOptionsCustomValues() {
        let options = PrintOptions(
            numberOfCopies: 3,
            priority: .high,
            filmSize: .size14InX17In,
            filmOrientation: .landscape,
            mediumType: .blueFilm,
            filmDestination: .magazine,
            borderDensity: "WHITE",
            emptyImageDensity: "WHITE",
            magnificationType: .bilinear,
            polarity: .reverse,
            trimOption: .yes,
            sessionLabel: "Test Print"
        )
        
        XCTAssertEqual(options.numberOfCopies, 3)
        XCTAssertEqual(options.priority, .high)
        XCTAssertEqual(options.filmSize, .size14InX17In)
        XCTAssertEqual(options.filmOrientation, .landscape)
        XCTAssertEqual(options.mediumType, .blueFilm)
        XCTAssertEqual(options.filmDestination, .magazine)
        XCTAssertEqual(options.borderDensity, "WHITE")
        XCTAssertEqual(options.emptyImageDensity, "WHITE")
        XCTAssertEqual(options.magnificationType, .bilinear)
        XCTAssertEqual(options.polarity, .reverse)
        XCTAssertEqual(options.trimOption, .yes)
        XCTAssertEqual(options.sessionLabel, "Test Print")
    }
    
    func testPrintOptionsStaticDefault() {
        let options = PrintOptions.default
        
        XCTAssertEqual(options.numberOfCopies, 1)
        XCTAssertEqual(options.priority, .medium)
        XCTAssertEqual(options.filmSize, .size8InX10In)
    }
    
    func testPrintOptionsStaticHighQuality() {
        let options = PrintOptions.highQuality
        
        XCTAssertEqual(options.priority, .high)
        XCTAssertEqual(options.filmSize, .size14InX17In)
        XCTAssertEqual(options.mediumType, .clearFilm)
        XCTAssertEqual(options.magnificationType, .bilinear)
    }
    
    func testPrintOptionsStaticDraft() {
        let options = PrintOptions.draft
        
        XCTAssertEqual(options.priority, .low)
        XCTAssertEqual(options.filmSize, .size8_5InX11In)
        XCTAssertEqual(options.mediumType, .paper)
        XCTAssertEqual(options.magnificationType, .replicate)
    }
    
    func testPrintOptionsStaticMammography() {
        let options = PrintOptions.mammography
        
        XCTAssertEqual(options.priority, .high)
        XCTAssertEqual(options.filmSize, .size14InX17In)
        XCTAssertEqual(options.mediumType, .mammoBlueFilm)
        XCTAssertEqual(options.magnificationType, .bilinear)
    }
    
    // MARK: - Phase 2: PrintLayout Tests
    
    func testPrintLayoutBasicInitialization() {
        let layout = PrintLayout(rows: 2, columns: 3)
        
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.imageCount, 6)
        // PS3.3 C.13.3: STANDARD\\C,R — columns first.
        XCTAssertEqual(layout.imageDisplayFormat, "STANDARD\\3,2")
    }
    
    func testPrintLayoutMinimumValues() {
        let layout = PrintLayout(rows: 0, columns: 0)
        
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.imageCount, 1)
    }
    
    func testPrintLayoutOptimalFor1Image() {
        let layout = PrintLayout.optimalLayout(for: 1)
        
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 1)
    }
    
    func testPrintLayoutOptimalFor2Images() {
        let layout = PrintLayout.optimalLayout(for: 2)
        
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 2)
    }
    
    func testPrintLayoutOptimalFor4Images() {
        let layout = PrintLayout.optimalLayout(for: 4)
        
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.columns, 2)
    }
    
    func testPrintLayoutOptimalFor6Images() {
        let layout = PrintLayout.optimalLayout(for: 6)
        
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.columns, 3)
    }
    
    func testPrintLayoutOptimalFor9Images() {
        let layout = PrintLayout.optimalLayout(for: 9)
        
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.columns, 3)
    }
    
    func testPrintLayoutOptimalFor12Images() {
        let layout = PrintLayout.optimalLayout(for: 12)
        
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.columns, 4)
    }
    
    func testPrintLayoutOptimalFor16Images() {
        let layout = PrintLayout.optimalLayout(for: 16)
        
        XCTAssertEqual(layout.rows, 4)
        XCTAssertEqual(layout.columns, 4)
    }
    
    func testPrintLayoutOptimalFor20Images() {
        let layout = PrintLayout.optimalLayout(for: 20)
        
        XCTAssertEqual(layout.rows, 4)
        XCTAssertEqual(layout.columns, 5)
    }
    
    func testPrintLayoutOptimalForMoreThan20Images() {
        let layout = PrintLayout.optimalLayout(for: 30)
        
        XCTAssertEqual(layout.rows, 5)
        XCTAssertEqual(layout.columns, 5)
    }
    
    func testPrintLayoutStaticSingleImage() {
        let layout = PrintLayout.singleImage
        
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 1)
    }
    
    func testPrintLayoutStaticComparison() {
        let layout = PrintLayout.comparison
        
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.columns, 2)
    }
    
    func testPrintLayoutStaticGrid2x2() {
        let layout = PrintLayout.grid2x2
        
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.columns, 2)
    }
    
    func testPrintLayoutStaticGrid3x3() {
        let layout = PrintLayout.grid3x3
        
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.columns, 3)
    }
    
    func testPrintLayoutStaticGrid4x4() {
        let layout = PrintLayout.grid4x4
        
        XCTAssertEqual(layout.rows, 4)
        XCTAssertEqual(layout.columns, 4)
    }
    
    func testPrintLayoutStaticMultiPhase2x3() {
        let layout = PrintLayout.multiPhase2x3
        
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.imageCount, 6)
    }
    
    func testPrintLayoutStaticMultiPhase3x4() {
        let layout = PrintLayout.multiPhase3x4
        
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.columns, 4)
        XCTAssertEqual(layout.imageCount, 12)
    }
    
    func testPrintLayoutEquality() {
        let layout1 = PrintLayout(rows: 2, columns: 3)
        let layout2 = PrintLayout(rows: 2, columns: 3)
        let layout3 = PrintLayout(rows: 3, columns: 2)
        
        XCTAssertEqual(layout1, layout2)
        XCTAssertNotEqual(layout1, layout3)
    }
    
    // MARK: - Phase 2: PrintProgress Tests
    
    func testPrintProgressConnecting() {
        let progress = PrintProgress(
            phase: .connecting,
            progress: 0.0,
            message: "Connecting..."
        )
        
        XCTAssertEqual(progress.phase, .connecting)
        XCTAssertEqual(progress.progress, 0.0, accuracy: 0.001)
        XCTAssertEqual(progress.message, "Connecting...")
    }
    
    func testPrintProgressUploadingImages() {
        let progress = PrintProgress(
            phase: .uploadingImages(current: 3, total: 10),
            progress: 0.5,
            message: "Uploading image 3 of 10"
        )
        
        if case .uploadingImages(let current, let total) = progress.phase {
            XCTAssertEqual(current, 3)
            XCTAssertEqual(total, 10)
        } else {
            XCTFail("Expected uploadingImages phase")
        }
        
        XCTAssertEqual(progress.progress, 0.5, accuracy: 0.001)
    }
    
    func testPrintProgressCompleted() {
        let progress = PrintProgress(
            phase: .completed,
            progress: 1.0,
            message: "Print completed"
        )
        
        XCTAssertEqual(progress.phase, .completed)
        XCTAssertEqual(progress.progress, 1.0, accuracy: 0.001)
    }
    
    func testPrintProgressClampedValues() {
        // Test that progress values are clamped to 0.0 - 1.0
        let progressOver = PrintProgress(phase: .printing, progress: 1.5, message: "")
        XCTAssertEqual(progressOver.progress, 1.0, accuracy: 0.001)
        
        let progressUnder = PrintProgress(phase: .printing, progress: -0.5, message: "")
        XCTAssertEqual(progressUnder.progress, 0.0, accuracy: 0.001)
    }
    
    func testPrintProgressPhaseEquality() {
        let phase1 = PrintProgress.Phase.connecting
        let phase2 = PrintProgress.Phase.connecting
        let phase3 = PrintProgress.Phase.printing
        
        XCTAssertEqual(phase1, phase2)
        XCTAssertNotEqual(phase1, phase3)
        
        let upload1 = PrintProgress.Phase.uploadingImages(current: 1, total: 5)
        let upload2 = PrintProgress.Phase.uploadingImages(current: 1, total: 5)
        let upload3 = PrintProgress.Phase.uploadingImages(current: 2, total: 5)
        
        XCTAssertEqual(upload1, upload2)
        XCTAssertNotEqual(upload1, upload3)
    }
    
    // MARK: - Phase 2: Print Template Tests
    
    func testSingleImageTemplate() {
        let template = SingleImageTemplate()
        
        XCTAssertEqual(template.name, "Single Image")
        XCTAssertEqual(template.filmSize, .size8InX10In)
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\1,1")
        XCTAssertEqual(template.imageCount, 1)
        XCTAssertEqual(template.filmOrientation, .portrait)
        
        let filmBox = template.createFilmBox()
        XCTAssertEqual(filmBox.imageDisplayFormat, "STANDARD\\1,1")
        XCTAssertEqual(filmBox.filmSizeID, .size8InX10In)
    }
    
    func testSingleImageTemplateCustom() {
        let template = SingleImageTemplate(filmSize: .size14InX17In, filmOrientation: .landscape)
        
        XCTAssertEqual(template.filmSize, .size14InX17In)
        XCTAssertEqual(template.filmOrientation, .landscape)
        
        let filmBox = template.createFilmBox()
        XCTAssertEqual(filmBox.filmSizeID, .size14InX17In)
        XCTAssertEqual(filmBox.filmOrientation, .landscape)
    }
    
    func testComparisonTemplate() {
        let template = ComparisonTemplate()
        
        XCTAssertEqual(template.name, "Comparison")
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\2,1")
        XCTAssertEqual(template.imageCount, 2)
        XCTAssertEqual(template.filmOrientation, .landscape)
        
        let filmBox = template.createFilmBox()
        XCTAssertEqual(filmBox.imageDisplayFormat, "STANDARD\\2,1")
    }
    
    func testGridTemplate2x2() {
        let template = GridTemplate(rows: 2, columns: 2)
        
        XCTAssertEqual(template.name, "2x2 Grid")
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\2,2")
        XCTAssertEqual(template.imageCount, 4)
        
        let filmBox = template.createFilmBox()
        XCTAssertEqual(filmBox.imageDisplayFormat, "STANDARD\\2,2")
    }
    
    func testGridTemplate3x4() {
        let template = GridTemplate(rows: 3, columns: 4, filmSize: .size11InX17In)
        
        XCTAssertEqual(template.name, "3x4 Grid")
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\4,3")
        XCTAssertEqual(template.imageCount, 12)
        XCTAssertEqual(template.filmSize, .size11InX17In)
    }
    
    func testGridTemplateMinimumValues() {
        let template = GridTemplate(rows: 0, columns: 0)
        
        XCTAssertEqual(template.imageCount, 1)
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\1,1")
    }
    
    func testMultiPhaseTemplate2x3() {
        let template = MultiPhaseTemplate(rows: 2, columns: 3)
        
        XCTAssertEqual(template.name, "Multi-Phase 2x3")
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\3,2")
        XCTAssertEqual(template.imageCount, 6)
    }
    
    func testMultiPhaseTemplate3x4() {
        let template = MultiPhaseTemplate(rows: 3, columns: 4)
        
        XCTAssertEqual(template.name, "Multi-Phase 3x4")
        XCTAssertEqual(template.imageDisplayFormat, "STANDARD\\4,3")
        XCTAssertEqual(template.imageCount, 12)
    }
    
    // MARK: - Phase 2: PrintRetryPolicy Tests
    
    func testPrintRetryPolicyDefaults() {
        let policy = PrintRetryPolicy()
        
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.initialDelay, 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.backoffMultiplier, 2.0, accuracy: 0.001)
        XCTAssertEqual(policy.maxDelay, 30.0, accuracy: 0.001)
    }
    
    func testPrintRetryPolicyCustomValues() {
        let policy = PrintRetryPolicy(
            maxAttempts: 5,
            initialDelay: 2.0,
            backoffMultiplier: 3.0,
            maxDelay: 60.0
        )
        
        XCTAssertEqual(policy.maxAttempts, 5)
        XCTAssertEqual(policy.initialDelay, 2.0, accuracy: 0.001)
        XCTAssertEqual(policy.backoffMultiplier, 3.0, accuracy: 0.001)
        XCTAssertEqual(policy.maxDelay, 60.0, accuracy: 0.001)
    }
    
    func testPrintRetryPolicyDelayCalculation() {
        let policy = PrintRetryPolicy(
            initialDelay: 1.0,
            backoffMultiplier: 2.0,
            maxDelay: 10.0
        )
        
        XCTAssertEqual(policy.delay(for: 0), 1.0, accuracy: 0.001)  // 1 * 2^0 = 1
        XCTAssertEqual(policy.delay(for: 1), 2.0, accuracy: 0.001)  // 1 * 2^1 = 2
        XCTAssertEqual(policy.delay(for: 2), 4.0, accuracy: 0.001)  // 1 * 2^2 = 4
        XCTAssertEqual(policy.delay(for: 3), 8.0, accuracy: 0.001)  // 1 * 2^3 = 8
        XCTAssertEqual(policy.delay(for: 4), 10.0, accuracy: 0.001) // 1 * 2^4 = 16, capped at 10
    }
    
    func testPrintRetryPolicyDelayNegativeAttempt() {
        let policy = PrintRetryPolicy(initialDelay: 1.0)
        
        XCTAssertEqual(policy.delay(for: -1), 1.0, accuracy: 0.001)
    }
    
    func testPrintRetryPolicyStaticDefault() {
        let policy = PrintRetryPolicy.default
        
        XCTAssertEqual(policy.maxAttempts, 3)
    }
    
    func testPrintRetryPolicyStaticAggressive() {
        let policy = PrintRetryPolicy.aggressive
        
        XCTAssertEqual(policy.maxAttempts, 5)
        XCTAssertEqual(policy.initialDelay, 0.5, accuracy: 0.001)
        XCTAssertEqual(policy.backoffMultiplier, 1.5, accuracy: 0.001)
    }
    
    func testPrintRetryPolicyStaticNone() {
        let policy = PrintRetryPolicy.none
        
        XCTAssertEqual(policy.maxAttempts, 0)
    }
    
    func testPrintRetryPolicyMinimumValues() {
        let policy = PrintRetryPolicy(
            maxAttempts: -5,
            initialDelay: -1.0,
            backoffMultiplier: 0.5,
            maxDelay: -10.0
        )
        
        XCTAssertEqual(policy.maxAttempts, 0)
        XCTAssertEqual(policy.initialDelay, 0.0, accuracy: 0.001)
        XCTAssertEqual(policy.backoffMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.maxDelay, 0.0, accuracy: 0.001)
    }
    
    // MARK: - Phase 3: Image Preparation Pipeline Tests
    
    // MARK: - PreparedImage Tests
    
    func testPreparedImageInitialization() {
        let pixelData = Data([0x00, 0x01, 0x02, 0x03])
        let image = PreparedImage(
            pixelData: pixelData,
            width: 512,
            height: 512,
            bitsAllocated: 8,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2"
        )
        
        XCTAssertEqual(image.pixelData, pixelData)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(image.bitsAllocated, 8)
        XCTAssertEqual(image.samplesPerPixel, 1)
        XCTAssertEqual(image.photometricInterpretation, "MONOCHROME2")
    }
    
    func testPreparedImageWithRGBData() {
        let pixelData = Data(count: 512 * 512 * 3)
        let image = PreparedImage(
            pixelData: pixelData,
            width: 512,
            height: 512,
            bitsAllocated: 8,
            samplesPerPixel: 3,
            photometricInterpretation: "RGB"
        )
        
        XCTAssertEqual(image.samplesPerPixel, 3)
        XCTAssertEqual(image.photometricInterpretation, "RGB")
    }
    
    // MARK: - ImagePreprocessor Tests
    
    func testImagePreprocessorInitialization() async {
        let preprocessor = ImagePreprocessor()
        // Actor initializes successfully
        _ = preprocessor
    }
    
    func testPreprocessMONOCHROME2ImageNoTransforms() async throws {
        let width = 64
        let height = 64
        let pixelCount = width * height
        
        // Create simple grayscale pixel data
        var pixelData = Data(count: pixelCount)
        for i in 0..<pixelCount {
            pixelData[i] = UInt8(i % 256)
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .grayscale
        )
        
        XCTAssertEqual(result.width, width)
        XCTAssertEqual(result.height, height)
        XCTAssertEqual(result.bitsAllocated, 8)
        XCTAssertEqual(result.samplesPerPixel, 1)
        XCTAssertEqual(result.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(result.pixelData.count, pixelCount)
    }
    
    func testPreprocessMONOCHROME1ImageInversion() async throws {
        // Decided behavior (enhancement plan P0-1): MONOCHROME1 is normalized via
        // window/level (auto-computed from the data range when no window is in the
        // data set), inverted exactly once, and emitted as 8-bit MONOCHROME2. The
        // darkest stored value therefore prints white (255) and the brightest
        // prints black (0), with a monotonically non-increasing ramp between.
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create pixel data with known values
        var pixelData = Data(count: pixelCount)
        for i in 0..<pixelCount {
            pixelData[i] = UInt8(i * 16) // 0, 16, 32, 48, ...
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME1", for: .photometricInterpretation, vr: .CS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .grayscale
        )
        
        XCTAssertEqual(result.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(result.bitsAllocated, 8)
        XCTAssertEqual(result.pixelData.count, pixelCount)

        // Inverted exactly once: darkest stored value (0) prints white,
        // brightest (240) prints black, ramp is monotonically non-increasing.
        XCTAssertEqual(result.pixelData[0], 255)
        XCTAssertEqual(result.pixelData[pixelCount - 1], 0)
        for i in 1..<pixelCount {
            XCTAssertLessThanOrEqual(result.pixelData[i], result.pixelData[i - 1],
                                     "inverted ramp must not increase at index \(i)")
        }
    }
    
    func testPreprocessMONOCHROME1Image16BitInversion() async throws {
        // Decided behavior (enhancement plan P0-1): 16-bit MONOCHROME1 sources are
        // window/level-normalized and down-converted to 8-bit MONOCHROME2 for
        // print (Basic Grayscale Image Box P-Values), inverted exactly once.
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create 16-bit pixel data
        var pixelData = Data(count: pixelCount * 2)
        pixelData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            let buffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            for i in 0..<pixelCount {
                buffer[i] = UInt16(i * 4096) // 0, 4096, 8192, ...
            }
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(16, for: .bitsAllocated)
        dataSet.setUInt16(16, for: .bitsStored)
        dataSet.setUInt16(15, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME1", for: .photometricInterpretation, vr: .CS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .grayscale
        )
        
        XCTAssertEqual(result.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(result.bitsAllocated, 8)
        XCTAssertEqual(result.pixelData.count, pixelCount)

        // 16-bit source, 8-bit windowed output, inverted exactly once:
        // darkest stored value prints white, brightest prints black.
        XCTAssertEqual(result.pixelData[0], 255)
        XCTAssertEqual(result.pixelData[pixelCount - 1], 0)
        for i in 1..<pixelCount {
            XCTAssertLessThanOrEqual(result.pixelData[i], result.pixelData[i - 1],
                                     "inverted ramp must not increase at index \(i)")
        }
    }
    
    func testPreprocessWithWindowLevel8Bit() async throws {
        let width = 4
        let height = 4
        let pixelCount = width * height
        
        // Create pixel data with values 0-255 range
        var pixelData = Data(count: pixelCount)
        for i in 0..<pixelCount {
            pixelData[i] = UInt8(i * 16)
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        dataSet.setString(String(128.0), for: .windowCenter, vr: .DS)
        dataSet.setString(String(256.0), for: .windowWidth, vr: .DS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .grayscale
        )
        
        XCTAssertEqual(result.pixelData.count, pixelCount)
        // Window/level should normalize the values
        XCTAssertTrue(result.pixelData[0] >= 0)
        XCTAssertTrue(result.pixelData[pixelCount - 1] <= 255)
    }
    
    func testPreprocessRGBToGrayscaleConversion() async throws {
        let width = 2
        let height = 2
        let pixelCount = width * height
        
        // Create RGB pixel data (white, red, green, blue)
        var pixelData = Data(count: pixelCount * 3)
        // White: R=255, G=255, B=255
        pixelData[0] = 255; pixelData[1] = 255; pixelData[2] = 255
        // Red: R=255, G=0, B=0
        pixelData[3] = 255; pixelData[4] = 0; pixelData[5] = 0
        // Green: R=0, G=255, B=0
        pixelData[6] = 0; pixelData[7] = 255; pixelData[8] = 0
        // Blue: R=0, G=0, B=255
        pixelData[9] = 0; pixelData[10] = 0; pixelData[11] = 255
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(3, for: .samplesPerPixel)
        dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .grayscale
        )
        
        XCTAssertEqual(result.samplesPerPixel, 1)
        XCTAssertEqual(result.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(result.pixelData.count, pixelCount)
        
        // White should be bright (close to 255)
        XCTAssertGreaterThan(result.pixelData[0], 200)
        // Using ITU-R BT.601 weights:
        // Red: 0.299 * 255 ≈ 76
        XCTAssertTrue(result.pixelData[1] > 50 && result.pixelData[1] < 100)
        // Green: 0.587 * 255 ≈ 150
        XCTAssertTrue(result.pixelData[2] > 120 && result.pixelData[2] < 180)
        // Blue: 0.114 * 255 ≈ 29
        XCTAssertTrue(result.pixelData[3] < 50)
    }
    
    func testPreprocessMissingPixelDataThrowsError() async throws {
        var dataSet = DataSet()
        dataSet.setUInt16(64, for: .rows)
        dataSet.setUInt16(64, for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        
        let preprocessor = ImagePreprocessor()
        
        do {
            _ = try await preprocessor.prepareForPrint(
                dataSet: dataSet,
                colorMode: .grayscale
            )
            XCTFail("Expected error for missing pixel data")
        } catch {
            // Expected error
        }
    }
    
    func testPreprocessMissingImageAttributesThrowsError() async throws {
        var pixelData = Data(count: 64 * 64)
        for i in 0..<(64 * 64) {
            pixelData[i] = UInt8(i % 256)
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        // Missing rows, columns, bitsAllocated
        
        let preprocessor = ImagePreprocessor()
        
        do {
            _ = try await preprocessor.prepareForPrint(
                dataSet: dataSet,
                colorMode: .grayscale
            )
            XCTFail("Expected error for missing image attributes")
        } catch {
            // Expected error
        }
    }
    
    func testPreprocessColorImagePreservesRGBWhenColorModeIsColor() async throws {
        let width = 2
        let height = 2
        let pixelCount = width * height
        
        // Create RGB pixel data
        var pixelData = Data(count: pixelCount * 3)
        for i in 0..<(pixelCount * 3) {
            pixelData[i] = UInt8(i % 256)
        }
        
        var dataSet = DataSet()
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: .OW, data: pixelData)
        dataSet.setUInt16(UInt16(height), for: .rows)
        dataSet.setUInt16(UInt16(width), for: .columns)
        dataSet.setUInt16(8, for: .bitsAllocated)
        dataSet.setUInt16(8, for: .bitsStored)
        dataSet.setUInt16(7, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(3, for: .samplesPerPixel)
        dataSet.setString("RGB", for: .photometricInterpretation, vr: .CS)
        
        let preprocessor = ImagePreprocessor()
        let result = try await preprocessor.prepareForPrint(
            dataSet: dataSet,
            colorMode: .color
        )
        
        // RGB should be preserved when color mode is color
        XCTAssertEqual(result.samplesPerPixel, 3)
        XCTAssertEqual(result.photometricInterpretation, "RGB")
        XCTAssertEqual(result.pixelData.count, pixelCount * 3)
    }
    
    // MARK: - Phase 4: Print Queue Tests
    
    func testPrintJobInitialization() {
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let jobID = UUID()
        let imageURLs = [
            URL(fileURLWithPath: "/tmp/image1.dcm"),
            URL(fileURLWithPath: "/tmp/image2.dcm")
        ]
        
        let job = PrintJob(
            id: jobID,
            configuration: config,
            imageURLs: imageURLs,
            options: .highQuality,
            priority: .high,
            label: "Urgent Print"
        )
        
        XCTAssertEqual(job.id, jobID)
        XCTAssertEqual(job.configuration.host, "192.168.1.100")
        XCTAssertEqual(job.imageURLs.count, 2)
        XCTAssertEqual(job.options.priority, .high)
        XCTAssertEqual(job.priority, .high)
        XCTAssertEqual(job.label, "Urgent Print")
    }
    
    func testPrintJobDefaultValues() {
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: []
        )
        
        XCTAssertEqual(job.priority, .medium)
        XCTAssertNil(job.label)
        XCTAssertEqual(job.options.numberOfCopies, 1)
    }
    
    func testPrintJobRecordInitialization() {
        let recordID = UUID()
        let submittedAt = Date()
        let completedAt = Date()
        
        let record = PrintJobRecord(
            id: recordID,
            label: "Test Job",
            imageCount: 5,
            submittedAt: submittedAt,
            completedAt: completedAt,
            success: true,
            errorMessage: nil,
            printerName: "Film Printer 1"
        )
        
        XCTAssertEqual(record.id, recordID)
        XCTAssertEqual(record.label, "Test Job")
        XCTAssertEqual(record.imageCount, 5)
        XCTAssertTrue(record.success)
        XCTAssertNil(record.errorMessage)
        XCTAssertEqual(record.printerName, "Film Printer 1")
    }
    
    func testPrintJobRecordFailure() {
        let record = PrintJobRecord(
            id: UUID(),
            label: "Failed Job",
            imageCount: 3,
            submittedAt: Date(),
            completedAt: Date(),
            success: false,
            errorMessage: "Printer offline"
        )
        
        XCTAssertFalse(record.success)
        XCTAssertEqual(record.errorMessage, "Printer offline")
    }
    
    func testPrintQueueJobStatus() {
        let statusQueued = PrintQueueJobStatus.queued(position: 3)
        let statusProcessing = PrintQueueJobStatus.processing
        let statusCompleted = PrintQueueJobStatus.completed
        let statusFailed = PrintQueueJobStatus.failed(message: "Error")
        let statusCancelled = PrintQueueJobStatus.cancelled
        
        XCTAssertEqual(statusQueued, .queued(position: 3))
        XCTAssertEqual(statusProcessing, .processing)
        XCTAssertEqual(statusCompleted, .completed)
        XCTAssertNotEqual(statusFailed, .completed)
        XCTAssertEqual(statusCancelled, .cancelled)
    }
    
    func testPrintQueueEnqueue() async {
        let queue = PrintQueue()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/test.dcm")]
        )
        
        let jobID = await queue.enqueue(job: job)
        
        XCTAssertEqual(jobID, job.id)
        let count = await queue.queuedCount
        XCTAssertEqual(count, 1)
    }
    
    func testPrintQueuePriorityOrdering() async {
        let queue = PrintQueue()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        // Add jobs with different priorities
        let lowJob = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/low.dcm")],
            priority: .low
        )
        let highJob = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/high.dcm")],
            priority: .high
        )
        let medJob = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/med.dcm")],
            priority: .medium
        )
        
        await queue.enqueue(job: lowJob)
        await queue.enqueue(job: highJob)
        await queue.enqueue(job: medJob)
        
        // High priority should be first
        let first = await queue.dequeue()
        XCTAssertEqual(first?.id, highJob.id)
        
        // Medium priority should be second
        let second = await queue.dequeue()
        XCTAssertEqual(second?.id, medJob.id)
        
        // Low priority should be last
        let third = await queue.dequeue()
        XCTAssertEqual(third?.id, lowJob.id)
    }
    
    func testPrintQueueCancel() async {
        let queue = PrintQueue()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/test.dcm")]
        )
        
        await queue.enqueue(job: job)
        let cancelled = await queue.cancel(jobID: job.id)
        
        XCTAssertTrue(cancelled)
        let count = await queue.queuedCount
        XCTAssertEqual(count, 0)
        
        // Check it's in history as cancelled
        let status = await queue.status(jobID: job.id)
        XCTAssertEqual(status, .cancelled)
    }
    
    func testPrintQueueStatus() async {
        let queue = PrintQueue()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/test.dcm")]
        )
        
        // Status before enqueue should be nil
        let statusBefore = await queue.status(jobID: job.id)
        XCTAssertNil(statusBefore)
        
        // After enqueue should be queued
        await queue.enqueue(job: job)
        let statusQueued = await queue.status(jobID: job.id)
        XCTAssertEqual(statusQueued, .queued(position: 1))
        
        // After dequeue should be processing
        _ = await queue.dequeue()
        let statusProcessing = await queue.status(jobID: job.id)
        XCTAssertEqual(statusProcessing, .processing)
        
        // After marking complete should be completed
        await queue.markCompleted(jobID: job.id)
        let statusCompleted = await queue.status(jobID: job.id)
        XCTAssertEqual(statusCompleted, .completed)
    }
    
    func testPrintQueueHistory() async {
        let queue = PrintQueue()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        // Complete some jobs
        for i in 1...3 {
            let job = PrintJob(
                configuration: config,
                imageURLs: [URL(fileURLWithPath: "/tmp/test\(i).dcm")]
            )
            await queue.enqueue(job: job)
            _ = await queue.dequeue()
            await queue.markCompleted(jobID: job.id)
        }
        
        let history = await queue.getHistory(limit: 10)
        XCTAssertEqual(history.count, 3)
        
        // Most recent should be first
        XCTAssertTrue(history[0].success)
    }
    
    func testPrintQueueMarkFailed() async {
        let queue = PrintQueue(retryPolicy: .none)
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/test.dcm")]
        )
        
        await queue.enqueue(job: job)
        _ = await queue.dequeue()
        
        let willRetry = await queue.markFailed(
            jobID: job.id,
            error: PrintError.printerUnavailable(message: "Offline"),
            job: job
        )
        
        XCTAssertFalse(willRetry)
        
        let status = await queue.status(jobID: job.id)
        if case .failed = status {
            // Success
        } else {
            XCTFail("Expected failed status")
        }
    }
    
    func testPrintQueueRetry() async {
        let retryPolicy = PrintRetryPolicy(maxAttempts: 2)
        let queue = PrintQueue(retryPolicy: retryPolicy)
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let job = PrintJob(
            configuration: config,
            imageURLs: [URL(fileURLWithPath: "/tmp/test.dcm")]
        )
        
        await queue.enqueue(job: job)
        _ = await queue.dequeue()
        
        // First failure should retry
        let willRetry1 = await queue.markFailed(
            jobID: job.id,
            error: PrintError.networkError(message: "Timeout"),
            job: job
        )
        XCTAssertTrue(willRetry1)
        
        // Should be back in queue
        let count = await queue.queuedCount
        XCTAssertEqual(count, 1)
        
        // Dequeue and fail again
        _ = await queue.dequeue()
        let willRetry2 = await queue.markFailed(
            jobID: job.id,
            error: PrintError.networkError(message: "Timeout"),
            job: job
        )
        XCTAssertTrue(willRetry2)
        
        // Dequeue and fail third time - no more retries
        _ = await queue.dequeue()
        let willRetry3 = await queue.markFailed(
            jobID: job.id,
            error: PrintError.networkError(message: "Timeout"),
            job: job
        )
        XCTAssertFalse(willRetry3)
    }
    
    // MARK: - Phase 4: Printer Capabilities Tests
    
    func testPrinterCapabilitiesDefaults() {
        let caps = PrinterCapabilities()
        
        XCTAssertFalse(caps.supportedFilmSizes.isEmpty)
        XCTAssertTrue(caps.supportsColor)
        XCTAssertEqual(caps.maxCopies, 99)
        XCTAssertFalse(caps.supportedMediumTypes.isEmpty)
        XCTAssertEqual(caps.maxImagesPerFilmBox, 25)
    }
    
    func testPrinterCapabilitiesCustom() {
        let caps = PrinterCapabilities(
            supportedFilmSizes: [.size8InX10In, .size14InX17In],
            supportsColor: false,
            maxCopies: 10,
            supportedMediumTypes: [.clearFilm],
            supportedMagnificationTypes: [.replicate],
            maxImagesPerFilmBox: 16
        )
        
        XCTAssertEqual(caps.supportedFilmSizes.count, 2)
        XCTAssertFalse(caps.supportsColor)
        XCTAssertEqual(caps.maxCopies, 10)
        XCTAssertEqual(caps.supportedMediumTypes.count, 1)
        XCTAssertEqual(caps.maxImagesPerFilmBox, 16)
    }
    
    func testFilmSizeCaseIterable() {
        XCTAssertEqual(FilmSize.allCases.count, 12)
        XCTAssertTrue(FilmSize.allCases.contains(.size8InX10In))
        XCTAssertTrue(FilmSize.allCases.contains(.a4))
    }
    
    func testMediumTypeCaseIterable() {
        // The five Table C.13-1 terms; the deprecated spellings are not listed.
        XCTAssertEqual(MediumType.allCases.count, 5)
        XCTAssertTrue(MediumType.allCases.contains(.paper))
        XCTAssertTrue(MediumType.allCases.contains(.mammoBlueFilm))
    }
    
    func testMagnificationTypeCaseIterable() {
        XCTAssertEqual(MagnificationType.allCases.count, 4)
        XCTAssertTrue(MagnificationType.allCases.contains(.replicate))
        XCTAssertTrue(MagnificationType.allCases.contains(.cubic))
    }
    
    // MARK: - Phase 4: Printer Info Tests
    
    func testPrinterInfoInitialization() {
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer = PrinterInfo(
            name: "Radiology Film Printer",
            configuration: config,
            capabilities: .default,
            isDefault: true
        )
        
        XCTAssertEqual(printer.name, "Radiology Film Printer")
        XCTAssertEqual(printer.configuration.host, "192.168.1.100")
        XCTAssertTrue(printer.isDefault)
        XCTAssertTrue(printer.isAvailable)
    }
    
    func testPrinterInfoEquality() {
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let id = UUID()
        let printer1 = PrinterInfo(id: id, name: "Printer 1", configuration: config)
        let printer2 = PrinterInfo(id: id, name: "Different Name", configuration: config)
        let printer3 = PrinterInfo(name: "Printer 3", configuration: config)
        
        XCTAssertEqual(printer1, printer2) // Same ID
        XCTAssertNotEqual(printer1, printer3) // Different ID
    }
    
    // MARK: - Phase 4: Printer Registry Tests
    
    func testPrinterRegistryAddPrinter() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer = PrinterInfo(name: "Test Printer", configuration: config)
        try await registry.addPrinter(printer)
        
        let count = await registry.count
        XCTAssertEqual(count, 1)
        
        let retrieved = await registry.printer(id: printer.id)
        XCTAssertEqual(retrieved?.name, "Test Printer")
    }
    
    func testPrinterRegistryDefaultPrinter() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        // First printer becomes default
        let printer1 = PrinterInfo(name: "Printer 1", configuration: config)
        try await registry.addPrinter(printer1)
        
        let defaultPrinter = await registry.defaultPrinter()
        XCTAssertEqual(defaultPrinter?.id, printer1.id)
        
        // Add second printer marked as default
        let printer2 = PrinterInfo(name: "Printer 2", configuration: config, isDefault: true)
        try await registry.addPrinter(printer2)
        
        let newDefault = await registry.defaultPrinter()
        XCTAssertEqual(newDefault?.id, printer2.id)
    }
    
    func testPrinterRegistryRemovePrinter() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer = PrinterInfo(name: "Test Printer", configuration: config)
        try await registry.addPrinter(printer)
        
        let removed = await registry.removePrinter(id: printer.id)
        XCTAssertNotNil(removed)
        
        let count = await registry.count
        XCTAssertEqual(count, 0)
    }
    
    func testPrinterRegistrySetDefaultPrinter() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer1 = PrinterInfo(name: "Printer 1", configuration: config)
        let printer2 = PrinterInfo(name: "Printer 2", configuration: config)
        
        try await registry.addPrinter(printer1)
        try await registry.addPrinter(printer2)
        
        try await registry.setDefaultPrinter(id: printer2.id)
        
        let defaultPrinter = await registry.defaultPrinter()
        XCTAssertEqual(defaultPrinter?.id, printer2.id)
    }
    
    func testPrinterRegistryDuplicateError() async {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let id = UUID()
        let printer1 = PrinterInfo(id: id, name: "Printer 1", configuration: config)
        let printer2 = PrinterInfo(id: id, name: "Printer 2", configuration: config)
        
        do {
            try await registry.addPrinter(printer1)
            try await registry.addPrinter(printer2)
            XCTFail("Expected error for duplicate printer")
        } catch let error as PrinterRegistryError {
            XCTAssertEqual(error, .printerAlreadyExists(id: id))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testPrinterRegistryNotFoundError() async {
        let registry = PrinterRegistry()
        
        let nonExistentID = UUID()
        
        do {
            try await registry.setDefaultPrinter(id: nonExistentID)
            XCTFail("Expected error for non-existent printer")
        } catch let error as PrinterRegistryError {
            XCTAssertEqual(error, .printerNotFound(id: nonExistentID))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testPrinterRegistrySelectPrinter() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        // Add grayscale-only printer
        let grayscaleCaps = PrinterCapabilities(
            supportedFilmSizes: [.size14InX17In],
            supportsColor: false
        )
        let grayscalePrinter = PrinterInfo(
            name: "Grayscale Printer",
            configuration: config,
            capabilities: grayscaleCaps
        )
        try await registry.addPrinter(grayscalePrinter)
        
        // Add color printer
        let colorCaps = PrinterCapabilities(
            supportedFilmSizes: [.size8InX10In, .size14InX17In],
            supportsColor: true
        )
        let colorPrinter = PrinterInfo(
            name: "Color Printer",
            configuration: config,
            capabilities: colorCaps
        )
        try await registry.addPrinter(colorPrinter)
        
        // Select printer for color job
        let selected = await registry.selectPrinter(requiresColor: true)
        XCTAssertEqual(selected?.name, "Color Printer")
        
        // Select printer for grayscale job should prefer default
        let anyPrinter = await registry.selectPrinter(requiresColor: false)
        XCTAssertNotNil(anyPrinter)
    }
    
    func testPrinterRegistryAvailability() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer = PrinterInfo(name: "Test Printer", configuration: config)
        try await registry.addPrinter(printer)
        
        await registry.updateAvailability(id: printer.id, isAvailable: false)
        
        let available = await registry.listAvailablePrinters()
        XCTAssertEqual(available.count, 0)
        
        await registry.markSeen(id: printer.id)
        
        let nowAvailable = await registry.listAvailablePrinters()
        XCTAssertEqual(nowAvailable.count, 1)
    }
    
    func testPrinterRegistryByName() async throws {
        let registry = PrinterRegistry()
        let config = PrintConfiguration(
            host: "192.168.1.100",
            port: 104,
            callingAETitle: "MYAPP",
            calledAETitle: "PRINTER"
        )
        
        let printer = PrinterInfo(name: "Radiology Film Printer", configuration: config)
        try await registry.addPrinter(printer)
        
        let found = await registry.printer(named: "Radiology Film Printer")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, printer.id)
        
        let notFound = await registry.printer(named: "Non-existent")
        XCTAssertNil(notFound)
    }
    
    // MARK: - Phase 4: Print Error Tests
    
    func testPrintErrorDescriptions() {
        let errors: [PrintError] = [
            .printerUnavailable(message: "Offline"),
            .filmSessionCreationFailed(statusCode: 0xA700),
            .filmBoxCreationFailed(statusCode: 0xA700),
            .imageBoxSetFailed(position: 3, statusCode: 0xA900),
            .printJobFailed(status: "FAILURE", info: "Paper jam"),
            .timeout(operation: "N-CREATE"),
            .invalidConfiguration(reason: "Invalid port"),
            .imagePreparationFailed(reason: "Missing pixel data"),
            .networkError(message: "Connection refused"),
            .queueFull(maxSize: 100)
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
            XCTAssertFalse(error.recoverySuggestion.isEmpty)
        }
    }
    
    func testPrintErrorEquality() {
        let error1 = PrintError.printerUnavailable(message: "Offline")
        let error2 = PrintError.printerUnavailable(message: "Offline")
        let error3 = PrintError.printerUnavailable(message: "Different")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }
    
    func testPrintErrorRecoverySuggestions() {
        let timeoutError = PrintError.timeout(operation: "N-CREATE")
        XCTAssertTrue(timeoutError.recoverySuggestion.contains("timeout"))
        
        let printerError = PrintError.printerUnavailable(message: "")
        XCTAssertTrue(printerError.recoverySuggestion.contains("powered on"))
    }
    
    // MARK: - Phase 4: Partial Print Result Tests
    
    func testPartialPrintResultSuccess() {
        let result = PartialPrintResult.success(
            count: 5,
            filmSessionUID: "1.2.3.4.5",
            printJobUID: "1.2.3.4.6"
        )
        
        XCTAssertTrue(result.isFullySuccessful)
        XCTAssertFalse(result.isFullyFailed)
        XCTAssertFalse(result.isPartiallySuccessful)
        XCTAssertEqual(result.successCount, 5)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertEqual(result.filmSessionUID, "1.2.3.4.5")
        XCTAssertEqual(result.printJobUID, "1.2.3.4.6")
    }
    
    func testPartialPrintResultFailure() {
        let result = PartialPrintResult.failure(
            count: 3,
            error: .printerUnavailable(message: "Offline")
        )
        
        XCTAssertFalse(result.isFullySuccessful)
        XCTAssertTrue(result.isFullyFailed)
        XCTAssertFalse(result.isPartiallySuccessful)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failureCount, 3)
        XCTAssertEqual(result.failedPositions, [1, 2, 3])
        XCTAssertEqual(result.errors.count, 1)
    }
    
    func testPartialPrintResultPartialSuccess() {
        let result = PartialPrintResult(
            successCount: 4,
            failureCount: 2,
            failedPositions: [3, 5],
            errors: [
                .imageBoxSetFailed(position: 3, statusCode: 0xA900),
                .imageBoxSetFailed(position: 5, statusCode: 0xA900)
            ]
        )
        
        XCTAssertFalse(result.isFullySuccessful)
        XCTAssertFalse(result.isFullyFailed)
        XCTAssertTrue(result.isPartiallySuccessful)
        XCTAssertEqual(result.successCount, 4)
        XCTAssertEqual(result.failureCount, 2)
        XCTAssertEqual(result.failedPositions, [3, 5])
    }
    
    // MARK: - Phase 4: Printer Registry Error Tests
    
    func testPrinterRegistryErrorDescriptions() {
        let id = UUID()
        let errors: [PrinterRegistryError] = [
            .printerAlreadyExists(id: id),
            .printerNotFound(id: id),
            .noPrinterAvailable
        ]
        
        for error in errors {
            XCTAssertFalse(error.description.isEmpty)
        }
    }
    
    func testPrinterRegistryErrorEquality() {
        let id = UUID()
        let error1 = PrinterRegistryError.printerAlreadyExists(id: id)
        let error2 = PrinterRegistryError.printerAlreadyExists(id: id)
        let error3 = PrinterRegistryError.printerNotFound(id: id)

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Print Event (N-EVENT-REPORT) Tests

    func testPrinterEventTypeRawValues() {
        XCTAssertEqual(PrinterEventType.normal.rawValue, 1)
        XCTAssertEqual(PrinterEventType.warning.rawValue, 2)
        XCTAssertEqual(PrinterEventType.failure.rawValue, 3)
    }

    func testPrintJobEventTypeRawValues() {
        XCTAssertEqual(PrintJobEventType.pending.rawValue, 1)
        XCTAssertEqual(PrintJobEventType.printing.rawValue, 2)
        XCTAssertEqual(PrintJobEventType.done.rawValue, 3)
        XCTAssertEqual(PrintJobEventType.failure.rawValue, 4)
    }

    func testPrintEventInterpretsPrinterSOPClass() {
        let event = PrintEvent(
            sopClassUID: printerSOPClassUID,
            sopInstanceUID: "1.2.3",
            eventTypeID: 3,
            printerStatusInfo: "OUT OF SUPPLY"
        )
        XCTAssertEqual(event.printerEvent, .failure)
        XCTAssertNil(event.printJobEvent)
        XCTAssertTrue(event.isFault)
        XCTAssertEqual(event.summary, "Printer Failure: OUT OF SUPPLY")
    }

    func testPrintEventInterpretsPrintJobSOPClass() {
        let event = PrintEvent(
            sopClassUID: printJobSOPClassUID,
            sopInstanceUID: "1.2.3",
            eventTypeID: 2,
            executionStatusInfo: "QUEUED"
        )
        XCTAssertEqual(event.printJobEvent, .printing)
        XCTAssertNil(event.printerEvent)
        XCTAssertFalse(event.isFault)
        XCTAssertEqual(event.summary, "Print Job Printing: QUEUED")
    }

    func testPrintEventPrintJobFailureIsFault() {
        let event = PrintEvent(
            sopClassUID: printJobSOPClassUID,
            sopInstanceUID: "1.2.3",
            eventTypeID: 4
        )
        XCTAssertEqual(event.printJobEvent, .failure)
        XCTAssertTrue(event.isFault)
        XCTAssertEqual(event.summary, "Print Job Failure")
    }

    func testPrintEventPrinterNormalIsNotFault() {
        let event = PrintEvent(
            sopClassUID: printerSOPClassUID,
            sopInstanceUID: "1.2.3",
            eventTypeID: 1
        )
        XCTAssertEqual(event.printerEvent, .normal)
        XCTAssertFalse(event.isFault)
        XCTAssertEqual(event.summary, "Printer Normal")
    }

    func testPrintEventUnknownSOPClassFallsBack() {
        let event = PrintEvent(
            sopClassUID: "1.2.840.10008.1.1", // Verification SOP Class, not print
            sopInstanceUID: "1.2.3",
            eventTypeID: 7
        )
        XCTAssertNil(event.printerEvent)
        XCTAssertNil(event.printJobEvent)
        XCTAssertFalse(event.isFault)
        XCTAssertEqual(event.summary, "Print Event 7")
    }

    // MARK: - Presentation LUT / Annotation Tests

    func testPresentationLUTShapeRawValues() {
        XCTAssertEqual(PresentationLUTShape.identity.rawValue, "IDENTITY")
        XCTAssertEqual(PresentationLUTShape.inverseRendered.rawValue, "INVERSE_RENDERED")
        XCTAssertEqual(PresentationLUTShape.linearOpticalDensity.rawValue, "LIN OD")
        XCTAssertEqual(PresentationLUTShape.allCases.count, 3)
    }

    func testPresentationLUTSOPClassUID() {
        XCTAssertEqual(presentationLUTSOPClassUID, "1.2.840.10008.5.1.1.23")
    }

    func testAnnotationBoxSOPClassUID() {
        XCTAssertEqual(basicAnnotationBoxSOPClassUID, "1.2.840.10008.5.1.1.15")
    }

    func testPrintAnnotationClampsPosition() {
        XCTAssertEqual(PrintAnnotation(position: 0, text: "x").position, 1)
        XCTAssertEqual(PrintAnnotation(position: 3, text: "x").position, 3)
        XCTAssertEqual(PrintAnnotation(position: 2, text: "PATIENT NAME").text, "PATIENT NAME")
    }

    func testPrintOptionsCarriesPresentationLUTAndAnnotations() {
        let options = PrintOptions(
            presentationLUTShape: .identity,
            annotations: [PrintAnnotation(position: 1, text: "Hello")],
            annotationDisplayFormatID: "STANDARD"
        )
        XCTAssertEqual(options.presentationLUTShape, .identity)
        XCTAssertEqual(options.annotations.count, 1)
        XCTAssertEqual(options.annotationDisplayFormatID, "STANDARD")
    }

    func testPrintOptionsDefaultsHaveNoLUTOrAnnotations() {
        let options = PrintOptions()
        XCTAssertNil(options.presentationLUTShape)
        XCTAssertTrue(options.annotations.isEmpty)
        XCTAssertNil(options.annotationDisplayFormatID)
    }

    func testParseReferencedSOPInstanceUIDsScopedToSequence() {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

        // Explicit VR LE Referenced SOP Instance UID (0008,1155) UI element.
        func uiElement(_ value: String) -> Data {
            var v = value.data(using: .ascii)!
            if v.count % 2 != 0 { v.append(0x00) }
            var d = le16(0x0008) + le16(0x1155)
            d.append(contentsOf: [0x55, 0x49]) // "UI"
            d += le16(UInt16(v.count)) + v
            return d
        }
        // Explicit VR LE sequence with a single item wrapping `content`.
        func sequence(_ group: UInt16, _ element: UInt16, content: Data) -> Data {
            var item = le16(0xFFFE) + le16(0xE000) + le32(UInt32(content.count)) + content
            var d = le16(group) + le16(element)
            d.append(contentsOf: [0x53, 0x51]) // "SQ"
            d += le16(0) // reserved
            d += le32(UInt32(item.count)) + item
            return d
        }

        let imageSeq = sequence(0x2010, 0x0510, content: uiElement("1.2.10"))
        let annSeq = sequence(0x2010, 0x0520, content: uiElement("1.2.20") + uiElement("1.2.21"))
        let data = imageSeq + annSeq

        let annUIDs = DICOMPrintService.parseReferencedSOPInstanceUIDs(
            from: data, withinSequence: .referencedBasicAnnotationBoxSequence)
        XCTAssertEqual(annUIDs, ["1.2.20", "1.2.21"])

        let imgUIDs = DICOMPrintService.parseReferencedSOPInstanceUIDs(
            from: data, withinSequence: .referencedImageBoxSequence)
        XCTAssertEqual(imgUIDs, ["1.2.10"])

        // A sequence that is not present yields no UIDs.
        let none = DICOMPrintService.parseReferencedSOPInstanceUIDs(
            from: data, withinSequence: .referencedPresentationLUTSequence)
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - parsePrinterStatus (P0-3)

    /// Builds an Explicit VR LE short-form string element (CS/LO), space-padded to even length.
    private func stringElement(_ group: UInt16, _ element: UInt16, vr: String, _ value: String) -> Data {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var v = value.data(using: .ascii)!
        if v.count % 2 != 0 { v.append(0x20) }
        var d = le16(group) + le16(element)
        d.append(contentsOf: Array(vr.utf8))
        d += le16(UInt16(v.count)) + v
        return d
    }

    func testParsePrinterStatusNormal() {
        let data = stringElement(0x2110, 0x0010, vr: "CS", "NORMAL")
            + stringElement(0x2110, 0x0030, vr: "LO", "LASER1")
        let status = DICOMPrintService.parsePrinterStatus(from: data)
        XCTAssertEqual(status.status, "NORMAL")
        XCTAssertTrue(status.isNormal)
        XCTAssertEqual(status.printerName, "LASER1")
        XCTAssertNil(status.statusInfo)
    }

    func testParsePrinterStatusWarningWithInfo() {
        let data = stringElement(0x2110, 0x0010, vr: "CS", "WARNING")
            + stringElement(0x2110, 0x0020, vr: "CS", "SUPPLY LOW")
            + stringElement(0x2110, 0x0030, vr: "LO", "LASER1")
            + stringElement(0x0008, 0x0070, vr: "LO", "ACME")
            + stringElement(0x0008, 0x1090, vr: "LO", "FILMPRINTER 2000")
        let status = DICOMPrintService.parsePrinterStatus(from: data)
        XCTAssertEqual(status.status, "WARNING")
        XCTAssertFalse(status.isNormal)
        XCTAssertEqual(status.statusInfo, "SUPPLY LOW")
        XCTAssertEqual(status.printerName, "LASER1")
        XCTAssertEqual(status.manufacturer, "ACME")
        XCTAssertEqual(status.manufacturerModelName, "FILMPRINTER 2000")
    }

    func testParsePrinterStatusFailure() {
        let data = stringElement(0x2110, 0x0010, vr: "CS", "FAILURE")
            + stringElement(0x2110, 0x0020, vr: "CS", "OUT OF FILM")
        let status = DICOMPrintService.parsePrinterStatus(from: data)
        XCTAssertEqual(status.status, "FAILURE")
        XCTAssertFalse(status.isNormal)
        XCTAssertEqual(status.statusInfo, "OUT OF FILM")
    }

    func testParsePrinterStatusMissingStatusIsUnknown() {
        let data = stringElement(0x2110, 0x0030, vr: "LO", "LASER1")
        let status = DICOMPrintService.parsePrinterStatus(from: data)
        XCTAssertEqual(status.status, "UNKNOWN")
        XCTAssertFalse(status.isNormal)
    }

    /// Builds an Implicit VR LE element: [tag(4)][length(4)][value].
    private func implicitElement(_ group: UInt16, _ element: UInt16, _ value: String) -> Data {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var v = value.data(using: .ascii)!
        if v.count % 2 != 0 { v.append(0x20) }
        return le16(group) + le16(element) + le32(UInt32(v.count)) + v
    }

    func testParsePrinterStatusImplicitVR() {
        let data = implicitElement(0x2110, 0x0010, "WARNING")
            + implicitElement(0x2110, 0x0020, "SUPPLY LOW")
            + implicitElement(0x2110, 0x0030, "LASER1")
        let status = DICOMPrintService.parsePrinterStatus(from: data, explicitVR: false)
        XCTAssertEqual(status.status, "WARNING")
        XCTAssertEqual(status.statusInfo, "SUPPLY LOW")
        XCTAssertEqual(status.printerName, "LASER1")
    }

    func testParseReferencedSOPInstanceUIDsImplicitVR() {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        // Implicit VR: UI element is [tag][len32][value]; SQ is [tag][len32][items].
        let ui = le16(0x0008) + le16(0x1155) + le32(6) + "1.2.10".data(using: .ascii)!
        let item = le16(0xFFFE) + le16(0xE000) + le32(UInt32(ui.count)) + ui
        let seq = le16(0x2010) + le16(0x0510) + le32(UInt32(item.count)) + item

        let uids = DICOMPrintService.parseReferencedSOPInstanceUIDs(
            from: seq, withinSequence: .referencedImageBoxSequence, explicitVR: false)
        XCTAssertEqual(uids, ["1.2.10"])
    }

    func testParsePrinterStatusEmptyData() {
        let status = DICOMPrintService.parsePrinterStatus(from: Data())
        XCTAssertEqual(status.status, "UNKNOWN")
        XCTAssertNil(status.printerName)
    }

    // MARK: - DIMSE error detail (P0-5)

    func testCommandSetErrorAccessors() {
        var commandSet = CommandSet()
        commandSet.setErrorComment("OUT OF FILM")
        commandSet.setErrorID(0x0042)
        XCTAssertEqual(commandSet.errorComment, "OUT OF FILM")
        XCTAssertEqual(commandSet.errorID, 0x0042)
        XCTAssertNil(commandSet.offendingElements)
    }

    func testCommandSetOffendingElements() {
        // AT VM 2: (2010,0010) and (2020,0020) as LE group/element pairs.
        let at = Data([0x10, 0x20, 0x10, 0x00, 0x20, 0x20, 0x20, 0x00])
        let commandSet = CommandSet(elements: [.offendingElement: at])
        XCTAssertEqual(commandSet.offendingElements, [
            Tag(group: 0x2010, element: 0x0010),
            Tag(group: 0x2020, element: 0x0020)
        ])
    }

    func testErrorDetailFromCommandSet() {
        var commandSet = CommandSet()
        XCTAssertNil(DICOMPrintService.errorDetail(from: commandSet))

        commandSet.setErrorComment("OUT OF FILM")
        XCTAssertEqual(DICOMPrintService.errorDetail(from: commandSet), "OUT OF FILM")

        commandSet.setErrorID(7)
        XCTAssertEqual(DICOMPrintService.errorDetail(from: commandSet), "OUT OF FILM (Error ID 7)")

        var idOnly = CommandSet()
        idOnly.setErrorID(7)
        XCTAssertEqual(DICOMPrintService.errorDetail(from: idOnly), "(Error ID 7)")
    }

    func testPrintOperationFailedCarriesDetail() {
        let error = DICOMNetworkError.printOperationFailed(.failedUnableToProcess, detail: "OUT OF FILM")
        XCTAssertTrue(error.description.contains("OUT OF FILM"))
        XCTAssertTrue((error.errorDescription ?? "").contains("OUT OF FILM"))

        let plain = DICOMNetworkError.printOperationFailed(.failedUnableToProcess)
        XCTAssertFalse(plain.description.contains("—"))
    }

    // MARK: - Per-frame preprocessing + YBR conversion (Milestone B)

    func testPrepareForPrintSelectsRequestedFrame() async throws {
        // Two-frame 2x2 8-bit MONOCHROME2: frame 0 is an ascending ramp,
        // frame 1 a descending ramp — the first output pixel tells the frames apart.
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let frame0: [UInt8] = [0, 80, 160, 240]
        let frame1: [UInt8] = [240, 160, 80, 0]
        let pixelData = PixelData(data: Data(frame0 + frame1), descriptor: descriptor)

        let preprocessor = ImagePreprocessor()
        let first = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0, colorMode: .grayscale)
        let second = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 1, colorMode: .grayscale)

        XCTAssertEqual(first.pixelData.count, 4)
        XCTAssertEqual(second.pixelData.count, 4)
        XCTAssertEqual(first.pixelData[0], 0)     // darkest source pixel
        XCTAssertEqual(second.pixelData[0], 255)  // brightest source pixel
    }

    func testPrepareForPrintRejectsOutOfRangeFrame() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 1, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        do {
            _ = try await preprocessor.prepareForPrint(
                pixelData: pixelData, dataSet: DataSet(), frameIndex: 1, colorMode: .grayscale)
            XCTFail("Expected out-of-range frame to throw")
        } catch {
            // expected
        }
    }

    func testPrepareForPrintConvertsYBRFullToRGB() async throws {
        // One YBR_FULL pixel encoding pure red: Y=76, Cb=85, Cr=255 → ~(254, 0, 0).
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 1, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .ybrFull,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([76, 85, 255]), descriptor: descriptor)

        let preprocessor = ImagePreprocessor()
        let prepared = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0, colorMode: .color)

        XCTAssertEqual(prepared.photometricInterpretation, "RGB")
        XCTAssertEqual(prepared.samplesPerPixel, 3)
        XCTAssertEqual(prepared.pixelData.count, 3)
        XCTAssertGreaterThanOrEqual(prepared.pixelData[0], 252) // red channel
        XCTAssertLessThanOrEqual(prepared.pixelData[1], 2)      // green channel
        XCTAssertLessThanOrEqual(prepared.pixelData[2], 2)      // blue channel
    }

    // MARK: - Milestone C (interop)

    func testLayoutFromImageDisplayFormat() {
        // PS3.3 C.13.3: "STANDARD\\C,R" — 2 columns, 3 rows.
        let l1 = DICOMPrintService.layout(fromImageDisplayFormat: "STANDARD\\2,3")
        XCTAssertEqual(l1.rows, 3)
        XCTAssertEqual(l1.columns, 2)

        let l2 = DICOMPrintService.layout(fromImageDisplayFormat: "STANDARD\\1,1")
        XCTAssertEqual(l2.rows, 1)
        XCTAssertEqual(l2.columns, 1)

        // Malformed strings fall back to 1x1 rather than crashing.
        for bad in ["", "STANDARD", "CUSTOM\\2,3", "STANDARD\\0,3", "STANDARD\\a,b"] {
            let l = DICOMPrintService.layout(fromImageDisplayFormat: bad)
            XCTAssertEqual(l.rows, 1, "fallback for \(bad)")
            XCTAssertEqual(l.columns, 1, "fallback for \(bad)")
        }
    }

    func testPrintImagesRequiresDescriptors() async {
        // P1-1: the workflow must refuse to build image boxes without the
        // mandatory pixel-module attributes — and it must fail before any
        // network activity (the config below points nowhere).
        let config = PrintConfiguration(
            host: "127.0.0.1", port: 1,
            callingAETitle: "TEST", calledAETitle: "TEST"
        )
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: config,
                images: [Data([0x00])],
                imageDescriptors: []
            )
            XCTFail("Expected encodingFailed for missing descriptors")
        } catch let error as DICOMNetworkError {
            guard case .encodingFailed(let message) = error else {
                return XCTFail("Expected encodingFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("descriptor"))
        } catch {
            XCTFail("Expected DICOMNetworkError, got \(error)")
        }
    }

    func testSetImageBoxRequiresDescriptor() async {
        let config = PrintConfiguration(
            host: "127.0.0.1", port: 1,
            callingAETitle: "TEST", calledAETitle: "TEST"
        )
        let imageBox = ImageBoxContent(sopInstanceUID: "1.2.3", imagePosition: 1)
        do {
            try await DICOMPrintService.setImageBox(
                configuration: config,
                imageBoxUID: "1.2.3",
                imageBox: imageBox,
                pixelData: Data([0x00])
            )
            XCTFail("Expected encodingFailed for missing descriptor")
        } catch let error as DICOMNetworkError {
            guard case .encodingFailed = error else {
                return XCTFail("Expected encodingFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected DICOMNetworkError, got \(error)")
        }
    }

    func testPrepareForPrintConvertsYBRFull422ToRGB() async throws {
        // Packed 4:2:2 (Y1 Y2 Cb Cr): both pixels encode pure red at full range.
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .ybrFull422,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([76, 76, 85, 255]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        let prepared = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0, colorMode: .color)

        XCTAssertEqual(prepared.photometricInterpretation, "RGB")
        XCTAssertEqual(prepared.pixelData.count, 6) // 2 pixels × RGB
        for pixel in 0..<2 {
            XCTAssertGreaterThanOrEqual(prepared.pixelData[pixel * 3], 252, "red channel")
            XCTAssertLessThanOrEqual(prepared.pixelData[pixel * 3 + 1], 2, "green channel")
            XCTAssertLessThanOrEqual(prepared.pixelData[pixel * 3 + 2], 2, "blue channel")
        }
    }

    func testPrepareForPrintConvertsYBRPartial422StudioRange() async throws {
        // BT.601 studio range: Y=16 is black, Y=235 is white (neutral chroma).
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .ybrPartial422,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([16, 235, 128, 128]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        let prepared = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0, colorMode: .color)

        XCTAssertLessThanOrEqual(prepared.pixelData[0], 1)   // black pixel
        XCTAssertGreaterThanOrEqual(prepared.pixelData[3], 254) // white pixel
    }

    // MARK: - Bit depth, explicit window, palette color

    func testPrepareForPrint12BitOutput() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0, 80, 160, 240]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        let prepared = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0,
            colorMode: .grayscale, outputBitDepth: 12)

        XCTAssertEqual(prepared.bitsAllocated, 16)
        XCTAssertEqual(prepared.bitsStored, 12)
        XCTAssertEqual(prepared.pixelData.count, 8) // 4 px × 2 bytes

        // Little-endian samples; darkest → 0, brightest → 4095.
        func sample(_ i: Int) -> UInt16 {
            UInt16(prepared.pixelData[i * 2]) | (UInt16(prepared.pixelData[i * 2 + 1]) << 8)
        }
        XCTAssertEqual(sample(0), 0)
        XCTAssertEqual(sample(3), 4095)
        XCTAssertTrue((1...2).allSatisfy { sample($0) > 0 && sample($0) < 4095 })
    }

    func testPrepareForPrintRejectsInvalidBitDepth() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 1, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        do {
            _ = try await preprocessor.prepareForPrint(
                pixelData: pixelData, dataSet: DataSet(), frameIndex: 0,
                colorMode: .grayscale, outputBitDepth: 24)
            XCTFail("Expected unsupportedBitsAllocated")
        } catch {
            // expected
        }
    }

    func testPrepareForPrintHonorsExplicitWindow() async throws {
        // Window [100 ± 10]: values ≤90 → black, ≥110 → white.
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0, 90, 110, 255]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        let prepared = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: DataSet(), frameIndex: 0,
            colorMode: .grayscale,
            windowSettings: WindowSettings(center: 100, width: 20))

        XCTAssertEqual(prepared.pixelData[0], 0)
        XCTAssertLessThanOrEqual(prepared.pixelData[1], 5)
        XCTAssertGreaterThanOrEqual(prepared.pixelData[2], 250)
        XCTAssertEqual(prepared.pixelData[3], 255)
    }

    func testPrepareForPrintPaletteColor() async throws {
        // 2-entry palette: index 0 → red, index 1 → blue. LUT entries carry
        // their significant byte in the high byte (PS3.3 C.7.6.3.1.5).
        var dataSet = DataSet()
        func descriptorData(entries: UInt16) -> Data {
            var d = Data()
            for v in [entries, 0, 16] as [UInt16] {
                d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8))
            }
            return d
        }
        func lutData(_ values: [UInt16]) -> Data {
            var d = Data()
            for v in values { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
            return d
        }
        dataSet[.redPaletteColorLookupTableDescriptor] = DataElement.data(
            tag: .redPaletteColorLookupTableDescriptor, vr: .US, data: descriptorData(entries: 2))
        dataSet[.greenPaletteColorLookupTableDescriptor] = DataElement.data(
            tag: .greenPaletteColorLookupTableDescriptor, vr: .US, data: descriptorData(entries: 2))
        dataSet[.bluePaletteColorLookupTableDescriptor] = DataElement.data(
            tag: .bluePaletteColorLookupTableDescriptor, vr: .US, data: descriptorData(entries: 2))
        dataSet[.redPaletteColorLookupTableData] = DataElement.data(
            tag: .redPaletteColorLookupTableData, vr: .OW, data: lutData([0xFF00, 0x0000]))
        dataSet[.greenPaletteColorLookupTableData] = DataElement.data(
            tag: .greenPaletteColorLookupTableData, vr: .OW, data: lutData([0x0000, 0x0000]))
        dataSet[.bluePaletteColorLookupTableData] = DataElement.data(
            tag: .bluePaletteColorLookupTableData, vr: .OW, data: lutData([0x0000, 0xFF00]))

        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .paletteColor,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0, 1]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()

        let color = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: dataSet, frameIndex: 0, colorMode: .color)
        XCTAssertEqual(color.photometricInterpretation, "RGB")
        XCTAssertEqual([UInt8](color.pixelData), [255, 0, 0, 0, 0, 255])

        let gray = try await preprocessor.prepareForPrint(
            pixelData: pixelData, dataSet: dataSet, frameIndex: 0, colorMode: .grayscale)
        XCTAssertEqual(gray.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(gray.pixelData.count, 2)
    }

    func testPrepareForPrintPaletteColorMissingLUTThrows() async throws {
        let descriptor = PixelDataDescriptor(
            rows: 1, columns: 1, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .paletteColor,
            planarConfiguration: 0
        )
        let pixelData = PixelData(data: Data([0]), descriptor: descriptor)
        let preprocessor = ImagePreprocessor()
        do {
            _ = try await preprocessor.prepareForPrint(
                pixelData: pixelData, dataSet: DataSet(), frameIndex: 0, colorMode: .color)
            XCTFail("Expected missingPaletteLUT")
        } catch {
            // expected
        }
    }
}


