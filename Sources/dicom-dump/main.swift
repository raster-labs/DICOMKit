// NEMA-verified: 2026a, checked 2026-10-01 — --tag/--highlight accept (gggg,eeee) or a PS3.6 2026a Table 6-1/7-1 keyword (exact); the --tag header (name, VR) and --annotate keywords/VRs of a CT fixture match PS3.6 Table 6-1/7-1 31/31; layout follows PS3.10 7.1 (128-byte preamble, "DICM", group 0002); --offset annotations come from a whole-file element walk (DICOMKit HexDumper, D144); hex layout options carry no DICOM-standard data
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMDump: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-dump",
        abstract: "Hexadecimal dump with DICOM structure visualization",
        discussion: """
            Displays hexadecimal dump of DICOM files with structure annotations.
            Useful for low-level debugging and format inspection.
            
            Examples:
              dicom-dump file.dcm
              dicom-dump file.dcm --tag 7FE0,0010
              dicom-dump file.dcm --tag PatientName --verbose
              dicom-dump file.dcm --offset 0x1000 --length 256
              dicom-dump file.dcm --no-color > dump.txt
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "Path to DICOM file")
    var filePath: String
    
    @Option(name: .long, help: "Dump specific tag (format: 0010,0010 or PS3.6 keyword, e.g. PatientName)")
    var tag: String?
    
    @Option(name: .long, help: "Start offset in bytes (hex or decimal)")
    var offset: String?
    
    @Option(name: .long, help: "Number of bytes to dump")
    var length: Int?
    
    @Option(name: .long, help: "Bytes per line (default: 16)")
    var bytesPerLine: Int = 16
    
    @Option(name: .long, help: "Highlight specific tag (format: 0010,0010 or PS3.6 keyword)")
    var highlight: String?
    
    @Flag(name: .long, help: "Disable color output")
    var noColor: Bool = false
    
    @Flag(name: .long, help: "Show tag annotations")
    var annotate: Bool = false
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    @Flag(name: .long, help: "Verbose output with VR and length details")
    var verbose: Bool = false
    
    func validate() throws {
        if let length, length < 0 {
            throw ValidationError("--length must be zero or more (got \(length))")
        }
        if bytesPerLine < 1 {
            throw ValidationError("--bytes-per-line must be at least 1 (got \(bytesPerLine))")
        }
    }

    mutating func run() throws {
        let fileURL = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ValidationError("File not found: \(filePath)")
        }
        
        let fileData = try Data(contentsOf: fileURL)
        
        // If specific tag requested, find and dump it
        if let tagString = tag {
            try dumpTag(fileData: fileData, tagString: tagString)
            return
        }
        
        // Parse offset if provided
        let startOffset = try parseOffset()
        guard startOffset >= 0, startOffset <= fileData.count else {
            throw ValidationError("Offset \(startOffset) is out of range (file is \(fileData.count) bytes)")
        }

        // When no explicit --length is given, cap the dump so that dumping a whole
        // (possibly very large) file does not build a huge string and exhaust
        // memory. Pass --length to dump more.
        let defaultDumpCap = 65_536
        let dumpLength = length ?? min(defaultDumpCap, fileData.count - startOffset)

        // Ensure we don't go past end of file
        let endOffset = min(startOffset + dumpLength, fileData.count)
        // Re-base to 0-based indices: a Data slice keeps its parent's indices,
        // which crashes the 0-based dump loop whenever startOffset > 0.
        let dataToShow = Data(fileData[startOffset..<endOffset])
        
        // Create dumper
        let dumper = HexDumper(
            bytesPerLine: bytesPerLine,
            useColor: !noColor,
            annotate: annotate,
            verbose: verbose
        )
        
        // Parse DICOM structure for annotations
        var dicomFile: DICOMFile?
        do {
            dicomFile = try DICOMFile.read(from: fileData, force: force)
        } catch {
            if verbose {
                let warningMessage = "Warning: Could not parse DICOM structure: \(error.localizedDescription)\n"
                if let data = warningMessage.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
                if let data = "Dumping raw bytes without annotations\n\n".data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            }
        }
        
        // Dump the data. The whole file goes to the dumper so annotations and the
        // highlight are found by walking the file from its start (D144).
        var output = dumper.dump(
            fileData: fileData,
            startOffset: startOffset,
            length: dataToShow.count,
            dicomFile: dicomFile,
            highlightTag: try parseHighlightTag()
        )

        if length == nil && endOffset < fileData.count {
            output += "\n… showing first \(endOffset - startOffset) of \(fileData.count) bytes — pass --length to dump more.\n"
        }

        print(output)
    }
    
    private func parseOffset() throws -> Int {
        guard let offsetString = offset else {
            return 0
        }
        
        // Handle hex format (0x prefix)
        if offsetString.lowercased().hasPrefix("0x") {
            let hexString = String(offsetString.dropFirst(2))
            guard let value = Int(hexString, radix: 16) else {
                throw ValidationError("Invalid hex offset: \(offsetString)")
            }
            return value
        }
        
        // Handle decimal
        guard let value = Int(offsetString) else {
            throw ValidationError("Invalid offset: \(offsetString)")
        }
        
        return value
    }
    
    private func parseHighlightTag() throws -> Tag? {
        guard let highlightString = highlight else {
            return nil
        }
        
        return try parseTag(highlightString)
    }
    
    private func parseTag(_ string: String) throws -> Tag {
        try Self.parseTagArgument(string)
    }

    /// Parses `0010,0010`, `(0010,0010)`, `00100010`, or a PS3.6 keyword (exact case).
    static func parseTagArgument(_ string: String) throws -> Tag {
        let cleanString = string.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleanString.count == 8, cleanString.allSatisfy(\.isHexDigit),
           let value = UInt32(cleanString, radix: 16) {
            let group = UInt16((value >> 16) & 0xFFFF)
            let element = UInt16(value & 0xFFFF)
            return Tag(group: group, element: element)
        }
        if let entry = DataElementDictionary.lookup(keyword: string.trimmingCharacters(in: .whitespaces)) {
            return entry.tag
        }

        throw ValidationError("Invalid tag format: \(string). Use format: 0010,0010 or a PS3.6 keyword such as PatientName")
    }

    private func dumpTag(fileData: Data, tagString: String) throws {
        let targetTag = try parseTag(tagString)
        let dicomFile = try DICOMFile.read(from: fileData, force: force)

        // Render via the shared core helper — same output as DICOMStudio, and it
        // uses the parsed element's value bytes (no raw-offset slicing, so it can't
        // crash). Cap the dump to --length (default 65,536) so a huge value (e.g.
        // PixelData) doesn't build an enormous string — matches the whole-file path
        // and keeps the app's SwiftUI console from hanging. Returns nil if absent.
        guard let output = HexDumper.tagDump(
            tag: targetTag,
            in: dicomFile,
            bytesPerLine: bytesPerLine,
            useColor: !noColor,
            verbose: verbose,
            maxBytes: length ?? 65_536
        ) else {
            throw ValidationError("Tag \(formatTag(targetTag)) not found in file")
        }

        print(output, terminator: "")
    }

    private func formatTag(_ tag: Tag) -> String {
        String(format: "(%04X,%04X)", tag.group, tag.element)
    }
}

struct ValidationError: Error, LocalizedError {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var errorDescription: String? {
        message
    }
}

DICOMDump.main()
