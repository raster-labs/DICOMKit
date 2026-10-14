import Foundation
import DICOMCore

/// Decides, for text OCR found in the pixels, whether it is PHI (redact) or provably
/// safe clinical/technical annotation (keep).
///
/// ## Failure direction is pinned
///
/// There are two verdicts and the default is **redact**. Text is kept **only** when
/// every token is positively matched against a small allowlist (laterality, units,
/// technique factors, bare scale numerals) *and* nothing about it matches a harvested
/// PHI term, a PHI-shaped pattern, or a PHI keyword. Low OCR confidence never lets text
/// pass. Classification can therefore only make redaction *less* aggressive than
/// `all` — text Vision missed never reaches this type — so classify mode is never
/// safer than `all`, only more preserving.
///
/// ## Term harvest runs BEFORE header de-identification
///
/// ``harvestTerms(from:)`` reads PatientName, IDs, accession, institution, physician
/// and operator names, dates and age from the **original** header — attributes the
/// header pass deletes — and renders them in the forms devices burn into images.
public struct PHITextClassifier: Sendable, Equatable {

    /// PHI strings harvested from the original header, already normalized
    /// (uppercase, alphanumerics only) and OCR-confusion folded.
    public struct Terms: Sendable, Equatable {
        /// Names, IDs, institution — matched fuzzily.
        public var identifiers: [String]
        /// Dates and ages rendered in burned formats — matched exactly after normalization.
        public var derived: [String]
        /// Which header attribute each term came from (for semantic replacement).
        public var sourceTags: [String: Tag]

        public init(identifiers: [String] = [], derived: [String] = [], sourceTags: [String: Tag] = [:]) {
            self.identifiers = identifiers
            self.derived = derived
            self.sourceTags = sourceTags
        }

        public var isEmpty: Bool { identifiers.isEmpty && derived.isEmpty }
    }

    public enum Verdict: Sendable, Equatable {
        case redact(reason: String)
        case keep(reason: String)

        public var isRedact: Bool {
            if case .redact = self { return true }
            return false
        }
        public var reason: String {
            switch self {
            case .redact(let r), .keep(let r): return r
            }
        }
        public var name: String { isRedact ? "redact" : "keep" }
    }

    /// A verdict plus the header attributes whose values were found in the text — the
    /// only basis on which a `replace` style may substitute a value.
    public struct Classification: Sendable, Equatable {
        public let verdict: Verdict
        /// Header tags matched, in order of first occurrence; empty for pattern/keyword/
        /// uncertain verdicts (those never get semantic replacement).
        public let matchedTags: [Tag]
    }

    /// Which of the four decision steps run.
    ///
    /// - `classify` (default): all four — header matches, PHI-shaped patterns, PHI
    ///   keywords, then keep **only** allowlisted text. Fails closed.
    /// - `header`: header matches and PHI-shaped patterns only; everything else is
    ///   kept. Fails **open** — text not present in the header (a sticker, a second
    ///   patient, a RIS-entered name the modality never received) passes. The mode
    ///   exists so scales, legends and free annotations survive on images where the
    ///   operator accepts that limit; it never earns more than `classify` does.
    public enum Policy: String, Sendable, Equatable {
        case classify
        case header
    }

    /// OCR confidence below this is treated as uncertain → redact, whatever the text.
    public static let defaultMinimumConfidence: Float = 0.5

    public var terms: Terms
    public var minimumConfidence: Float
    public var policy: Policy
    /// Pixel rectangles the file itself declares as calibrated image content
    /// (Sequence of Ultrasound Regions). Vendors draw the depth/velocity/time scale
    /// along their edges, and the OCR engine reads a ruler tick that touches a numeral
    /// as a trailing glyph (`10` + tick → `10y`, `15` + tick → `15}`). Only there does
    /// ``classify(_:confidence:)``'s allowlist forgive ONE such trailing glyph on a
    /// short numeral; a banner outside every declared region gets no such forgiveness,
    /// so an age like `72y` in a banner is still redacted. Empty = rule off.
    public var scaleZones: [PixelRedactionPlan.Region]

    public init(terms: Terms = Terms(), minimumConfidence: Float = PHITextClassifier.defaultMinimumConfidence,
                policy: Policy = .classify, scaleZones: [PixelRedactionPlan.Region] = []) {
        self.terms = terms
        self.minimumConfidence = minimumConfidence
        self.policy = policy
        self.scaleZones = scaleZones
    }

    // MARK: - Allowlist

    /// Tokens that are provably clinical/technical when they stand alone.
    static let allowlistedTokens: Set<String> = [
        // laterality / orientation markers
        "L", "R", "LT", "RT", "LEFT", "RIGHT", "A", "P", "S", "I", "H", "F", "AP", "PA", "LAT",
        "ANT", "POST", "SUP", "INF", "MED", "LATERAL", "MEDIAL", "OBL", "SUPINE", "PRONE",
        // units
        "CM", "MM", "M", "UM", "KG", "G", "MG", "ML", "L", "MS", "S", "MIN", "HZ", "KHZ", "MHZ", "DB",
        "DEG", "FPS", "BPM", "MGY", "GY", "MSV", "SV", "MAS", "MA", "KV", "KVP", "MV", "W", "T", "PPM",
        // technique / display labels
        "KVP", "MAS", "FOV", "TR", "TE", "TI", "TA", "SL", "THK", "SP", "NEX", "FA", "ETL", "BW",
        "WW", "WL", "WC", "WIN", "LEV", "ZOOM", "MAG", "SCALE", "DEPTH", "GAIN", "MI", "TIS", "TIB", "TIC",
        "TLS", "TLB", "TLC",   // OCR's lowercase-L reading of TIs / TIb / TIc (thermal indices)
        "FR", "FRQ", "FREQ", "PRF", "DR", "GN", "DYN", "MHZ", "HR",
        "AXIAL", "SAGITTAL", "CORONAL", "AX", "SAG", "COR", "TRA",
        "T1", "T2", "PD", "FLAIR", "DWI", "ADC", "STIR", "SWI", "TOF", "MIP", "MPR",
        "SOFT", "BONE", "LUNG", "BRAIN", "TISSUE", "WINDOW", "LEVEL", "KERNEL",
        "B", "X", "Y", "Z", "MM2", "MM3", "CM2", "CM3", "CC", "IN", "PX",
    ]

    /// Units that may be glued to a numeral (`120KVP`, `10CM`, `2.5MM`).
    static let allowlistedUnits: Set<String> = [
        "CM", "MM", "M", "UM", "KG", "G", "MG", "ML", "L", "MS", "S", "MIN", "HZ", "KHZ", "MHZ", "DB",
        "DEG", "FPS", "BPM", "MGY", "GY", "MSV", "SV", "MAS", "MA", "KV", "KVP", "MV", "W", "T", "PPM",
        "X", "MM2", "MM3", "CM2", "CM3", "CC", "IN", "PX", "FPS",
    ]

    /// Words that mark identifying content on the same line (`Pt:`, `Name:`, `DOB`, …).
    static let phiKeywords: Set<String> = [
        "PT", "PATIENT", "NAME", "DOB", "BIRTH", "BORN", "ACC", "ACCESSION", "MRN", "ID", "PID",
        "AGE", "SEX", "DR", "MD", "DOCTOR", "PHYSICIAN", "REF", "REFERRING", "HOSPITAL", "CLINIC",
        "CENTER", "CENTRE", "MEDICAL", "INSTITUTE", "UNIVERSITY", "RADIOLOGY", "IMAGING",
        "MR", "MRS", "MS", "MISS", "PROF", "STUDY", "EXAM", "DATE", "TIME", "OPERATOR", "TECH",
        "SONOGRAPHER", "ADDRESS", "PHONE", "TEL", "SSN", "DOD", "STATION",
    ]

    // MARK: - Harvest

    /// Harvests PHI terms from the **original** (not yet de-identified) data set.
    public static func harvestTerms(from dataSet: DataSet) -> Terms {
        var identifiers = Set<String>()
        var derived = Set<String>()
        var sourceTags: [String: Tag] = [:]
        func note(_ term: String, _ tag: Tag) { if sourceTags[term] == nil { sourceTags[term] = tag } }

        func value(_ tag: Tag) -> String? {
            dataSet.string(for: tag)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        func values(_ tag: Tag) -> [String] {
            (dataSet[tag]?.stringValues ?? [value(tag)].compactMap { $0 })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // Person names: every component, and the joined forms in both orders.
        let nameTags: [Tag] = [
            .patientName, .otherPatientNames, .referringPhysicianName, .performingPhysicianName,
            Tag(group: 0x0008, element: 0x1070),   // Operators' Name
            Tag(group: 0x0008, element: 0x1048),   // Physician(s) of Record
            Tag(group: 0x0008, element: 0x1060),   // Name of Physician(s) Reading Study
            .requestingPhysician,
        ]
        for tag in nameTags {
            for pn in values(tag) {
                // Drop ideographic/phonetic groups; split components on "^".
                let alphabetic = pn.split(separator: "=", omittingEmptySubsequences: false).first.map(String.init) ?? pn
                let components = alphabetic.split(separator: "^").map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for c in components {
                    // A component may itself hold several words ("JOHN PAUL").
                    for word in c.split(whereSeparator: { $0 == " " || $0 == "-" }) {
                        let n = normalize(String(word))
                        if n.count >= 3 { identifiers.insert(n); note(n, tag) }
                    }
                    let n = normalize(c)
                    if n.count >= 3 { identifiers.insert(n); note(n, tag) }
                }
                if components.count >= 2 {
                    for form in [normalize(components.joined()),                        // SMITHJOHN
                                 normalize(components.reversed().joined()),             // JOHNSMITH
                                 normalize(components[1].prefix(1) + components[0])] {  // JSMITH
                        identifiers.insert(form); note(form, tag)
                    }
                }
            }
        }

        // Identifiers: IDs, accession, institution, department, station.
        let idTags: [Tag] = [
            .patientID, .otherPatientIDs, .accessionNumber, .institutionName,
            .institutionalDepartmentName, .stationName,
            Tag(group: 0x0020, element: 0x0010),   // Study ID
        ]
        for tag in idTags {
            for raw in values(tag) {
                let n = normalize(raw)
                guard n.count >= 3 else { continue }
                identifiers.insert(n); note(n, tag)
                // MRN with and without leading zeros.
                let stripped = String(n.drop(while: { $0 == "0" }))
                if stripped.count >= 3 { identifiers.insert(stripped); note(stripped, tag) }
                // Multi-word institutions: each significant word too.
                for word in raw.split(separator: " ") {
                    let w = normalize(String(word))
                    if w.count >= 5 { identifiers.insert(w); note(w, tag) }
                }
            }
        }

        // Dates in the formats devices burn.
        let dateTags: [Tag] = [.patientBirthDate, .studyDate, .seriesDate, .acquisitionDate, .contentDate]
        for tag in dateTags {
            for raw in values(tag) {
                for rendered in renderedDateForms(raw) {
                    let n = normalize(rendered)
                    derived.insert(n); note(n, tag)
                }
            }
        }
        // Patient age: 045Y → 45Y, 45.
        if let age = value(.patientAge) {
            let digits = age.filter(\.isNumber)
            let unit = age.filter(\.isLetter)
            let n = String(Int(digits) ?? -1)
            // Only the unit-bearing forms: a bare "45" would match inside any ID.
            if n != "-1", !unit.isEmpty {
                for form in [normalize(n + unit), normalize(digits + unit)] {
                    derived.insert(form); note(form, .patientAge)
                }
            }
        }

        return Terms(identifiers: identifiers.sorted(), derived: derived.sorted(), sourceTags: sourceTags)
    }

    /// Common burned renderings of a DICOM DA value (`YYYYMMDD`).
    static func renderedDateForms(_ da: String) -> [String] {
        let digits = da.filter(\.isNumber)
        guard digits.count == 8, let y = Int(digits.prefix(4)),
              let m = Int(digits.dropFirst(4).prefix(2)), let d = Int(digits.suffix(2)),
              (1...12).contains(m), (1...31).contains(d)
        else { return [] }
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        let mon = months[m - 1]
        let yy = String(format: "%02d", y % 100)
        let mm = String(format: "%02d", m), dd = String(format: "%02d", d)
        return [
            digits,                                  // 19611203
            "\(y)-\(mm)-\(dd)", "\(y)/\(mm)/\(dd)", "\(y).\(mm).\(dd)",
            "\(mm)/\(dd)/\(y)", "\(dd)/\(mm)/\(y)", "\(mm)-\(dd)-\(y)", "\(dd)-\(mm)-\(y)",
            "\(dd).\(mm).\(y)", "\(m)/\(d)/\(y)", "\(d)/\(m)/\(y)",
            "\(mm)/\(dd)/\(yy)", "\(dd)/\(mm)/\(yy)", "\(m)/\(d)/\(yy)", "\(d)/\(m)/\(yy)",
            "\(dd)-\(mon)-\(y)", "\(d)-\(mon)-\(y)", "\(dd) \(mon) \(y)", "\(mon) \(dd) \(y)",
            "\(mon) \(d), \(y)", "\(dd)\(mon)\(y)", "\(dd)-\(mon)-\(yy)",
        ]
    }

    // MARK: - Normalization

    /// Uppercase, alphanumerics only, PN separators and punctuation dropped.
    public static func normalize(_ text: String) -> String {
        String(text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Folds the classic OCR substitutions so `SM1TH` matches `SMITH` and `O`↔`0`.
    static func foldConfusions(_ normalized: String) -> String {
        var out = ""
        out.reserveCapacity(normalized.count)
        for ch in normalized {
            switch ch {
            case "0", "O", "Q", "D": out.append("0")
            case "1", "I", "L", "|": out.append("1")
            case "5", "S": out.append("5")
            case "8", "B": out.append("8")
            case "2", "Z": out.append("2")
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - Classification

    /// Classifies one recognized string.
    public func classify(_ text: String, confidence: Float) -> Verdict {
        classifyDetailed(text, confidence: confidence).verdict
    }

    /// Classifies one recognized string and reports which header attributes matched.
    /// `region` is where the text sits; it only matters for the scale-zone rule.
    public func classifyDetailed(_ text: String, confidence: Float,
                                 region: PixelRedactionPlan.Region? = nil) -> Classification {
        let uncertain = confidence < minimumConfidence
        // `classify` refuses to reason about text it cannot read; `header` still tries
        // the matches (a fuzzy hit on garbled PHI is the safe direction) and otherwise
        // keeps — that is the mode's contract.
        if uncertain, policy == .classify {
            return Classification(verdict: .redact(reason: "uncertain: OCR confidence \(String(format: "%.2f", confidence)) below \(String(format: "%.2f", minimumConfidence))"), matchedTags: [])
        }
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else {
            if policy == .header {
                return Classification(verdict: .keep(reason: "header mode: no recognizable characters"), matchedTags: [])
            }
            return Classification(verdict: .redact(reason: "uncertain: no recognizable characters"), matchedTags: [])
        }
        let folded = Self.foldConfusions(normalized)

        // 1. Harvested PHI terms (fuzzy). Collect EVERY matching attribute so a line
        //    carrying name + ID + date can be replaced item by item.
        var matched: [(Int, Tag)] = []
        var reasons: [String] = []
        for term in terms.identifiers {
            let needle = Self.foldConfusions(term)
            if let position = Self.fuzzyPosition(haystack: folded, needle: needle) {
                if reasons.isEmpty { reasons.append("matched header identifier") }
                if let tag = terms.sourceTags[term] { matched.append((position, tag)) }
            }
        }
        for term in terms.derived {
            if let range = folded.range(of: Self.foldConfusions(term)) {
                if !reasons.contains("matched header date/age") { reasons.append("matched header date/age") }
                if let tag = terms.sourceTags[term] {
                    matched.append((folded.distance(from: folded.startIndex, to: range.lowerBound), tag))
                }
            }
        }
        if !reasons.isEmpty {
            var seen = Set<Tag>()
            let tags = matched.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
            return Classification(verdict: .redact(reason: reasons.joined(separator: "; ")), matchedTags: tags)
        }

        // 2. PHI-shaped patterns (no header source needed).
        if let pattern = Self.phiPattern(in: text) {
            return Classification(verdict: .redact(reason: "pattern: \(pattern)"), matchedTags: [])
        }

        // `header` stops here: nothing tied it to this study's PHI, so it stays.
        if policy == .header {
            let note = uncertain ? " (low OCR confidence \(String(format: "%.2f", confidence)))" : ""
            return Classification(verdict: .keep(reason: "header mode: no header match or PHI pattern" + note), matchedTags: [])
        }

        // 3. Keyword proximity: a PHI label on the line taints the whole line.
        let tokens = Self.tokens(of: text)
        if let keyword = tokens.first(where: { Self.phiKeywords.contains($0) }) {
            return Classification(verdict: .redact(reason: "near PHI keyword \(keyword)"), matchedTags: [])
        }

        // 4. Keep ONLY when every token is positively allowlisted.
        if !tokens.isEmpty, tokens.allSatisfy(Self.isAllowlisted) {
            return Classification(verdict: .keep(reason: "allowlist: " + Self.allowlistCategory(tokens)), matchedTags: [])
        }
        // 4b. A short numeral with ONE trailing glyph, sitting on a declared scale zone:
        //     the glyph is the ruler tick the OCR engine fused into the word. Steps 1–3
        //     ran first, so a header match, a PHI pattern or a keyword still wins.
        if let region, Self.isScaleNumeralWithTickGlyph(text), scaleZones.contains(where: { $0.intersects(region) }) {
            return Classification(verdict: .keep(reason: "allowlist: scale numeral on a declared ultrasound region (trailing tick glyph ignored)"), matchedTags: [])
        }
        return Classification(verdict: .redact(reason: "uncertain: not on the allowlist"), matchedTags: [])
    }

    /// `10y`, `15}`, `-5)`, `2.5|`: an optionally signed numeral of at most three
    /// integer digits, then exactly one character that is not a digit. Two trailing
    /// characters (`10cm` is handled by the unit allowlist; `10yo` is not a tick) fail.
    static func isScaleNumeralWithTickGlyph(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, !last.isNumber, !last.isWhitespace else { return false }
        var body = Substring(t.dropLast())
        if let sign = body.first, sign == "-" || sign == "+" || sign == "–" { body = body.dropFirst() }
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber || $0 == "." }), Double(body) != nil else { return false }
        let integerDigits = body.split(separator: ".", omittingEmptySubsequences: false).first?.count ?? 0
        return integerDigits >= 1 && integerDigits <= 3
    }

    /// Classifies every detection.
    public func classify(_ detections: [TextRegionDetector.Detection]) -> [Verdict] {
        detections.map { classify($0.text, confidence: $0.confidence) }
    }

    /// Classifies every detection with matched attributes.
    public func classifyDetailed(_ detections: [TextRegionDetector.Detection]) -> [Classification] {
        detections.map { classifyDetailed($0.text, confidence: $0.confidence, region: $0.region) }
    }

    // MARK: Helpers

    static func tokens(of text: String) -> [String] {
        text.uppercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." ) })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    static func isAllowlisted(_ token: String) -> Bool {
        if allowlistedTokens.contains(token) { return true }
        // Numeral, optionally decimal, optionally with a glued unit: 120, 2.5, 10CM, 120KVP.
        let digits = token.prefix(while: { $0.isNumber || $0 == "." })
        let rest = String(token.dropFirst(digits.count))
        guard !digits.isEmpty, Double(digits) != nil else { return false }
        let integerDigits = digits.split(separator: ".").first.map { $0.count } ?? 0
        guard integerDigits <= 4 else { return false }               // longer runs are IDs
        return rest.isEmpty || allowlistedUnits.contains(rest)
    }

    static func allowlistCategory(_ tokens: [String]) -> String {
        if tokens.allSatisfy({ ["L", "R", "LT", "RT", "LEFT", "RIGHT"].contains($0) }) { return "laterality" }
        if tokens.allSatisfy({ Double($0.prefix(while: { $0.isNumber || $0 == "." })) != nil }) { return "numeral/unit" }
        return "technical label"
    }

    /// Returns the name of the first PHI-shaped pattern found, or nil.
    static func phiPattern(in text: String) -> String? {
        let upper = text.uppercased()
        let patterns: [(String, String)] = [
            ("date", #"\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b"#),
            ("date", #"\b\d{4}[/.\-]\d{1,2}[/.\-]\d{1,2}\b"#),
            ("date", #"\b\d{1,2}[ \-]?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*[ \-,]*\d{2,4}\b"#),
            ("date", #"\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*[ \-]?\d{1,2}[ ,\-]+\d{2,4}\b"#),
            ("date", #"\b(19|20)\d{6}\b"#),
            ("time", #"\b\d{1,2}:\d{2}(:\d{2})?\b"#),
            ("long digit run (ID)", #"\d{5,}"#),
            ("mixed alphanumeric ID", #"\b(?=[A-Z0-9\-]{6,}\b)(?=[A-Z\-]*\d)(?=[\d\-]*[A-Z])[A-Z0-9\-]+\b"#),
        ]
        for (name, pattern) in patterns {
            if upper.range(of: pattern, options: .regularExpression) != nil { return name }
        }
        return nil
    }

    /// Normalized-substring, else any window of `needle.count` (±1) within `haystack`
    /// at bounded edit distance (1 for short terms, 2 for 8+ characters).
    static func fuzzyContains(haystack: String, needle: String) -> Bool {
        fuzzyPosition(haystack: haystack, needle: needle) != nil
    }

    /// Character offset of the (fuzzy) match, or nil.
    static func fuzzyPosition(haystack: String, needle: String) -> Int? {
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        if let r = haystack.range(of: needle) {
            return haystack.distance(from: haystack.startIndex, to: r.lowerBound)
        }
        guard needle.count >= 4 else { return nil }
        let budget = needle.count >= 8 ? 2 : 1
        let h = Array(haystack), n = Array(needle)
        for width in max(1, n.count - 1)...(n.count + 1) where width <= h.count {
            for start in 0...(h.count - width) {
                if editDistance(Array(h[start..<(start + width)]), n, limit: budget) <= budget { return start }
            }
        }
        return nil
    }

    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(1, a.count) where i <= a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...max(1, b.count) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return a.isEmpty ? b.count : prev[b.count]
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
