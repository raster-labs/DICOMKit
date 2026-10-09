// NEMA-verified: 2026a, checked 2026-10-06 — no table of its own since D268: the 7 PS3.6 2026a Table A-1 keywords the catalog tokens do not spell and the composed --transfer-syntax help are DICOMConverter.additionalTableA1Keywords / resolveTargetEncoding / transferSyntaxOptionHelpWithKeywords, which the tool calls; this type only forwards the pre-D268 names for the DICOMStudio copy and the tests
import DICOMCore
import DICOMKit

/// The pre-D268 name of the `--transfer-syntax` keyword table and help. `DICOMConverter` now
/// accepts every PS3.6 2026a Table A-1 keyword of a target UID itself
/// (`additionalTableA1Keywords`) and composes the help (`transferSyntaxOptionHelpWithKeywords`),
/// shared with the DICOMStudio CLI Workshop; this type only forwards.
@available(*, deprecated, message: "use DICOMConverter.additionalTableA1Keywords / resolveTargetEncoding / transferSyntaxOptionHelpWithKeywords (D268)")
enum TransferSyntaxKeywords {

    /// Table A-1 keyword → Transfer Syntax UID, for catalog targets whose keyword is missing.
    static var additional: [String: String] { DICOMConverter.additionalTableA1Keywords }

    /// Resolves a `--transfer-syntax` token (catalog names, UIDs and Table A-1 keywords).
    static func resolve(_ token: String) -> SelectableEncoding? {
        DICOMConverter.resolveTargetEncoding(token)
    }

    /// The stderr note for a keyword whose meaning changed on 2026-10-01, or `nil`.
    static func meaningChangeNote(for token: String) -> String? {
        TransferSyntax.reassignedKeywordNote(for: token)
    }

    /// `--transfer-syntax` help: the catalog names, plus what else is accepted.
    static var optionHelp: String { DICOMConverter.transferSyntaxOptionHelpWithKeywords }
}
