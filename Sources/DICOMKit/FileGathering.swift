// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (directory walk)
import Foundation

/// Shared directory-walk used by every "process a whole directory" tool surface
/// (dicom-anon, dicom-validate, dicom-convert, dicom-pdf, dicom-export bulk).
///
/// Both the CLI executables and the Workshop executors MUST discover files through
/// this gatherer so the two surfaces see the same file set in the same order.
/// The walk is content-agnostic on purpose: these tools try every regular file and
/// let the DICOM reader fail per-file, so their summaries count unreadable files —
/// pre-filtering by extension here would silently change those counts.
public enum FileGatherer {
    /// Regular files under `directory` (hidden files skipped), sorted by path so
    /// processing order — and therefore console output — is deterministic.
    /// `recursive: false` limits the walk to the directory's immediate children.
    /// Returns nil when the directory cannot be enumerated.
    public static func regularFiles(under directory: URL, recursive: Bool = true) -> [URL]? {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else { return nil }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
