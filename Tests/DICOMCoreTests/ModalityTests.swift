import Testing
import Foundation
@testable import DICOMCore

@Suite("Modality Tests")
struct ModalityTests {

    // MARK: - Construction

    @Test("Known code constructs and reports its name")
    func testKnownCode() {
        let modality = Modality(rawValue: "CT")
        #expect(modality != nil)
        #expect(modality?.rawValue == "CT")
        #expect(modality?.name == "Computed Tomography")
    }

    @Test("Unknown code fails the validating initializer")
    func testUnknownCodeRejected() {
        #expect(Modality(rawValue: "NOTACODE") == nil)
        #expect(Modality(rawValue: "") == nil)
    }

    @Test("Lowercase and padded values canonicalize")
    func testCanonicalization() {
        #expect(Modality(rawValue: "ct") == Modality.ct)
        #expect(Modality(rawValue: "  mr  ") == Modality.mr)
        #expect(Modality(rawValue: "Opt") == Modality.opt)
    }

    @Test("Unchecked initializer preserves private codes")
    func testUncheckedPreservesPrivateCodes() {
        let priv = Modality(unchecked: "ACME_PRIVATE")
        #expect(priv.rawValue == "ACME_PRIVATE")
        #expect(priv.isStandard == false)
        #expect(priv.isCurrent == false)
        #expect(priv.name == "ACME_PRIVATE", "unknown codes display as themselves")
        #expect(priv.category == .other)
    }

    @Test("Unchecked initializer canonicalizes too")
    func testUncheckedCanonicalizes() {
        #expect(Modality(unchecked: " ct ").rawValue == "CT")
    }

    // MARK: - Standard / retired classification

    @Test("Current standard codes are standard and not retired")
    func testCurrentCodes() {
        for modality in [Modality.ct, .mr, .opt, .rtplan, .m3d, .resp] {
            #expect(modality.isStandard, "\(modality) should be standard")
            #expect(!modality.isRetired, "\(modality) should not be retired")
            #expect(modality.isCurrent)
        }
    }

    @Test("Retired codes are recognized but flagged")
    func testRetiredCodes() {
        let st = Modality(rawValue: "ST")
        #expect(st != nil, "retired codes must still parse for legacy data")
        #expect(st?.isRetired == true)
        #expect(st?.isCurrent == false)
        #expect(st?.name == "Single-Photon Emission Computed Tomography")
    }

    @Test("All 18 retired codes are recognized")
    func testAllRetiredCodesRecognized() {
        let retired = ["AS", "CD", "CF", "CP", "CS", "DD", "DF", "DM", "DS",
                       "EC", "FA", "FS", "LP", "MA", "MS", "OPR", "ST", "VF"]
        for code in retired {
            let modality = Modality(rawValue: code)
            #expect(modality != nil, "\(code) should be recognized")
            #expect(modality?.isRetired == true, "\(code) should be retired")
        }
        #expect(retired.count == 18)
    }

    @Test("SC and VL are recognized but not standard")
    func testNonStandardConventionalCodes() {
        for modality in [Modality.sc, Modality.vl] {
            #expect(Modality(rawValue: modality.rawValue) != nil,
                    "\(modality) must be recognized — existing data uses it")
            #expect(modality.isStandard == false,
                    "\(modality) is not a Defined Term")
            #expect(modality.category == .nonStandard)
        }
    }

    // MARK: - Collections

    @Test("allCases holds exactly the 79 current defined terms")
    func testAllCasesCount() {
        #expect(Modality.allCases.count == 79)
        #expect(Modality.allCases.allSatisfy { $0.isCurrent })
    }

    @Test("allCases excludes non-standard and retired codes")
    func testAllCasesExclusions() {
        #expect(!Modality.allCases.contains(Modality.sc))
        #expect(!Modality.allCases.contains(Modality.vl))
        #expect(!Modality.allCases.contains { $0.isRetired })
    }

    @Test("allIncludingRetired covers current, conventional and retired")
    func testAllIncludingRetired() {
        // 79 current + SC + VL + 18 retired
        #expect(Modality.allIncludingRetired.count == 99)
        #expect(Modality.allIncludingRetired.contains(Modality.sc))
        #expect(Modality.allIncludingRetired.contains(Modality(unchecked: "ST")))
    }

    @Test("No duplicate codes in the definition table")
    func testNoDuplicates() {
        let codes = Modality.allIncludingRetired.map { $0.rawValue }
        #expect(Set(codes).count == codes.count, "duplicate modality code in table")
    }

    @Test("Every code has a non-empty name distinct from its code")
    func testEveryCodeHasName() {
        for modality in Modality.allIncludingRetired {
            #expect(!modality.name.isEmpty)
            #expect(modality.name != modality.rawValue,
                    "\(modality.rawValue) is missing a human-readable name")
        }
    }

    @Test("groupedByCategory partitions allCases without loss")
    func testGroupedByCategory() {
        let grouped = Modality.groupedByCategory.flatMap { $0.modalities }
        #expect(grouped.count == Modality.allCases.count)
        #expect(Set(grouped) == Set(Modality.allCases))
        let hasEmptyGroup = Modality.groupedByCategory.contains { $0.modalities.isEmpty }
        #expect(!hasEmptyGroup)
    }

    // MARK: - Categories

    @Test("Codes land in their expected category")
    func testCategories() {
        #expect(Modality.ct.category == .crossSectional)
        #expect(Modality.dx.category == .radiography)
        #expect(Modality.us.category == .ultrasound)
        #expect(Modality.es.category == .visibleLight)
        #expect(Modality.opt.category == .ophthalmic)
        #expect(Modality.ecg.category == .waveform)
        #expect(Modality.rtplan.category == .radiotherapy)
        #expect(Modality.sr.category == .derived)
        #expect(Modality.ot.category == .other)
    }

    // MARK: - Alias resolution

    @Test("Common aliases normalize to their canonical code")
    func testAliasNormalization() {
        #expect(Modality.normalized("MRI") == Modality.mr)
        #expect(Modality.normalized("PET") == Modality.pt)
        #expect(Modality.normalized("PDF") == Modality.doc)
        #expect(Modality.normalized("XR") == Modality.dx)
        #expect(Modality.normalized("DR") == Modality.dx)
        #expect(Modality.normalized("SPECT") == Modality.nm)
    }

    @Test("RT resolves to RTIMAGE rather than staying a pseudo-code")
    func testRTDemotion() {
        #expect(Modality(rawValue: "RT") == nil, "RT is not a DICOM modality code")
        #expect(Modality.normalized("RT") == Modality.rtimage)
    }

    @Test("Real RT codes are distinguished from one another")
    func testRTCodesDistinct() {
        let codes = ["RTIMAGE", "RTDOSE", "RTSTRUCT", "RTPLAN",
                     "RTRECORD", "RTINTENT", "RTRAD", "RTSEGANN"]
        let modalities = codes.compactMap { Modality(rawValue: $0) }
        #expect(modalities.count == 8)
        #expect(Set(modalities).count == 8, "RT codes must not collapse together")
        let allRT = modalities.allSatisfy { $0.category == .radiotherapy }
        #expect(allRT)
    }

    @Test("Aliases are case- and whitespace-insensitive")
    func testAliasCanonicalization() {
        #expect(Modality.normalized("mri") == Modality.mr)
        #expect(Modality.normalized(" pet ") == Modality.pt)
    }

    @Test("Normalizing an unknown value returns nil")
    func testNormalizeUnknown() {
        #expect(Modality.normalized("NOTACODE") == nil)
    }

    @Test("Normalizing a canonical code is idempotent")
    func testNormalizeIdempotent() {
        for modality in Modality.allCases {
            #expect(Modality.normalized(modality.rawValue) == modality)
        }
    }

    // MARK: - Ophthalmic coverage (absent from the repo before this type)

    @Test("Ophthalmic tomography family is fully represented")
    func testOphthalmicCoverage() {
        for code in ["OPT", "OPTENF", "OPTBSV", "OCT", "IVOCT",
                     "OPM", "OAM", "OPV", "OP"] {
            let modality = Modality(rawValue: code)
            #expect(modality != nil, "\(code) should be recognized")
            #expect(modality?.category == .ophthalmic)
        }
    }

    // MARK: - Codes the library itself emits

    @Test("Every modality DICOMKit emits is recognized")
    func testLibraryEmittedCodesRecognized() {
        // Regression guard: these are written by WaveformBuilder, Video,
        // EncapsulatedDocumentWorkflow, SecondaryCapture and the PR builders.
        // Before this type, AU/EPS/RESP/M3D fell off the app's 26-code list and
        // rendered with a fallback icon and a raw uppercased string.
        let emitted = ["ECG", "HD", "EPS", "AU", "RESP", "OT",
                       "ES", "GM", "XC", "M3D", "DOC", "SC", "PR", "SEG"]
        for code in emitted {
            let modality = Modality(rawValue: code)
            #expect(modality != nil, "library emits \(code) but it is unrecognized")
            #expect(modality?.name.isEmpty == false)
        }
    }

    // MARK: - Validation-facing behavior

    // DICOMValidator.validateModalityDefinedTerm branches on exactly these
    // properties; the validator's own end-to-end path is covered by the
    // round-trip validate tests, which run against real files.

    @Test("Defined Term check: current codes raise nothing")
    func testDefinedTermCurrentCodesClean() {
        for modality in Modality.allCases {
            #expect(modality.isStandard && !modality.isRetired,
                    "\(modality.rawValue) would warn as non-current")
        }
    }

    @Test("Defined Term check: an alias is recognized as a correctable spelling")
    func testDefinedTermAliasIsCorrectable() {
        // The validator warns "did you mean X" only when rawValue lookup fails
        // but normalization succeeds. MRI must behave that way.
        #expect(Modality(rawValue: "MRI") == nil)
        #expect(Modality.normalized("MRI") == Modality.mr)
    }

    @Test("Defined Term check: an unknown private code is neither known nor aliased")
    func testDefinedTermPrivateCode() {
        #expect(Modality(rawValue: "ACME") == nil)
        #expect(Modality.normalized("ACME") == nil)
        #expect(Modality(unchecked: "ACME").isStandard == false)
    }

    @Test("Defined Term check: SC and VL warn as conventional, not as unknown")
    func testDefinedTermConventionalCodes() {
        for modality in [Modality.sc, Modality.vl] {
            // Known (so no "not a Defined Term" unknown-branch warning)…
            #expect(Modality(rawValue: modality.rawValue) != nil)
            // …but not standard, so the conventional-code branch fires.
            #expect(modality.isStandard == false)
            #expect(modality.isRetired == false)
        }
    }

    // MARK: - Enhanced multi-frame helper

    @Test("Frame Type descriptors apply to exactly CT, MR and PT")
    func testEnhancedFrameTypeDescriptors() {
        #expect(Modality.ct.usesEnhancedFrameTypeDescriptors)
        #expect(Modality.mr.usesEnhancedFrameTypeDescriptors)
        #expect(Modality.pt.usesEnhancedFrameTypeDescriptors)
        for modality in [Modality.xa, .rf, .us, .nm, .ot, .seg] {
            #expect(!modality.usesEnhancedFrameTypeDescriptors,
                    "\(modality.rawValue) should not carry Frame Type descriptors")
        }
    }

    // MARK: - Protocol conformances

    @Test("Codable round-trips through JSON")
    func testCodableRoundTrip() throws {
        let original = [Modality.ct, .opt, .rtplan, Modality(unchecked: "PRIVATE")]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([Modality].self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable encodes as a bare string")
    func testCodableEncodesAsString() throws {
        let data = try JSONEncoder().encode(Modality.ct)
        #expect(String(data: data, encoding: .utf8) == "\"CT\"")
    }

    @Test("Equality and hashing are by canonical code")
    func testEqualityAndHashing() {
        #expect(Modality(unchecked: "ct") == Modality.ct)
        #expect(Set([Modality.ct, Modality(unchecked: "CT")]).count == 1)
    }

    @Test("description is the raw code")
    func testDescription() {
        #expect(Modality.ct.description == "CT")
        #expect("\(Modality.opt)" == "OPT")
    }

    @Test("Named constants match their raw values")
    func testNamedConstantsValid() {
        // Catches a typo in any static constant: each must be a known code.
        let constants: [Modality] = [
            .ct, .mr, .nm, .pt, .ctprotocol,
            .cr, .dx, .rg, .mg, .px, .io, .xa, .rf, .bmd, .xaprotocol,
            .us, .ivus, .bdus,
            .es, .gm, .sm, .cfm, .xc, .dms, .stain,
            .op, .opt, .optenf, .optbsv, .opm, .oam, .opv, .oct, .ivoct,
            .ar, .ker, .len, .srf, .va, .iol,
            .ecg, .eeg, .emg, .eog, .eps, .hd, .resp, .au,
            .rtimage, .rtdose, .rtstruct, .rtplan, .rtrecord, .rtintent,
            .rtrad, .rtsegann,
            .sr, .pr, .ko, .seg, .reg, .rwv, .ann, .fid, .doc, .m3d,
            .plan, .asmt, .smr, .texturemap, .hc, .pos,
            .ot, .bi, .dg, .ls, .oss, .pa, .tg,
            .sc, .vl,
        ]
        for constant in constants {
            #expect(Modality(rawValue: constant.rawValue) != nil,
                    "constant \(constant.rawValue) is not in the definition table")
        }
        // 79 current + SC + VL
        #expect(constants.count == 81)
        #expect(Set(constants).count == 81, "duplicate named constant")
    }
}
