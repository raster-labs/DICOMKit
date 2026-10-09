// NEMA-verified: 2026a, checked 2026-10-06 — no rule of its own since D272: Encapsulated Document Length (0042,0015) and its padding cut (PS3.3 2026a Table C.24-2), Specific Character Set ISO_IR 192 (Table C.12-1, C.12-5), the Conversion Type terms (Table C.8-24), Burned In Annotation YES / NO and the HL7 Instance Identifier root^extension (Table C.24-2) are DICOMKit EncapsulatedDocumentBuilder.OptionRules, which the tool calls; the typealias below only forwards for the tests and DICOMStudio's copy

import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore

/// The pre-D272 name of ``EncapsulatedDocumentBuilder/OptionRules`` (the attributes
/// `dicom-pdf` added around the shared builder / parser, and its option vocabularies),
/// now shared with the DICOMStudio CLI Workshop.
@available(*, deprecated, renamed: "EncapsulatedDocumentBuilder.OptionRules", message: "lifted into DICOMKit (D272)")
typealias PDFEncapsulation = EncapsulatedDocumentBuilder.OptionRules

/// The option checks as the tool reports them: an engine refusal becomes an
/// ArgumentParser `ValidationError` with the same text, as before D272.
enum PDFOptionValues {
    static func conversionType(_ raw: String) throws -> String {
        try validated { try EncapsulatedDocumentBuilder.OptionRules.conversionType(raw) }
    }

    static func burnedInAnnotation(_ raw: String) throws -> Bool {
        try validated { try EncapsulatedDocumentBuilder.OptionRules.burnedInAnnotation(raw) }
    }

    private static func validated<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as EncapsulatedDocumentBuilder.OptionRules.ValidationError {
            throw ArgumentParser.ValidationError(error.message)
        }
    }
}
