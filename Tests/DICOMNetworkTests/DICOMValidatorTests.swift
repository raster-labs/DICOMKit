import XCTest
@testable import DICOMNetwork
@testable import DICOMCore

// MARK: - Validation Error Tests

final class ValidationErrorTests: XCTestCase {
    
    func testMissingRequiredAttributeDescription() {
        let error = ValidationError.missingRequiredAttribute(
            tag: Tag(group: 0x0008, element: 0x0016),
            description: "SOP Class UID"
        )
        XCTAssertTrue(error.description.contains("Missing required attribute"))
        XCTAssertTrue(error.description.contains("(0008,0016)"))
        XCTAssertTrue(error.description.contains("SOP Class UID"))
    }
    
    func testInvalidUIDDescription() {
        let error = ValidationError.invalidUID(
            tag: Tag(group: 0x0008, element: 0x0016),
            value: "invalid..uid",
            reason: "Consecutive periods"
        )
        XCTAssertTrue(error.description.contains("Invalid UID"))
        XCTAssertTrue(error.description.contains("invalid..uid"))
        XCTAssertTrue(error.description.contains("Consecutive periods"))
    }
    
    func testEmptyValueDescription() {
        let error = ValidationError.emptyValue(
            tag: Tag(group: 0x0008, element: 0x0018),
            description: "SOP Instance UID"
        )
        XCTAssertTrue(error.description.contains("Empty value"))
        XCTAssertTrue(error.description.contains("SOP Instance UID"))
    }
    
    func testValueTooLongDescription() {
        let error = ValidationError.valueTooLong(
            tag: Tag(group: 0x0008, element: 0x0016),
            actualLength: 100,
            maxLength: 64
        )
        XCTAssertTrue(error.description.contains("too long"))
        XCTAssertTrue(error.description.contains("100"))
        XCTAssertTrue(error.description.contains("64"))
    }
    
    func testUnknownSOPClassDescription() {
        let error = ValidationError.unknownSOPClass(sopClassUID: "1.2.3.4.5.6.7.8.9")
        XCTAssertTrue(error.description.contains("Unknown SOP Class"))
        XCTAssertTrue(error.description.contains("1.2.3.4.5.6.7.8.9"))
    }
    
    func testUnknownTransferSyntaxDescription() {
        let error = ValidationError.unknownTransferSyntax(transferSyntaxUID: "1.2.3.4.5.6.7")
        XCTAssertTrue(error.description.contains("Unknown Transfer Syntax"))
        XCTAssertTrue(error.description.contains("1.2.3.4.5.6.7"))
    }
    
    func testIncompletePixelDataDescription() {
        let error = ValidationError.incompletePixelData(
            missingTags: [Tag(group: 0x0028, element: 0x0010), Tag(group: 0x0028, element: 0x0011)]
        )
        XCTAssertTrue(error.description.contains("Incomplete pixel data"))
        XCTAssertTrue(error.description.contains("(0028,0010)"))
        XCTAssertTrue(error.description.contains("(0028,0011)"))
    }
    
    func testCustomValidationFailedWithTagDescription() {
        let error = ValidationError.customValidationFailed(
            tag: Tag(group: 0x0010, element: 0x0010),
            message: "Invalid patient name format"
        )
        XCTAssertTrue(error.description.contains("(0010,0010)"))
        XCTAssertTrue(error.description.contains("Invalid patient name format"))
    }
    
    func testCustomValidationFailedWithoutTagDescription() {
        let error = ValidationError.customValidationFailed(
            tag: nil,
            message: "General validation failure"
        )
        XCTAssertFalse(error.description.contains("("))
        XCTAssertTrue(error.description.contains("General validation failure"))
    }
    
    func testValidationErrorHashable() {
        let error1 = ValidationError.missingRequiredAttribute(
            tag: Tag(group: 0x0008, element: 0x0016),
            description: "SOP Class UID"
        )
        let error2 = ValidationError.missingRequiredAttribute(
            tag: Tag(group: 0x0008, element: 0x0016),
            description: "SOP Class UID"
        )
        let error3 = ValidationError.missingRequiredAttribute(
            tag: Tag(group: 0x0008, element: 0x0018),
            description: "SOP Instance UID"
        )
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        
        var set = Set<ValidationError>()
        set.insert(error1)
        set.insert(error2)
        XCTAssertEqual(set.count, 1)
    }
}

// MARK: - Validation Result Tests

final class ValidationResultTests: XCTestCase {
    
    func testSuccessResult() {
        let result = ValidationResult.success
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertFalse(result.hasWarnings)
        XCTAssertEqual(result.issueCount, 0)
    }
    
    func testSuccessWithWarningsResult() {
        let warnings = [
            ValidationError.missingRequiredAttribute(tag: .patientID, description: "Patient ID")
        ]
        let result = ValidationResult.successWithWarnings(warnings)
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.hasWarnings)
        XCTAssertEqual(result.issueCount, 1)
    }
    
    func testFailureResult() {
        let errors = [
            ValidationError.missingRequiredAttribute(tag: .sopClassUID, description: "SOP Class UID")
        ]
        let warnings = [
            ValidationError.missingRequiredAttribute(tag: .patientID, description: "Patient ID")
        ]
        let result = ValidationResult.failure(errors: errors, warnings: warnings)
        
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.hasWarnings)
        XCTAssertEqual(result.issueCount, 2)
    }
    
    func testResultDescription() {
        let success = ValidationResult.success
        XCTAssertTrue(success.description.contains("valid"))
        
        let warnings = ValidationResult.successWithWarnings([
            ValidationError.missingRequiredAttribute(tag: .patientID, description: "Patient ID")
        ])
        XCTAssertTrue(warnings.description.contains("warning"))
        
        let failure = ValidationResult.failure(errors: [
            ValidationError.missingRequiredAttribute(tag: .sopClassUID, description: "SOP Class UID")
        ])
        XCTAssertTrue(failure.description.contains("invalid"))
    }
}

// MARK: - Validation Level Tests

final class ValidationLevelTests: XCTestCase {
    
    func testValidationLevelDescription() {
        XCTAssertEqual(ValidationLevel.minimal.description, "minimal")
        XCTAssertEqual(ValidationLevel.standard.description, "standard")
        XCTAssertEqual(ValidationLevel.strict.description, "strict")
    }
    
    func testValidationLevelCaseIterable() {
        let allCases = ValidationLevel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.minimal))
        XCTAssertTrue(allCases.contains(.standard))
        XCTAssertTrue(allCases.contains(.strict))
    }
}

// MARK: - Validation Configuration Tests

final class ValidationConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = ValidationConfiguration.default
        
        XCTAssertEqual(config.level, .standard)
        XCTAssertFalse(config.validateTransferSyntax)
        XCTAssertTrue(config.validatePixelData)
        XCTAssertFalse(config.treatWarningsAsErrors)
        XCTAssertTrue(config.allowedSOPClasses.isEmpty)
        XCTAssertTrue(config.additionalRequiredTags.isEmpty)
    }
    
    func testMinimalConfiguration() {
        let config = ValidationConfiguration.minimal
        
        XCTAssertEqual(config.level, .minimal)
        XCTAssertFalse(config.validateTransferSyntax)
        XCTAssertFalse(config.validatePixelData)
    }
    
    func testStrictConfiguration() {
        let config = ValidationConfiguration.strict
        
        XCTAssertEqual(config.level, .strict)
        XCTAssertTrue(config.validateTransferSyntax)
        XCTAssertTrue(config.validatePixelData)
        XCTAssertTrue(config.treatWarningsAsErrors)
    }
    
    func testCustomConfiguration() {
        let allowedSOP: Set<String> = ["1.2.840.10008.5.1.4.1.1.2"]
        let additionalTags: Set<Tag> = [.patientWeight, .patientSize]
        
        let config = ValidationConfiguration(
            level: .standard,
            validateTransferSyntax: true,
            validatePixelData: false,
            treatWarningsAsErrors: true,
            allowedSOPClasses: allowedSOP,
            additionalRequiredTags: additionalTags
        )
        
        XCTAssertEqual(config.level, .standard)
        XCTAssertTrue(config.validateTransferSyntax)
        XCTAssertFalse(config.validatePixelData)
        XCTAssertTrue(config.treatWarningsAsErrors)
        XCTAssertEqual(config.allowedSOPClasses, allowedSOP)
        XCTAssertEqual(config.additionalRequiredTags, additionalTags)
    }
    
    func testConfigurationHashable() {
        let config1 = ValidationConfiguration(level: .standard)
        let config2 = ValidationConfiguration(level: .standard)
        let config3 = ValidationConfiguration(level: .strict)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testConfigurationDescription() {
        let config = ValidationConfiguration(
            level: .strict,
            validateTransferSyntax: true,
            validatePixelData: true,
            treatWarningsAsErrors: true,
            allowedSOPClasses: ["1.2.3"],
            additionalRequiredTags: [.patientID]
        )
        let desc = config.description
        
        XCTAssertTrue(desc.contains("strict"))
        XCTAssertTrue(desc.contains("validateTS"))
        XCTAssertTrue(desc.contains("validatePD"))
        XCTAssertTrue(desc.contains("warningsAsErrors"))
        XCTAssertTrue(desc.contains("allowed SOP Classes"))
        XCTAssertTrue(desc.contains("additional tags"))
    }
}

// MARK: - DICOM Validator Tests

final class DICOMValidatorTests: XCTestCase {
    
    var validator: DICOMValidator!
    
    override func setUp() {
        super.setUp()
        validator = DICOMValidator()
    }
    
    // MARK: - Helper Methods
    
    /// Creates a mock data provider for testing
    private func createDataProvider(
        strings: [Tag: String] = [:],
        data: [Tag: Data] = [:]
    ) -> ((Tag) -> String?, (Tag) -> Data?) {
        let getString: (Tag) -> String? = { strings[$0] }
        let getData: (Tag) -> Data? = { data[$0] }
        return (getString, getData)
    }
    
    // MARK: - Minimal Validation Tests
    
    func testMinimalValidation_ValidData() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .minimal
        )
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }
    
    func testMinimalValidation_MissingSOPClassUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .minimal
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .missingRequiredAttribute(let tag, _) = error {
                return tag == .sopClassUID
            }
            return false
        }))
    }
    
    func testMinimalValidation_MissingSOPInstanceUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .minimal
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .missingRequiredAttribute(let tag, _) = error {
                return tag == .sopInstanceUID
            }
            return false
        }))
    }
    
    func testMinimalValidation_EmptySOPClassUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .minimal
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .emptyValue(let tag, _) = error {
                return tag == .sopClassUID
            }
            return false
        }))
    }
    
    func testMinimalValidation_InvalidUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "invalid..uid",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .minimal
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .invalidUID(let tag, _, _) = error {
                return tag == .sopClassUID
            }
            return false
        }))
    }
    
    // MARK: - Standard Validation Tests
    
    func testStandardValidation_ValidData() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .patientID: "PATIENT001",
            .modality: "CT"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .default
        )
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }
    
    func testStandardValidation_MissingStudyInstanceUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .patientID: "PATIENT001",
            .modality: "CT"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .default
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .missingRequiredAttribute(let tag, _) = error {
                return tag == .studyInstanceUID
            }
            return false
        }))
    }
    
    func testStandardValidation_MissingPatientID_Warning() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .modality: "CT"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .default
        )
        
        // Patient ID missing is a warning, not an error
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.hasWarnings)
        XCTAssertTrue(result.warnings.contains(where: { error in
            if case .missingRequiredAttribute(let tag, _) = error {
                return tag == .patientID
            }
            return false
        }))
    }
    
    func testStandardValidation_InvalidStudyInstanceUID() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.001.4",  // Leading zero in component "001" is invalid
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .patientID: "PATIENT001",
            .modality: "CT"
        ])
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: .default
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .invalidUID(let tag, _, _) = error {
                return tag == .studyInstanceUID
            }
            return false
        }))
    }
    
    // MARK: - Strict Validation Tests
    
    func testStrictValidation_UnknownSOPClass_Warning() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.3.4.5.6.7.8.9",  // Unknown but valid format
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .patientID: "PATIENT001",
            .modality: "CT"
        ])
        
        // Use strict validation but don't treat warnings as errors
        let config = ValidationConfiguration(
            level: .strict,
            validateTransferSyntax: false,
            validatePixelData: false,
            treatWarningsAsErrors: false
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        // Should have a warning for unknown SOP Class
        XCTAssertTrue(result.hasWarnings)
        XCTAssertTrue(result.warnings.contains(where: { error in
            if case .unknownSOPClass(_) = error {
                return true
            }
            return false
        }))
    }
    
    func testStrictValidation_MissingType2Attributes() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            .patientID: "PATIENT001",
            .modality: "CT"
            // Missing: patientName, patientBirthDate, patientSex, etc.
        ])
        
        let config = ValidationConfiguration(
            level: .strict,
            validateTransferSyntax: false,
            validatePixelData: false,
            treatWarningsAsErrors: false
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        // Should have warnings for missing Type 2 attributes
        XCTAssertTrue(result.hasWarnings)
        XCTAssertTrue(result.warnings.count > 0)
    }
    
    // MARK: - Transfer Syntax Validation Tests
    
    func testTransferSyntaxValidation_ValidSyntax() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .transferSyntaxUID: "1.2.840.10008.1.2.1"  // Explicit VR Little Endian
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            validateTransferSyntax: true
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertTrue(result.isValid)
    }
    
    func testTransferSyntaxValidation_UnknownSyntax() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .transferSyntaxUID: "1.2.3.4.5.6.7.8"  // Unknown but valid format
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            validateTransferSyntax: true,
            treatWarningsAsErrors: false
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertTrue(result.isValid) // Unknown transfer syntax is a warning
        XCTAssertTrue(result.hasWarnings)
    }
    
    func testTransferSyntaxValidation_InvalidFormat() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .transferSyntaxUID: "not.a.valid..uid"
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            validateTransferSyntax: true
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .invalidUID(let tag, _, _) = error {
                return tag == .transferSyntaxUID
            }
            return false
        }))
    }
    
    // MARK: - Pixel Data Validation Tests
    
    func testPixelDataValidation_NoPixelData() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        // No pixel data provided
        
        let config = ValidationConfiguration(
            level: .minimal,
            validatePixelData: true
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        // Should pass because there's no pixel data to validate
        XCTAssertTrue(result.isValid)
    }
    
    func testPixelDataValidation_IncompletePixelData() {
        let pixelDataTag = Tag(group: 0x7FE0, element: 0x0010)
        let (getString, getData) = createDataProvider(
            strings: [
                .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
                // Missing: rows, columns, bitsAllocated, etc.
            ],
            data: [
                pixelDataTag: Data([0x00, 0x01, 0x02, 0x03])  // Some pixel data
            ]
        )
        
        let config = ValidationConfiguration(
            level: .minimal,
            validatePixelData: true
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .incompletePixelData(_) = error {
                return true
            }
            return false
        }))
    }
    
    func testPixelDataValidation_CompletePixelData() {
        let pixelDataTag = Tag(group: 0x7FE0, element: 0x0010)
        let (getString, getData) = createDataProvider(
            strings: [
                .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
                .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
                .rows: "512",
                .columns: "512",
                .bitsAllocated: "16",
                .bitsStored: "12",
                .highBit: "11",
                .pixelRepresentation: "0",
                .samplesPerPixel: "1",
                .photometricInterpretation: "MONOCHROME2"
            ],
            data: [
                pixelDataTag: Data([0x00, 0x01, 0x02, 0x03])
            ]
        )
        
        let config = ValidationConfiguration(
            level: .minimal,
            validatePixelData: true
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertTrue(result.isValid)
    }
    
    // MARK: - Allowed SOP Classes Tests
    
    func testAllowedSOPClasses_Allowed() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",  // CT
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            allowedSOPClasses: ["1.2.840.10008.5.1.4.1.1.2", "1.2.840.10008.5.1.4.1.1.4"]
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertTrue(result.isValid)
    }
    
    func testAllowedSOPClasses_NotAllowed() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.7",  // Secondary Capture
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            allowedSOPClasses: ["1.2.840.10008.5.1.4.1.1.2"]  // Only CT allowed
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .unknownSOPClass(_) = error {
                return true
            }
            return false
        }))
    }
    
    // MARK: - Additional Required Tags Tests
    
    func testAdditionalRequiredTags_Present() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .patientWeight: "70.5"
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            additionalRequiredTags: [.patientWeight]
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertTrue(result.isValid)
    }
    
    func testAdditionalRequiredTags_Missing() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10"
        ])
        
        let config = ValidationConfiguration(
            level: .minimal,
            additionalRequiredTags: [.patientWeight]
        )
        
        let result = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { error in
            if case .missingRequiredAttribute(let tag, _) = error {
                return tag == .patientWeight
            }
            return false
        }))
    }
    
    // MARK: - Warnings As Errors Tests
    
    func testTreatWarningsAsErrors() {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .studyInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            .seriesInstanceUID: "1.2.3.4.5.6.7.8.9.12",
            // Missing: patientID (warning)
            .modality: "CT"
        ])
        
        // Without treatWarningsAsErrors
        let config1 = ValidationConfiguration(
            level: .standard,
            treatWarningsAsErrors: false
        )
        let result1 = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config1
        )
        XCTAssertTrue(result1.isValid)
        XCTAssertTrue(result1.hasWarnings)
        
        // With treatWarningsAsErrors
        let config2 = ValidationConfiguration(
            level: .standard,
            treatWarningsAsErrors: true
        )
        let result2 = validator.validate(
            getString: getString,
            getData: getData,
            configuration: config2
        )
        XCTAssertFalse(result2.isValid)
        XCTAssertFalse(result2.hasWarnings)  // Warnings moved to errors
    }
    
    // MARK: - UID Validation Helper Tests
    
    func testIsValidUID_Valid() {
        XCTAssertTrue(validator.isValidUID("1.2.3.4.5"))
        XCTAssertTrue(validator.isValidUID("1.2.840.10008.5.1.4.1.1.2"))
        XCTAssertTrue(validator.isValidUID("0"))
        XCTAssertTrue(validator.isValidUID("1"))
    }
    
    func testIsValidUID_Invalid() {
        XCTAssertFalse(validator.isValidUID(""))
        XCTAssertFalse(validator.isValidUID("..1.2.3"))
        XCTAssertFalse(validator.isValidUID("1.2.3..4"))
        XCTAssertFalse(validator.isValidUID("1.2.3."))
        XCTAssertFalse(validator.isValidUID("1.2.3.04"))  // Leading zero
        XCTAssertFalse(validator.isValidUID("abc.def.ghi"))
    }

    // MARK: - Known transfer syntaxes come from DICOMCore's registry (PS3.6 Table A-1)

    private func transferSyntaxWarning(_ uid: String) -> Bool {
        let (getString, getData) = createDataProvider(strings: [
            .sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            .sopInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            .transferSyntaxUID: uid
        ])
        let config = ValidationConfiguration(level: .minimal, validateTransferSyntax: true, treatWarningsAsErrors: false)
        let result = validator.validate(getString: getString, getData: getData, configuration: config)
        return result.warnings.contains { if case .unknownTransferSyntax = $0 { return true } else { return false } }
    }

    func testTransferSyntaxValidation_RegisteredSyntaxesAreKnown() {
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.4.110"), "JPEG XL Lossless (PS3.6 Table A-1)")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.8.1"), "Deflated Image Frame Compression")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.1.98"), "Encapsulated Uncompressed Explicit VR LE")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.4.100.1"), "Fragmentable MPEG2 (PS3.5 Annex A.4)")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.4.52"), "retired JPEG Extended (Process 3 & 5) is still a registered UID")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.20"), "Papyrus 3 (retired)")
        XCTAssertFalse(transferSyntaxWarning("1.2.840.10008.1.2.1"))
        // The validator and DICOMCore agree by construction.
        for syntax in TransferSyntax.allKnown {
            XCTAssertFalse(transferSyntaxWarning(syntax.uid), syntax.uid)
        }
    }

    func testTransferSyntaxValidation_UnregisteredSyntaxIsUnknown() {
        XCTAssertTrue(transferSyntaxWarning("1.2.3.4"))
        XCTAssertTrue(transferSyntaxWarning("1.2.840.10008.1.2.4.999"))
    }

}
