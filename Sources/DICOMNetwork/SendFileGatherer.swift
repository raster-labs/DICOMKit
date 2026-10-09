import Foundation
// NEMA-verified: 2026a, checked 2026-09-28 — the "DICM" prefix at offset 128 compared with PS3.10 2026a §7.1 (128-byte preamble then the 4-byte prefix): match; no other standard data

/// Expands C-STORE path arguments into the concrete list of DICOM files to send.
///
/// This is the SINGLE implementation shared by the `dicom-send` CLI and the CLI
/// Parity reference, so the two can never disagree on *which* files a directory
/// contains — the parity's `--dry-run` "Found N" and the real-send success/fail
/// counts both depend on the two sides enumerating identically.
///
/// Resolution rules (identical to the original `dicom-send` logic):
///   • a path that is a file is taken as-is;
///   • a directory is scanned for DICOM files — its direct children, or the whole
///     tree when `recursive`;
///   • glob patterns (`*` / `?`) in a path are expanded;
///   • a DICOM file is identified by extension (`dcm` / `dicom` / `dic`) or by the
///     "DICM" magic at byte 128.
public enum DICOMSendFileGatherer {

    /// Resolves `paths` into the files `dicom-send` would transmit. `warn`, when
    /// supplied, is called for a path that does not exist (the CLI logs this only
    /// in `--verbose`); the reference passes `nil` so it stays silent.
    public static func gather(paths: [String], recursive: Bool,
                              warn: ((String) -> Void)? = nil) -> [String] {
        var files: [String] = []
        let fileManager = FileManager.default

        for path in paths {
            // Handle glob patterns
            let expandedPaths = expandGlobPattern(path)

            for expandedPath in expandedPaths {
                var isDirectory: ObjCBool = false

                guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
                    warn?("Path not found: \(expandedPath)")
                    continue
                }

                if isDirectory.boolValue {
                    // Directory — direct children, or the whole tree when recursive
                    files.append(contentsOf: scanDirectory(expandedPath, recursive: recursive))
                } else {
                    // Single file
                    files.append(expandedPath)
                }
            }
        }

        return files
    }

    public static func isDICOMFile(_ path: String) -> Bool {
        // Check file extension
        let ext = (path as NSString).pathExtension.lowercased()
        if ["dcm", "dicom", "dic"].contains(ext) {
            return true
        }

        // Check for DICM magic bytes
        guard let fileHandle = FileHandle(forReadingAtPath: path),
              let data = try? fileHandle.read(upToCount: 132) else {
            return false
        }

        // DICOM files have "DICM" at byte 128
        if data.count >= 132 {
            let magic = data[128..<132]
            return magic == Data([0x44, 0x49, 0x43, 0x4D]) // "DICM"
        }

        return false
    }

    private static func expandGlobPattern(_ pattern: String) -> [String] {
        let fileManager = FileManager.default

        // If no wildcards, return as-is
        if !pattern.contains("*") && !pattern.contains("?") {
            return [pattern]
        }

        // Split into directory and pattern
        let url = URL(fileURLWithPath: pattern)
        let directory = url.deletingLastPathComponent().path
        let filePattern = url.lastPathComponent

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return []
        }

        var matches: [String] = []
        for case let item as String in enumerator {
            if matchesPattern(item, pattern: filePattern) {
                matches.append((directory as NSString).appendingPathComponent(item))
            }
        }

        return matches
    }

    private static func matchesPattern(_ string: String, pattern: String) -> Bool {
        // Simple pattern matching (* matches any chars, ? matches single char)
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") else {
            return false
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    /// Scans a directory for DICOM files. Returns `[]` (rather than throwing) if the
    /// directory can't be read, so both the CLI and the reference degrade the same way.
    private static func scanDirectory(_ path: String, recursive: Bool) -> [String] {
        let fileManager = FileManager.default
        var files: [String] = []

        if recursive {
            // Use enumerator for recursive scan
            guard let enumerator = fileManager.enumerator(atPath: path) else {
                return []
            }

            for case let item as String in enumerator {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   !isDirectory.boolValue,
                   isDICOMFile(fullPath) {
                    files.append(fullPath)
                }
            }
        } else {
            // Only direct children
            guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
                return []
            }
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   !isDirectory.boolValue,
                   isDICOMFile(fullPath) {
                    files.append(fullPath)
                }
            }
        }

        return files
    }
}
