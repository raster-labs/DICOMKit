import XCTest
import Foundation
import DICOMCore
@testable import DICOMKit

/// Classifier pins (PIXEL_ANONYMIZATION_PIPELINE.md §10.5). The failure direction is
/// the point: anything not provably safe is redacted.
final class PHITextClassifierTests: XCTestCase {

    private func header() -> DataSet {
        var ds = DataSet()
        ds.setString("SMITH^JOHN", for: .patientName, vr: .PN)
        ds.setString("0012345", for: .patientID, vr: .LO)
        ds.setString("19611203", for: .patientBirthDate, vr: .DA)
        ds.setString("20240115", for: .studyDate, vr: .DA)
        ds.setString("ACC4521", for: .accessionNumber, vr: .SH)
        ds.setString("General Hospital", for: .institutionName, vr: .LO)
        ds.setString("DOE^JANE^M", for: .referringPhysicianName, vr: .PN)
        ds.setString("045Y", for: .patientAge, vr: .AS)
        return ds
    }

    private func classifier() -> PHITextClassifier {
        PHITextClassifier(terms: PHITextClassifier.harvestTerms(from: header()))
    }

    // MARK: - Harvest

    func testHarvestCoversNamesIDsDatesInstitutionAndAge() {
        let t = PHITextClassifier.harvestTerms(from: header())
        for expected in ["SMITH", "JOHN", "SMITHJOHN", "JOHNSMITH", "JSMITH", "0012345", "12345",
                         "ACC4521", "GENERALHOSPITAL", "GENERAL", "HOSPITAL", "DOE", "JANE"] {
            XCTAssertTrue(t.identifiers.contains(expected), "missing \(expected) in \(t.identifiers)")
        }
        for expected in ["19611203", "12031961", "03121961", "120361", "3DEC1961", "03DEC1961",
                         "20240115", "01152024", "15012024", "45Y", "045Y"] {
            XCTAssertTrue(t.derived.contains(expected), "missing \(expected) in \(t.derived)")
        }
        XCTAssertFalse(t.derived.contains("45"), "a bare age would match inside any ID")
    }

    func testHarvestIgnoresTooShortTermsThatWouldMatchEverything() {
        var ds = DataSet()
        ds.setString("LI^WU", for: .patientName, vr: .PN)
        ds.setString("7", for: .patientID, vr: .LO)
        let t = PHITextClassifier.harvestTerms(from: ds)
        XCTAssertFalse(t.identifiers.contains("LI"))
        XCTAssertFalse(t.identifiers.contains("7"))
        XCTAssertTrue(t.identifiers.contains("LIWU"), "the joined form still catches the full name")
    }

    // MARK: - Fuzz table

    func testNameVariantsAreRedacted() {
        let c = classifier()
        for text in ["SMITH^JOHN", "John Smith", "SMITH, JOHN", "J. Smith", "J SMITH", "Smith",
                     "SM1TH J0HN", "SMlTH", "SMITH JOHN 45Y", "JOHN SMITH 12/03/1961"] {
            XCTAssertTrue(c.classify(text, confidence: 0.99).isRedact, text)
        }
    }

    func testIDAndDateVariantsAreRedacted() {
        let c = classifier()
        for text in ["0012345", "12345", "MRN 0012345", "ACC4521", "ACC 4521", "12/03/1961", "1961-12-03",
                     "03-DEC-1961", "3 Dec 1961", "19611203", "15/01/2024", "45Y", "General Hospital", "GENERAL H0SPITAL"] {
            XCTAssertTrue(c.classify(text, confidence: 0.99).isRedact, text)
        }
    }

    func testPatternsFireWithoutAnyHeaderTerms() {
        let c = PHITextClassifier()   // no harvest
        for text in ["07/04/1985", "1985-07-04", "04-JUL-1985", "20200101", "987654", "AB123456", "12:34:56", "10:05"] {
            let v = c.classify(text, confidence: 0.99)
            XCTAssertTrue(v.isRedact, text)
            XCTAssertTrue(v.reason.hasPrefix("pattern:"), "\(text): \(v.reason)")
        }
    }

    func testKeywordProximityTaintsTheLine() {
        let c = PHITextClassifier()
        for text in ["Pt: R", "Name: cm", "DOB", "Acc# 12", "MRN", "Dr. L"] {
            let v = c.classify(text, confidence: 0.99)
            XCTAssertTrue(v.isRedact, text)
        }
    }

    // MARK: - Allowlist

    func testAllowlistedClinicalTextIsKept() {
        let c = classifier()
        for text in ["R", "L", "RT", "LT", "10 cm", "120 kVp", "2.5mm", "W 400 L 40", "AXIAL T2", "FOV 24 cm", "1.5T", "100"] {
            let v = c.classify(text, confidence: 0.95)
            XCTAssertFalse(v.isRedact, "\(text): \(v.reason)")
            XCTAssertTrue(v.reason.hasPrefix("allowlist:"), v.reason)
        }
    }

    /// The OCR engine fuses a ruler tick into the numeral beside it (`10` + tick →
    /// `10y`, verified on a GE Vivid S70 Doppler frame, single candidate at 1.00).
    /// Only ON a declared Ultrasound Region is that one trailing glyph forgiven; the
    /// same text in a banner is still an age and still redacted, and steps 1–3 still
    /// win inside the zone.
    func testTickGlyphOnAScaleNumeralIsForgivenOnlyOnADeclaredRegion() {
        typealias Region = PixelRedactionPlan.Region
        let zone = Region(x: 389, y: 50, width: 236, height: 204)          // the sector
        let onScale = Region(x: 400, y: 130, width: 45, height: 33)         // "10" + tick
        let banner = Region(x: 700, y: 2, width: 40, height: 25)            // top strip
        let c = PHITextClassifier(terms: PHITextClassifier.harvestTerms(from: header()), scaleZones: [zone])

        // A LETTER glyph is the case that matters: it is exactly what an age looks like.
        for text in ["10y", "+10y", "15y", "-5v", "2.5y"] {
            let on = c.classifyDetailed(text, confidence: 1, region: onScale).verdict
            XCTAssertFalse(on.isRedact, "\(text) on the scale: \(on.reason)")
            XCTAssertTrue(on.reason.contains("trailing tick glyph ignored"), on.reason)
            let off = c.classifyDetailed(text, confidence: 1, region: banner).verdict
            XCTAssertTrue(off.isRedact, "\(text) in the banner must stay redacted: \(off.reason)")
            XCTAssertEqual(off.reason, "uncertain: not on the allowlist")
        }
        // A punctuation glyph (`15}`, `-5)`) never needed the rule: the tokenizer
        // treats punctuation as a separator, so it is a bare numeral anywhere.
        for text in ["15}", "-5)", "2.5|"] {
            XCTAssertEqual(c.classifyDetailed(text, confidence: 1, region: banner).verdict.reason, "allowlist: numeral/unit")
        }
        // No region, or no zones: the rule is off.
        XCTAssertTrue(c.classifyDetailed("10y", confidence: 1).verdict.isRedact)
        XCTAssertTrue(PHITextClassifier().classifyDetailed("10y", confidence: 1, region: onScale).verdict.isRedact)
        // Two trailing glyphs, four digits, or an ID run are not ticks.
        for text in ["10yo", "1234y", "12345y", "y10", "SMITH"] {
            XCTAssertTrue(c.classifyDetailed(text, confidence: 1, region: onScale).verdict.isRedact, text)
        }
        // Steps 1–3 still win on the scale: header age, a date, a PHI keyword.
        XCTAssertEqual(c.classifyDetailed("45Y", confidence: 1, region: onScale).verdict.reason, "matched header date/age")
        XCTAssertTrue(c.classifyDetailed("12/03/1961", confidence: 1, region: onScale).verdict.isRedact)
        XCTAssertTrue(c.classifyDetailed("DOB 10y", confidence: 1, region: onScale).verdict.isRedact)
        // Low confidence never lets it pass.
        XCTAssertTrue(c.classifyDetailed("10y", confidence: 0.2, region: onScale).verdict.isRedact)
        // header policy is unaffected (it kept it anyway).
        let h = PHITextClassifier(terms: PHITextClassifier.harvestTerms(from: header()), policy: .header, scaleZones: [zone])
        XCTAssertFalse(h.classifyDetailed("10y", confidence: 1, region: banner).verdict.isRedact)
    }

    // MARK: - header policy

    /// `header` redacts only what the study's own header (or a PHI-shaped pattern)
    /// ties to the pixels; everything else — including text `classify` would call
    /// uncertain — is kept. The mode is fail-open and the reasons say so.
    func testHeaderPolicyKeepsEverythingNotTiedToTheHeader() {
        let c = PHITextClassifier(terms: PHITextClassifier.harvestTerms(from: header()), policy: .header)
        // Still redacted: header PHI in burned forms, and PHI-shaped patterns.
        for text in ["SMITH JOHN", "J SMITH", "0012345", "12345", "03/12/1961", "General Hospital",
                     "Dr Doe", "45Y", "09/09/2001", "12:34:56", "987654321", "AB12CD34"] {
            XCTAssertTrue(c.classify(text, confidence: 0.99).isRedact, text)
        }
        // Kept: allowlisted clinical text AND text classify would redact as uncertain/keyword.
        for text in ["10", "- 5", "[cm/s]", "Soft", "10y", "Zebra", "Tls 0.5", "4Vc", "66.67 mm/s",
                     "Patient position supine", "Tech notes"] {
            let v = c.classify(text, confidence: 0.99)
            XCTAssertFalse(v.isRedact, "\(text): \(v.reason)")
            XCTAssertTrue(v.reason.hasPrefix("header mode:"), v.reason)
        }
        // Low confidence: a fuzzy header hit still redacts; otherwise keep, saying why.
        XCTAssertTrue(c.classify("SM1TH", confidence: 0.2).isRedact)
        let low = c.classify("Zebra", confidence: 0.2)
        XCTAssertFalse(low.isRedact)
        XCTAssertTrue(low.reason.contains("low OCR confidence"), low.reason)
        XCTAssertFalse(c.classify("", confidence: 0.99).isRedact, "unreadable text is kept in header mode")
    }

    /// Ordering pin: header ⊆ classify — nothing `header` redacts is kept by `classify`.
    func testHeaderRedactionsAreASubsetOfClassifyRedactions() {
        let terms = PHITextClassifier.harvestTerms(from: header())
        let h = PHITextClassifier(terms: terms, policy: .header)
        let k = PHITextClassifier(terms: terms, policy: .classify)
        let corpus = ["SMITH JOHN", "0012345", "03/12/1961", "Dr Doe", "45Y", "12:34", "987654321",
                      "10", "- 5", "[cm/s]", "Soft", "10y", "Zebra", "Tls 0.5", "R", "", "MI 1.1",
                      "Pt: Zebra", "General Hospital", "AB12CD34", "120 kVp"]
        for text in corpus where h.classify(text, confidence: 0.99).isRedact {
            XCTAssertTrue(k.classify(text, confidence: 0.99).isRedact, "\(text): header redacts but classify keeps")
        }
        for text in corpus where h.classify(text, confidence: 0.3).isRedact {
            XCTAssertTrue(k.classify(text, confidence: 0.3).isRedact, "\(text) @0.3: header redacts but classify keeps")
        }
    }

    /// `header` still reports the matched attributes, so `replace` style works with it.
    func testHeaderPolicyReportsMatchedTags() {
        let c = PHITextClassifier(terms: PHITextClassifier.harvestTerms(from: header()), policy: .header)
        XCTAssertEqual(c.classifyDetailed("SMITH JOHN 0012345", confidence: 0.99).matchedTags, [.patientName, .patientID])
        XCTAssertEqual(c.classifyDetailed("Soft", confidence: 0.99).matchedTags, [])
    }

    /// OCR reads GE's thermal indices `TIs`/`TIb` with a lowercase L; those are technical.
    func testThermalIndexMisreadsAreAllowlisted() {
        let c = classifier()
        for text in ["Tls 0.5", "TIs 0.5", "TIb 1.2", "Tlb 1.2", "MI 1.1 TIS 0.7"] {
            let v = c.classify(text, confidence: 0.99)
            XCTAssertFalse(v.isRedact, "\(text): \(v.reason)")
        }
    }

    func testUncertainTextIsRedactedNeverKept() {
        let c = classifier()
        XCTAssertTrue(c.classify("R", confidence: 0.2).isRedact, "low confidence never passes")
        XCTAssertTrue(c.classify("Zebra", confidence: 0.99).isRedact, "unknown word is uncertain")
        XCTAssertTrue(c.classify("", confidence: 0.99).isRedact)
        XCTAssertTrue(c.classify("R cm Zebra", confidence: 0.99).isRedact, "one unknown token taints")
        XCTAssertTrue(c.classify("SMITH R", confidence: 0.99).isRedact, "PHI beats the allowlist")
        XCTAssertTrue(c.classify("123456789", confidence: 0.99).isRedact, "long digit runs are IDs")
    }

    func testMatchedTagsReportEveryAttributeFoundInTextOrder() {
        let c = classifier()
        let r = c.classifyDetailed("SMITH JOHN MRN 0012345 12/03/1961", confidence: 0.99)
        XCTAssertTrue(r.verdict.isRedact)
        XCTAssertEqual(r.matchedTags, [.patientName, .patientID, .patientBirthDate])
        XCTAssertEqual(c.classifyDetailed("R 10 cm", confidence: 0.99).matchedTags, [])
        XCTAssertEqual(c.classifyDetailed("07/04/1985", confidence: 0.99).matchedTags, [], "a bare pattern has no attribute")
        XCTAssertEqual(c.classifyDetailed("SMITH", confidence: 0.1).matchedTags, [], "uncertain never carries a match")
    }

    func testFuzzyMatchingIsBoundedNotUnbounded() {
        // One substitution matches a 5-letter term; three do not.
        XCTAssertTrue(PHITextClassifier.fuzzyContains(haystack: "SMYTH", needle: "SMITH"))
        XCTAssertFalse(PHITextClassifier.fuzzyContains(haystack: "SXYZH", needle: "SMITH"))
        // Short terms need an exact substring.
        XCTAssertFalse(PHITextClassifier.fuzzyContains(haystack: "DOG", needle: "DOE"))
        XCTAssertTrue(PHITextClassifier.fuzzyContains(haystack: "JANEDOE", needle: "DOE"))
    }

    func testDateRenderings() {
        let forms = PHITextClassifier.renderedDateForms("19611203")
        for f in ["19611203", "12/03/1961", "03/12/1961", "1961-12-03", "03-DEC-1961", "3-DEC-1961", "12/3/61", "03.12.1961"] {
            XCTAssertTrue(forms.contains(f), f)
        }
        XCTAssertTrue(PHITextClassifier.renderedDateForms("1961").isEmpty)
    }
}
