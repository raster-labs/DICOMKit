// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (output path composition)
import Foundation

/// Resolves a user-supplied `--output` into a concrete destination FILE path for
/// tools that write a single file.
///
/// Shared by the `dicom-*` CLIs and DICOMStudio's CLI Workshop so a directory
/// such as `~/Desktop/DICOM_Output/` resolves to the SAME file path on both
/// sides — instead of failing with *"<dir> couldn't be saved in the folder …"*
/// when a directory is passed where a single output file is expected. Because
/// the logic is deterministic and shared, the app and the CLI stay in parity
/// without the app having to rewrite the command it shows the user.
public enum OutputPathResolver {
    /// - Parameters:
    ///   - output: the raw `--output` value (may be empty, a file, or a directory).
    ///   - input: the input file path — its name is reused when `output` is a directory.
    ///   - fileExtension: when `output` is a directory, the extension to give the
    ///     produced file (e.g. `"json"` for converters). `nil` keeps the input's
    ///     own extension (the right choice for DICOM-in/DICOM-out tools).
    /// - Returns: the destination file path. If `output` is empty, returns `input`
    ///   (overwrite in place). If `output` names a directory (it exists as one, or
    ///   ends with a path separator), the input's filename is placed inside it.
    ///   Otherwise `output` is returned verbatim (the user named a file).
    public static func resolveFileOutput(
        output: String?,
        input: String,
        fileExtension: String? = nil
    ) -> String {
        let trimmed = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir)
        let isDirectory = trimmed.hasSuffix("/") || (exists && isDir.boolValue)
        guard isDirectory else { return trimmed }

        var name = (input as NSString).lastPathComponent
        if let ext = fileExtension, !ext.isEmpty {
            let stem = (name as NSString).deletingPathExtension
            name = stem.isEmpty ? name : "\(stem).\(ext)"
        }
        return (trimmed as NSString).appendingPathComponent(name)
    }
}
