// NEMA-verified: 2026a, checked 2026-10-01 — the 8 category keywords are the 8 rows of PS3.16 2026a CID 7150 (Segmentation Property Category) with their exact Code Value / Coding Scheme Designator / Code Meaning; the 21 type keywords are rows of CIDs that CID 7151 (Segmentation Property Type) includes: CID 7166 (Tissue; via CID 7191), CID 7159 (Morphologically Abnormal Structure; via CID 7194), CID 7152–7155 and CID 7160 (via CID 7192), CID 7165 (via CID 7196); both Code Sequences are Type 1 with one Item per PS3.3 2026a Table C.8.20-4; Code Meaning is Type 1 in the Code Sequence Macro (PS3.3 Table 8.8-1), so a bare SCHEME:VALUE is accepted only for a listed code

import Foundation
import DICOMCore

/// Segmented Property Category (CID 7150) and Type (CID 7151) codes for the segments
/// `dicom-ai segment --format dicom-seg` writes.
///
/// An AI class label carries no coded anatomy, so every segment of one object gets the same
/// category and type pair: the defaults below, or the `--segment-category` /
/// `--segment-type` values, which accept a keyword from the tables here or
/// `SCHEME:VALUE[:MEANING]` (the meaning may be omitted only for a listed code).
enum SegmentPropertyCodes {

    /// Default category: (85756007, SCT, "Tissue"), a row of CID 7150
    static let defaultCategory = CodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Tissue")

    /// Default type: (85756007, SCT, "Tissue"), a row of CID 7166, included in CID 7151
    /// through CID 7191
    static let defaultType = CodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Tissue")

    /// `--segment-category` keywords: the 8 rows of CID 7150 (PS3.16 2026a)
    static let categories: [(keyword: String, concept: CodedConcept)] = [
        ("tissue", CodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Tissue")),
        ("anatomical-structure", CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")),
        ("physical-object", CodedConcept(codeValue: "260787004", codingSchemeDesignator: "SCT", codeMeaning: "Physical object")),
        ("abnormal-structure", CodedConcept(codeValue: "49755003", codingSchemeDesignator: "SCT", codeMeaning: "Morphologically Abnormal Structure")),
        ("function", CodedConcept(codeValue: "246464006", codingSchemeDesignator: "SCT", codeMeaning: "Function")),
        ("spatial-concept", CodedConcept(codeValue: "309825002", codingSchemeDesignator: "SCT", codeMeaning: "Spatial and Relational Concept")),
        ("body-substance", CodedConcept(codeValue: "91720002", codingSchemeDesignator: "SCT", codeMeaning: "Body Substance")),
        ("substance", CodedConcept(codeValue: "105590001", codingSchemeDesignator: "SCT", codeMeaning: "Substance")),
    ]

    /// `--segment-type` keywords: a selection of rows from the CIDs that CID 7151 includes
    /// (PS3.16 2026a), named in the file header
    static let types: [(keyword: String, concept: CodedConcept)] = [
        // CID 7166 Common Tissue Segmentation Types (CID 7191 → CID 7151)
        ("tissue", CodedConcept(codeValue: "85756007", codingSchemeDesignator: "SCT", codeMeaning: "Tissue")),
        ("soft-tissue", CodedConcept(codeValue: "87784001", codingSchemeDesignator: "SCT", codeMeaning: "Soft tissue")),
        ("organ", CodedConcept(codeValue: "91772007", codingSchemeDesignator: "SCT", codeMeaning: "Organ")),
        ("bone", CodedConcept(codeValue: "3138006", codingSchemeDesignator: "SCT", codeMeaning: "Bone")),
        ("blood-vessel", CodedConcept(codeValue: "59820001", codingSchemeDesignator: "SCT", codeMeaning: "Blood vessel")),
        ("muscle", CodedConcept(codeValue: "91727004", codingSchemeDesignator: "SCT", codeMeaning: "Muscle")),
        ("fat", CodedConcept(codeValue: "55603005", codingSchemeDesignator: "SCT", codeMeaning: "Fat")),
        // CID 7159 Lesion Segmentation Types (CID 7194 → CID 7151)
        ("lesion", CodedConcept(codeValue: "52988006", codingSchemeDesignator: "SCT", codeMeaning: "Lesion")),
        ("mass", CodedConcept(codeValue: "4147007", codingSchemeDesignator: "SCT", codeMeaning: "Mass")),
        ("nodule", CodedConcept(codeValue: "27925004", codingSchemeDesignator: "SCT", codeMeaning: "Nodule")),
        ("neoplasm", CodedConcept(codeValue: "108369006", codingSchemeDesignator: "SCT", codeMeaning: "Neoplasm")),
        ("cyst", CodedConcept(codeValue: "367643001", codingSchemeDesignator: "SCT", codeMeaning: "Cyst")),
        // CID 7152–7155, 7160 Anatomical Structure Segmentation Types (CID 7192 → CID 7151)
        ("heart", CodedConcept(codeValue: "80891009", codingSchemeDesignator: "SCT", codeMeaning: "Heart")),
        ("brain", CodedConcept(codeValue: "12738006", codingSchemeDesignator: "SCT", codeMeaning: "Brain")),
        ("liver", CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")),
        ("kidney", CodedConcept(codeValue: "64033007", codingSchemeDesignator: "SCT", codeMeaning: "Kidney")),
        ("spleen", CodedConcept(codeValue: "78961009", codingSchemeDesignator: "SCT", codeMeaning: "Spleen")),
        ("pancreas", CodedConcept(codeValue: "15776009", codingSchemeDesignator: "SCT", codeMeaning: "Pancreas")),
        ("lung", CodedConcept(codeValue: "39607008", codingSchemeDesignator: "SCT", codeMeaning: "Lung")),
        ("prostate", CodedConcept(codeValue: "41216001", codingSchemeDesignator: "SCT", codeMeaning: "Prostate")),
        // CID 7165 Abstract Segmentation Types (CID 7196 → CID 7151)
        ("background", CodedConcept(codeValue: "125040", codingSchemeDesignator: "DCM", codeMeaning: "Background")),
    ]

    enum ParseError: Error, CustomStringConvertible {
        case unknown(String, option: String)
        case missingMeaning(String, option: String)

        var description: String {
            switch self {
            case .unknown(let value, let option):
                return "\(option): \"\(value)\" is neither a listed keyword nor SCHEME:VALUE[:MEANING]"
            case .missingMeaning(let value, let option):
                return "\(option): \"\(value)\" is not a listed code, so its Code Meaning is required (SCHEME:VALUE:MEANING)"
            }
        }
    }

    /// Parses an option value: a keyword from `table`, or `SCHEME:VALUE[:MEANING]`. The
    /// meaning is looked up in `table` when omitted, because Code Meaning (0008,0104) is
    /// Type 1 (PS3.3 Table 8.8-1).
    static func parse(_ value: String, from table: [(keyword: String, concept: CodedConcept)], option: String) throws -> CodedConcept {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let match = table.first(where: { $0.keyword == trimmed.lowercased() }) {
            return match.concept
        }
        let parts = trimmed.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ParseError.unknown(value, option: option)
        }
        let scheme = parts[0], code = parts[1]
        if parts.count == 3, !parts[2].isEmpty {
            return CodedConcept(codeValue: code, codingSchemeDesignator: scheme, codeMeaning: parts[2])
        }
        guard let known = table.first(where: { $0.concept.codeValue == code && $0.concept.codingSchemeDesignator == scheme }) else {
            throw ParseError.missingMeaning(value, option: option)
        }
        return known.concept
    }

    /// Help text listing the keywords of a table
    static func keywordList(_ table: [(keyword: String, concept: CodedConcept)]) -> String {
        table.map(\.keyword).joined(separator: ", ")
    }
}
