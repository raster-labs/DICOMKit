// NEMA-verified: 2026a, checked 2026-10-06 — no rule of its own since D249: the --study-date warning (PS3.4 2026a C.2.2.2.5.1 DA range forms, PS3.5 2026a Table 6.2-1 DA value) is DICOMKit ArchiveMatching.studyDateKeyWarning, which the tool calls; studyDateWarning only forwards for the DICOMStudio copy and the tests
import Foundation
import DICOMKit

/// Warnings for `dicom-archive` query keys the shared ArchiveStore cannot match as DICOM.
///
/// ArchiveStore performs Single Value and Range Matching of Study Date (PS3.4 C.2.2.2.1,
/// C.2.2.2.5.1) and List of UID Matching (C.2.2.2.2). A Study Date that is neither a DA value
/// (YYYYMMDD) nor a DA range is compared as a literal string, so the CLI warns about it
/// (`ArchiveMatching.studyDateKeyWarning`, shared with the DICOMStudio CLI Workshop).
enum ArchiveQueryKeys {

    /// The pre-D249 name of `ArchiveMatching.studyDateKeyWarning(_:)` (same text).
    @available(*, deprecated, renamed: "ArchiveMatching.studyDateKeyWarning(_:option:)")
    static func studyDateWarning(_ value: String?) -> String? {
        ArchiveMatching.studyDateKeyWarning(value)
    }

    static func printWarnings(_ warnings: [String?]) {
        for case let warning? in warnings {
            FileHandle.standardError.write(Data((warning + "\n").utf8))
        }
    }
}
