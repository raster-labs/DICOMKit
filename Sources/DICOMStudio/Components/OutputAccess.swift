// OutputAccess.swift
// DICOMStudio
//
// Shared, sandbox/TCC-resilient output writer for CLI Workshop tools.
//
// WHY: tools that write a report/output file used to do `try? data.write(to:
// URL(fileURLWithPath: typedPath))`. On macOS, writing to a typed path under
// ~/Desktop, ~/Documents, etc. is blocked by **TCC (privacy)** — even when the
// App Sandbox is off, and even though POSIX reports the directory writable. The
// old code either silently swallowed the failure (no file, no message) or
// errored, which surfaced to users as an "access issue" when saving a report.
//
// FIX: a single helper that (1) prefers the security-scoped URL the Browse
// picker grants (always writable), (2) else tries the typed path, and (3) on
// failure falls back to ~/Downloads/DICOMStudio/<subfolder>/<filename> (the
// Downloads entitlement is always granted) and returns a user-facing note so the
// redirect is visible, never silent. The headless parity harness is unaffected:
// it writes to a genuinely-writable temp path, so step (2) succeeds and there is
// no redirect.

import Foundation

/// Sandbox/TCC-resilient writer for tool output files. See file header.
public enum OutputAccess {

    /// Writes `data` to the user's chosen output location, resilient to sandbox/TCC denials.
    /// - Parameters:
    ///   - data: the bytes to write.
    ///   - path: the typed/destination path (may be empty if only `scopedURL` is set).
    ///   - scopedURL: the security-scoped URL from the Browse picker, if any (preferred).
    ///   - subfolder: the `~/Downloads/DICOMStudio/<subfolder>/` bucket used only on fallback.
    /// - Returns: the URL actually written, plus a non-nil note when the write was redirected.
    /// - Throws: only if even the Downloads fallback write fails.
    @discardableResult
    public static func write(_ data: Data, toPath path: String, scopedURL: URL?,
                             subfolder: String = "Output") throws -> (url: URL, note: String?) {
        // 1. Security-scoped URL from the picker — preferred (granted writable).
        if let scoped = scopedURL {
            let accessing = scoped.startAccessingSecurityScopedResource()
            defer { if accessing { scoped.stopAccessingSecurityScopedResource() } }
            // The output Browse picker grants a FOLDER (`allowedContentTypes:
            // [.folder]`), so `scoped` is normally the *directory* the user chose —
            // the file must be written INSIDE it, named from the typed path. Writing
            // the bytes straight onto the directory URL is what produced
            // "The file <dir> couldn't be saved in the folder <parent>". When the
            // scope already refers to a regular file we write it directly. Mirrors
            // `readFileData`'s directory-scope handling.
            let destination = destinationWithinScope(scoped, typedPath: path)
            do {
                try writeCreatingParents(data, to: destination)
                return (destination, nil)
            } catch {
                // Scoped write still failed (stale bookmark, read-only volume, …):
                // don't surface a raw error — fall through to the typed path /
                // Downloads bucket so the user still gets their file, with a note.
                return try writeToTypedOrDownloads(data, path: path, subfolder: subfolder,
                                                   reason: error.localizedDescription)
            }
        }

        return try writeToTypedOrDownloads(data, path: path, subfolder: subfolder, reason: nil)
    }

    /// Writes to the typed path, falling back to ~/Downloads/DICOMStudio/<subfolder>/
    /// when that path is empty or not writable (sandbox/TCC). `reason`, when set,
    /// carries the upstream failure (e.g. a denied security scope) so the redirect
    /// note explains why the original destination was bypassed.
    private static func writeToTypedOrDownloads(_ data: Data, path: String, subfolder: String,
                                                reason: String?) throws -> (url: URL, note: String?) {
        guard !path.isEmpty else {
            // No usable destination → fall straight to the Downloads bucket.
            let fallback = fallbackURL(forName: "output.dat", subfolder: subfolder)
            try writeCreatingParents(data, to: fallback)
            return (fallback, redirectNote(from: nil, to: fallback,
                                           reason: reason ?? "no output path was provided"))
        }

        // 2. Try the typed path as-is.
        let target = URL(fileURLWithPath: path)
        do {
            try writeCreatingParents(data, to: target)
            // A non-nil reason means we already bypassed a scoped destination; the
            // typed path worked, so report success without a spurious redirect note.
            return (target, nil)
        } catch {
            // 3. Fall back to ~/Downloads/DICOMStudio/<subfolder>/<filename>.
            let fallback = fallbackURL(forName: target.lastPathComponent, subfolder: subfolder)
            try writeCreatingParents(data, to: fallback)
            return (fallback, redirectNote(from: target, to: fallback,
                                           reason: reason ?? error.localizedDescription))
        }
    }

    /// Resolves the actual file URL to write when the picker granted a security
    /// scope. The output Browse picker uses `allowedContentTypes: [.folder]`, so the
    /// scope is normally the *directory* the user chose; the file is written inside it
    /// using the filename from the typed path. Returns the scope unchanged only when
    /// it already refers to a regular file.
    private static func destinationWithinScope(_ scoped: URL, typedPath: String) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: scoped.path, isDirectory: &isDir)
        let scopedIsDirectory = (exists && isDir.boolValue) || (!exists && scoped.hasDirectoryPath)
        guard scopedIsDirectory else { return scoped }   // scope is the file itself

        let scopedDir = scoped.standardizedFileURL
        let typed = URL(fileURLWithPath: typedPath).standardizedFileURL
        let scopedComponents = scopedDir.pathComponents
        let typedComponents = typed.pathComponents

        // If the typed path lies inside the scoped directory, preserve the relative
        // remainder (browsed …/Out, typed …/Out/sub/file.dcm → write sub/file.dcm
        // within the grant). This is the common case: the typed field holds the
        // chosen folder plus a filename.
        if typedComponents.count > scopedComponents.count,
           Array(typedComponents.prefix(scopedComponents.count)) == scopedComponents {
            return typedComponents.dropFirst(scopedComponents.count)
                .reduce(scoped) { $0.appendingPathComponent($1) }
        }

        // Otherwise honor the grant and write a single file inside it, named from
        // the typed path (or a default when the path is just the directory itself).
        let fileName = typed.lastPathComponent
        if fileName.isEmpty || typed == scopedDir {
            return scoped.appendingPathComponent("output.dat")
        }
        return scoped.appendingPathComponent(fileName)
    }

    /// Convenience for text output (UTF-8).
    @discardableResult
    public static func writeString(_ string: String, toPath path: String, scopedURL: URL?,
                                   subfolder: String = "Output") throws -> (url: URL, note: String?) {
        try write(Data(string.utf8), toPath: path, scopedURL: scopedURL, subfolder: subfolder)
    }

    /// Resolves a writable destination URL up front, for producers that can't route
    /// their write through `write(_:toPath:…)` — e.g. `CGImageDestination` (writes to a
    /// URL) or directory producers (fill a folder with many files). Prefers the picker's
    /// scoped URL; else PROBES the typed path's parent (TCC only fails at write time, so
    /// a create+write+delete probe is the reliable detector); on failure returns a
    /// ~/Downloads/DICOMStudio/<subfolder>/ destination + a note. The headless harness's
    /// temp path passes the probe, so it is never redirected.
    /// - Parameter isDirectory: probe the path itself (true) vs its parent (false).
    public static func resolveWritableURL(forPath path: String, scopedURL: URL?,
                                          subfolder: String = "Output",
                                          isDirectory: Bool = false) -> (url: URL, note: String?) {
        if let scoped = scopedURL {
            // A directory producer fills the granted folder itself. A single-file
            // producer must NOT: the output Browse picker grants a *folder*, so
            // returning the scope verbatim would write the folder path as the file
            // (and silently drop the filename the user typed). Resolve the file
            // within the grant exactly as `write(_:toPath:…)` does.
            return (isDirectory ? scoped : destinationWithinScope(scoped, typedPath: path), nil)
        }
        guard !path.isEmpty else {
            let fb = fallbackURL(forName: "output.dat", subfolder: subfolder)
            return (fb, redirectNote(from: nil, to: fb, reason: "no output path was provided"))
        }
        let target = URL(fileURLWithPath: path)
        let probeDir = isDirectory ? target : target.deletingLastPathComponent()
        if canWrite(into: probeDir) { return (target, nil) }
        let fb = isDirectory
            ? fallbackDir(named: target.lastPathComponent, subfolder: subfolder)
            : fallbackURL(forName: target.lastPathComponent, subfolder: subfolder)
        return (fb, redirectNote(from: target, to: fb, reason: "destination is not writable (sandbox/TCC)"))
    }

    /// True if a probe file can be created+removed in `dir` (creating `dir` if needed).
    private static func canWrite(into dir: URL) -> Bool {
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return false }
        let probe = dir.appendingPathComponent(".dicomstudio-write-probe-\(ProcessInfo.processInfo.processIdentifier)")
        do { try Data().write(to: probe, options: .atomic); try? fm.removeItem(at: probe); return true }
        catch { return false }
    }

    private static func fallbackDir(named name: String, subfolder: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        return downloads.appendingPathComponent("DICOMStudio")
            .appendingPathComponent(subfolder)
            .appendingPathComponent(name.isEmpty ? "output" : name)
    }

    // MARK: - Helpers

    private static func writeCreatingParents(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func fallbackURL(forName name: String, subfolder: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let fileName = name.isEmpty ? "output.dat" : name
        return downloads.appendingPathComponent("DICOMStudio")
            .appendingPathComponent(subfolder)
            .appendingPathComponent(fileName)
    }

    private static func redirectNote(from target: URL?, to fallback: URL, reason: String) -> String {
        var note = "⚠ "
        if let target { note += "Could not write to \(target.path) (\(reason)). " }
        else { note += "\(reason). " }
        note += "Redirected to: \(fallback.path)\n"
        note += "  Tip: use the Browse button next to the output field to grant write access to a custom location."
        return note
    }
}
