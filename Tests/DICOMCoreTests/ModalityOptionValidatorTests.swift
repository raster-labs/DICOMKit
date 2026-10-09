import Testing
import Foundation
@testable import DICOMCore

@Suite("ModalityOptionValidator Tests")
struct ModalityOptionValidatorTests {

    // MARK: - Clean values

    @Test("A current defined term passes silently")
    func testCurrentCodeClean() {
        let outcome = ModalityOptionValidator.validate("CT")
        #expect(outcome?.value == "CT")
        #expect(outcome?.warning == nil)
        #expect(outcome?.isStrictFailure == false)
    }

    @Test("Codes new in this work pass silently")
    func testNewCodesClean() {
        for code in ["OPT", "OCT", "IVOCT", "RTPLAN", "M3D", "RESP", "SM", "PA"] {
            let outcome = ModalityOptionValidator.validate(code)
            #expect(outcome?.value == code)
            #expect(outcome?.warning == nil, "\(code) should not warn")
        }
    }

    @Test("Values are trimmed and uppercased")
    func testCanonicalization() {
        #expect(ModalityOptionValidator.validate(" ct ")?.value == "CT")
        #expect(ModalityOptionValidator.validate("opt")?.value == "OPT")
    }

    @Test("No modality given means no filter")
    func testNilAndEmpty() {
        #expect(ModalityOptionValidator.validate(nil) == nil)
        #expect(ModalityOptionValidator.validate("") == nil)
        #expect(ModalityOptionValidator.validate("   ") == nil)
    }

    // MARK: - Aliases

    @Test("Aliases normalize with an informational note")
    func testAliasNormalizes() {
        let outcome = ModalityOptionValidator.validate("MRI")
        #expect(outcome?.value == "MR")
        #expect(outcome?.isNote == true, "an alias is informational, not a problem")
        #expect(outcome?.isStrictFailure == false, "an alias must not fail --strict-modality")
        #expect(outcome?.warning?.contains("MR") == true)
    }

    @Test("Every alias resolves rather than warning as unknown")
    func testAllAliases() {
        let expected = ["MRI": "MR", "PET": "PT", "PDF": "DOC",
                        "XR": "DX", "DR": "DX", "SPECT": "NM", "RT": "RTIMAGE"]
        for (alias, code) in expected {
            let outcome = ModalityOptionValidator.validate(alias)
            #expect(outcome?.value == code, "\(alias) should resolve to \(code)")
            #expect(outcome?.isNote == true)
        }
    }

    // MARK: - Retired and conventional

    @Test("A retired code is accepted but flagged")
    func testRetiredCode() {
        let outcome = ModalityOptionValidator.validate("ST")
        #expect(outcome?.value == "ST", "legacy data must still be queryable")
        #expect(outcome?.warning?.contains("retired") == true)
        #expect(outcome?.isStrictFailure == true)
        #expect(outcome?.isNote == false)
    }

    @Test("SC and VL are accepted but flagged as non-standard")
    func testConventionalCodes() {
        for code in ["SC", "VL"] {
            let outcome = ModalityOptionValidator.validate(code)
            #expect(outcome?.value == code)
            #expect(outcome?.warning?.contains("not a DICOM Defined Term") == true)
            #expect(outcome?.isStrictFailure == true)
        }
    }

    // MARK: - Unknown values

    @Test("An unknown code is passed through, not rejected")
    func testUnknownCodePassesThrough() {
        // Private codes are legal on the wire, so the default is to warn and send.
        let outcome = ModalityOptionValidator.validate("ACMEPRIVATE")
        #expect(outcome?.value == "ACMEPRIVATE")
        #expect(outcome?.warning?.contains("not a DICOM Defined Term") == true)
        #expect(outcome?.isStrictFailure == true)
    }

    @Test("A typo suggests the closest defined terms")
    func testTypoSuggestions() {
        let outcome = ModalityOptionValidator.validate("CTT")
        #expect(outcome?.warning?.contains("Did you mean") == true)
        #expect(outcome?.warning?.contains("CT") == true)
    }

    @Test("Suggestions are ranked by edit distance and capped at three")
    func testClosestCodes() {
        let suggestions = ModalityOptionValidator.closestCodes(to: "CTT")
        #expect(suggestions.first == "CT", "the nearest code should come first")
        #expect(suggestions.count <= 3)
    }

    @Test("A value with no near match offers no misleading suggestion")
    func testNoSuggestionWhenFarOff() {
        let suggestions = ModalityOptionValidator.closestCodes(to: "ZZZZZZZZZ")
        #expect(suggestions.isEmpty)
    }

    // MARK: - resolve()

    @Test("resolve returns the normalized value")
    func testResolveNormalizes() throws {
        #expect(try ModalityOptionValidator.resolve("MRI") == "MR")
        #expect(try ModalityOptionValidator.resolve("CT") == "CT")
        #expect(try ModalityOptionValidator.resolve(nil) == nil)
    }

    @Test("resolve throws under strict mode for a questionable value")
    func testResolveStrictThrows() {
        #expect(throws: ModalityOptionError.self) {
            try ModalityOptionValidator.resolve("CTT", strict: true)
        }
        #expect(throws: ModalityOptionError.self) {
            try ModalityOptionValidator.resolve("ST", strict: true)
        }
    }

    @Test("resolve does not throw under strict mode for a valid code or alias")
    func testResolveStrictAllowsValid() throws {
        #expect(try ModalityOptionValidator.resolve("OPT", strict: true) == "OPT")
        // An alias is a spelling, not an invalid modality — strict must allow it.
        #expect(try ModalityOptionValidator.resolve("MRI", strict: true) == "MR")
    }

    @Test("The strict error names the reason")
    func testStrictErrorMessage() {
        do {
            _ = try ModalityOptionValidator.resolve("CTT", strict: true)
            Issue.record("expected a rejection")
        } catch let error as ModalityOptionError {
            #expect(error.description.contains("--strict-modality"))
            #expect(error.description.contains("CTT"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // MARK: - Help and listing

    @Test("Help text points at a command that can actually run standalone")
    func testHelpText() {
        let help = ModalityOptionValidator.helpText("filter")
        #expect(help.contains("0008,0060"))
        // Every tool taking --modality has a required positional argument, so
        // the listing lives on dicom-tags, which can run without one.
        #expect(help.contains("dicom-tags --list-modalities"))
    }

    @Test("The listing covers every current code, grouped")
    func testListing() {
        let listing = ModalityOptionValidator.listing()
        for modality in Modality.allCases {
            #expect(listing.contains(modality.rawValue), "listing omits \(modality.rawValue)")
        }
        for category in Modality.groupedByCategory {
            #expect(listing.contains(category.category.name))
        }
        #expect(listing.contains("Aliases accepted"))
    }

    @Test("The listing does not offer retired codes")
    func testListingExcludesRetired() {
        let listing = ModalityOptionValidator.listing()
        // "Retired" appears in the trailing explanation, but no retired code
        // should be listed as though it were offered.
        for code in ["Angioscopy", "Cinefluorography", "Culposcopy"] {
            #expect(!listing.contains(code), "listing should not offer retired \(code)")
        }
    }
}
