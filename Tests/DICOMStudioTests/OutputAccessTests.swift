// OutputAccessTests.swift
// Verifies the sandbox/TCC-resilient output writer used by every CLI Workshop
// tool: a writable path is used as-is; an UNWRITABLE path falls back to
// ~/Downloads/DICOMStudio/<subfolder> with a user-facing note (never a silent
// failure); a security-scoped URL is preferred. This is the headless proof of
// the access fix — the real TCC denial only happens in the sandboxed app, but
// the fallback logic (which is what makes the fix work) is fully testable here.

import XCTest
@testable import DICOMStudio

final class OutputAccessTests: XCTestCase {

    /// A writable typed path is written as-is, with NO redirect note.
    func testWritableTypedPathIsUsedAsIs() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-\(UUID().uuidString)")
            .appendingPathComponent("out.txt")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let res = try OutputAccess.writeString("hello", toPath: tmp.path, scopedURL: nil, subfolder: "Test")
        XCTAssertNil(res.note, "a writable path must not be redirected")
        XCTAssertEqual(res.url.path, tmp.path)
        XCTAssertEqual(try String(contentsOf: tmp, encoding: .utf8), "hello")
    }

    /// An UNWRITABLE path (cannot create a dir under "/") falls back to
    /// ~/Downloads/DICOMStudio/<subfolder> and returns a non-nil note.
    func testUnwritablePathFallsBackWithNote() throws {
        let unwritable = "/dicomstudio-oa-\(UUID().uuidString)/out.txt"
        let res = try OutputAccess.writeString("payload", toPath: unwritable, scopedURL: nil, subfolder: "FallbackTest")
        XCTAssertNotNil(res.note, "an unwritable path must surface a redirect note")
        XCTAssertTrue(res.url.path.contains("DICOMStudio/FallbackTest"), "expected Downloads fallback, got \(res.url.path)")
        XCTAssertEqual(try String(contentsOf: res.url, encoding: .utf8), "payload")
        try? FileManager.default.removeItem(at: res.url)
    }

    /// resolveWritableURL probes the parent directory and redirects when unwritable.
    func testResolveWritableURLProbeFallsBack() {
        let unwritable = "/dicomstudio-oa-probe-\(UUID().uuidString)/out.dcm"
        let res = OutputAccess.resolveWritableURL(forPath: unwritable, scopedURL: nil, subfolder: "ProbeTest")
        XCTAssertNotNil(res.note)
        XCTAssertTrue(res.url.path.contains("DICOMStudio/ProbeTest"))
    }

    /// resolveWritableURL leaves a writable path untouched (no redirect) — this is
    /// the headless-harness case (temp output dir is genuinely writable).
    func testResolveWritableURLKeepsWritablePath() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-keep-\(UUID().uuidString)")
            .appendingPathComponent("out.dcm")
        let res = OutputAccess.resolveWritableURL(forPath: tmp.path, scopedURL: nil, subfolder: "Test")
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, tmp.path)
    }

    // MARK: - Directory-scope handling (the output Browse picker grants a folder)

    /// Regression: the output Browse picker uses `allowedContentTypes: [.folder]`, so
    /// the scoped URL is the DIRECTORY the user chose, while the typed path adds the
    /// filename. The writer must place the file INSIDE the directory — not write the
    /// bytes onto the directory URL (which failed with
    /// "The file <dir> couldn't be saved in the folder <parent>").
    func testScopedDirectoryWritesFileInsideIt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-scopedir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Typed path = the chosen folder + a filename (exactly the screenshot case).
        let typed = dir.appendingPathComponent("output.dcm")
        let res = try OutputAccess.write(Data("dcm".utf8), toPath: typed.path, scopedURL: dir, subfolder: "Compressed")

        XCTAssertNil(res.note, "writing inside the granted folder must not be redirected")
        XCTAssertEqual(res.url.path, typed.path, "file should land inside the scoped directory")
        XCTAssertEqual(try String(contentsOf: typed, encoding: .utf8), "dcm")
    }

    /// A typed path nested below the scoped directory keeps its relative subpath.
    func testScopedDirectoryPreservesRelativeSubpath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-scopesub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let typed = dir.appendingPathComponent("sub").appendingPathComponent("out.dcm")
        let res = try OutputAccess.write(Data("x".utf8), toPath: typed.path, scopedURL: dir, subfolder: "Compressed")
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, typed.path)
        XCTAssertEqual(try String(contentsOf: typed, encoding: .utf8), "x")
    }

    /// When the user browses a folder but appends no filename (typed path == the
    /// scoped directory), the writer still produces a file inside it (default name)
    /// rather than failing by writing onto the directory.
    func testScopedDirectoryWithNoFilenameUsesDefault() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-scopedef-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let res = try OutputAccess.write(Data("y".utf8), toPath: dir.path, scopedURL: dir, subfolder: "Compressed")
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.deletingLastPathComponent().path, dir.path, "file must be created inside the directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: res.url.path))
    }

    /// When the scope already refers to a regular FILE, the bytes are written to it
    /// directly (the writer must not append a filename to a file path).
    func testScopedFileIsWrittenDirectly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-scopefile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("explicit.dcm")
        let res = try OutputAccess.write(Data("z".utf8), toPath: file.path, scopedURL: file, subfolder: "Compressed")
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, file.path)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "z")
    }

    // MARK: - resolveWritableURL + a scoped DIRECTORY grant (dicom-merge --level file)

    /// Regression (dicom-merge): the output Browse picker grants a FOLDER, so a
    /// single-file producer that returned the scope verbatim wrote the folder path
    /// as the file — dropping the filename the user typed and failing with
    /// "The file \"Test\" couldn't be saved in the folder \"Desktop\"".
    /// `isDirectory: false` must resolve the typed filename inside the grant.
    func testResolveScopedDirectoryAppendsTypedFilenameForFileOutput() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-resolve-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let typed = dir.appendingPathComponent("Test.dcm")
        let res = OutputAccess.resolveWritableURL(forPath: typed.path, scopedURL: dir,
                                                  subfolder: "Merge", isDirectory: false)
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, typed.path, "the typed filename must survive the folder grant")
    }

    /// A DIRECTORY producer (--level series/study) fills the granted folder itself,
    /// so the scope is returned unchanged.
    func testResolveScopedDirectoryUnchangedForDirectoryOutput() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-resolve-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let res = OutputAccess.resolveWritableURL(forPath: dir.path, scopedURL: dir,
                                                  subfolder: "Merge", isDirectory: true)
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, dir.path)
    }

    /// A scope that is already a regular FILE is returned as-is for file output
    /// (no filename is appended onto a file path).
    func testResolveScopedFileUnchangedForFileOutput() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oa-resolve-scopedfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("explicit.dcm")
        try Data().write(to: file)
        let res = OutputAccess.resolveWritableURL(forPath: file.path, scopedURL: file,
                                                  subfolder: "Merge", isDirectory: false)
        XCTAssertNil(res.note)
        XCTAssertEqual(res.url.path, file.path)
    }
}
