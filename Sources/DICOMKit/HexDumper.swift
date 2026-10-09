// NEMA-verified: 2026a, checked 2026-10-01 — the VR lists are the 34 VRs of PS3.5 2026a Table 6.2-1 and the 4-byte-length VRs of Table 7.1-1 (OV, SV, UV added); the walk starts after the Preamble only when "DICM" is at bytes 128-131 (PS3.10 7.1), covers the whole file for --offset (D144); Items and delimiters carry the (FFFE,E000/E00D/E0DD) keywords of PS3.6 Table 6-1 and every Item is descended except encapsulated fragments (PS3.5 7.5, A.4; D145); Private Creator (gggg,0010-00FF) named per PS3.5 7.8.1 (D146)
import Foundation
import DICOMCore
import DICOMDictionary

/// Formats binary data as a hexadecimal dump with optional DICOM annotations.
///
/// Shared by the `dicom-dump` CLI and DICOMStudio's CLI Workshop so both produce
/// the same dump from the same bytes (the app disables color and the parity
/// comparison strips ANSI, so the two match).
public final class HexDumper {
    let bytesPerLine: Int
    let useColor: Bool
    let annotate: Bool
    let verbose: Bool

    public init(bytesPerLine: Int = 16, useColor: Bool = true, annotate: Bool = true, verbose: Bool = false) {
        self.bytesPerLine = bytesPerLine
        self.useColor = useColor
        self.annotate = annotate
        self.verbose = verbose
    }

    /// Renders a single tag's dump (header + a hex dump of its value bytes),
    /// shared by the `dicom-dump` CLI (`--tag`) and DICOMStudio so both produce
    /// identical output. Uses the parsed element's value bytes (no raw-offset
    /// slicing), so it can't crash and the header reflects accurate metadata.
    /// Returns `nil` if the tag isn't present.
    ///
    /// `maxBytes` caps how many value bytes are dumped (nil = no cap). Dumping a
    /// large value (e.g. PixelData, which can be many MB) builds a huge string —
    /// a terminal prints it fine, but DICOMStudio's SwiftUI console hangs in
    /// CoreText glyph layout on the main thread. Both callers pass `--length`
    /// (defaulting to 65,536) so the two stay byte-identical and neither blows up.
    public static func tagDump(
        tag: Tag,
        in file: DICOMFile,
        bytesPerLine: Int = 16,
        useColor: Bool = true,
        verbose: Bool = false,
        maxBytes: Int? = nil
    ) -> String? {
        guard let element = file.dataSet[tag] ?? file.fileMetaInformation[tag] else { return nil }
        let name = AttributeNames.name(for: tag) ?? "Unknown"
        var out = "Tag: \(tag.description)  \(name)  VR=\(element.vr.rawValue)  Length=\(element.length)\n"
        if verbose {
            out += "Value: \(MetadataPresenter.formatElementValue(element))\n"
        }
        out += "\n"

        // Cap the dumped bytes. Re-base to a fresh 0-based Data: a `prefix` slice
        // keeps the parent's indices, which traps the 0-based dump loop.
        let fullData = element.valueData
        let shown = maxBytes.map { max(0, min($0, fullData.count)) } ?? fullData.count
        let dumpData = (shown < fullData.count) ? Data(fullData.prefix(shown)) : fullData

        out += HexDumper(bytesPerLine: bytesPerLine, useColor: useColor, annotate: false, verbose: verbose)
            .dump(data: dumpData, startOffset: 0, dicomFile: nil, highlightTag: nil)
        if shown < fullData.count {
            out += "\n… showing first \(shown) of \(fullData.count) bytes — pass --length to dump more.\n"
        }
        return out
    }

    /// Dumps data as hexadecimal with ASCII representation.
    ///
    /// `data` is the dumped bytes and `startOffset` the file offset of its first byte.
    /// Annotations come from walking `data` itself: from byte 132 when `startOffset` is 0
    /// and "DICM" sits at bytes 128-131 (PS3.10 7.1: 128-byte Preamble + 4-byte Prefix),
    /// else from its first byte — so a slice that does not begin on an element boundary
    /// cannot be annotated correctly. To dump part of a file, pass the whole file to
    /// ``dump(fileData:startOffset:length:dicomFile:highlightTag:)`` instead (D144).
    public func dump(
        data: Data,
        startOffset: Int,
        dicomFile: DICOMFile?,
        highlightTag: Tag?
    ) -> String {
        // Build the tag position map when annotating OR highlighting. The scan is
        // raw (operates on the bytes), so a parsed DICOMFile isn't required.
        var tagPositions: [Int: TagInfo] = [:]
        if annotate || highlightTag != nil {
            tagPositions = buildTagPositionMap(fileData: data, skipPreamble: startOffset == 0)
        }
        return render(data: data, startOffset: startOffset, tagPositions: tagPositions, highlightTag: highlightTag)
    }

    /// Dumps `length` bytes (nil: to the end) of a whole file from `startOffset`.
    ///
    /// The element walk covers the whole file — past the 128-byte Preamble and "DICM"
    /// Prefix only when they are present (PS3.10 2026a 7.1) — so `--annotate` and
    /// `--highlight` stay on the right bytes at any offset, and an element that begins
    /// before the dumped range can still be highlighted (D144).
    public func dump(
        fileData: Data,
        startOffset: Int,
        length: Int?,
        dicomFile: DICOMFile?,
        highlightTag: Tag?
    ) -> String {
        let data = Data(fileData)  // 0-based indices
        let start = max(0, min(startOffset, data.count))
        let end = length.map { min(data.count, start + max(0, $0)) } ?? data.count
        let slice = Data(data[start..<end])
        var tagPositions: [Int: TagInfo] = [:]
        if annotate || highlightTag != nil {
            for (offset, info) in buildTagPositionMap(fileData: data, skipPreamble: true) {
                // Keep elements that start in the dumped range, and any element that
                // overlaps it (for --highlight); re-base to slice indices.
                guard info.range.upperBound > start, info.range.lowerBound < end else { continue }
                tagPositions[offset - start] = TagInfo(
                    tag: info.tag, vr: info.vr, length: info.length, keyword: info.keyword,
                    range: (info.range.lowerBound - start)..<(info.range.upperBound - start))
            }
        }
        return render(data: slice, startOffset: start, tagPositions: tagPositions, highlightTag: highlightTag)
    }

    private func render(data: Data, startOffset: Int, tagPositions: [Int: TagInfo], highlightTag: Tag?) -> String {
        var output = ""
        // The element (in data-index space) to highlight, if requested.
        let highlightInfo: TagInfo? = highlightTag.flatMap { ht in
            tagPositions.values.filter { $0.tag == ht }.min { $0.range.lowerBound < $1.range.lowerBound }
        }
        let highlightRange = highlightInfo?.range

        var currentOffset = startOffset
        var dataIndex = 0

        while dataIndex < data.count {
            let lineEnd = min(dataIndex + bytesPerLine, data.count)
            let lineData = data[dataIndex..<lineEnd]

            // Format offset
            let offsetStr = String(format: "%08X", currentOffset)
            output += useColor ? color(offsetStr, .cyan) : offsetStr
            output += "  "

            // Format hex bytes
            var hexPart = ""
            var asciiPart = ""

            for (idx, byte) in lineData.enumerated() {
                let dataByteIndex = dataIndex + idx

                // Is this byte a tag boundary, or part of the highlighted element?
                let isTagStart = tagPositions[dataByteIndex] != nil
                let isHighlight = highlightRange?.contains(dataByteIndex) ?? false

                let hexByte = String(format: "%02X", byte)

                if useColor {
                    if isHighlight {
                        hexPart += color(hexByte, .yellow)
                    } else if isTagStart {
                        hexPart += color(hexByte, .green)
                    } else {
                        hexPart += hexByte
                    }
                } else {
                    hexPart += hexByte
                }

                hexPart += " "

                // ASCII representation
                if byte >= 32 && byte <= 126 {
                    asciiPart += String(format: "%c", byte)
                } else {
                    asciiPart += "."
                }
            }

            // Pad hex part if line is short
            let paddingNeeded = bytesPerLine - lineData.count
            hexPart += String(repeating: "   ", count: paddingNeeded)

            output += hexPart
            output += " |"
            output += useColor ? color(asciiPart, .white) : asciiPart
            output += "|"

            // Tag-boundary annotation (annotate mode). A tag can begin at any byte
            // within the row — tags rarely start exactly on a bytesPerLine boundary
            // (the first dataset tag sits at offset 132, i.e. 132 % 16 == 4) — so
            // scan the whole row's byte range, not just its first byte, and label
            // every tag that starts on this line. Same "← " glyph in both color
            // modes so colored and plain output match once ANSI is stripped.
            if annotate {
                for byteIndex in dataIndex..<lineEnd {
                    guard let tagInfo = tagPositions[byteIndex] else { continue }
                    output += "  "
                    output += useColor ? color("← ", .blue) : "← "
                    output += formatTagAnnotation(tagInfo)
                }
            }
            // Highlighted-tag marker on its first line — a plain-text label so
            // --highlight is visible even in no-color output (e.g. the in-app
            // console), not just as colored bytes in a terminal.
            // An element that begins before the dumped range is labelled on the first line.
            if let info = highlightInfo,
               max(info.range.lowerBound, 0) >= dataIndex, max(info.range.lowerBound, 0) < lineEnd {
                output += "  "
                output += useColor ? color("◀ HIGHLIGHT ", .yellow) : "◀ HIGHLIGHT "
                output += formatTagAnnotation(info)
            }

            output += "\n"

            currentOffset += lineData.count
            dataIndex = lineEnd
        }

        return output
    }

    /// Walks the DICOM stream element-by-element (deterministic, with per-element
    /// explicit/implicit VR detection) and records each element's offset → TagInfo
    /// with its full byte range. This replaces the old heuristic byte-scan, which
    /// byte-walked and misaligned — missing main-dataset tags (e.g. (0008,0060)),
    /// so --highlight / --annotate only found early group-0002 tags.
    ///
    /// The walk starts after the File Preamble and DICOM Prefix only when "DICM" is at
    /// bytes 128-131 (PS3.10 2026a 7.1) and `skipPreamble` is set (the data begins at file
    /// offset 0); a file without them (`--force`) is walked from byte 0 (D144).
    ///
    /// Items and delimiters (FFFE,E000/E00D/E0DD) are recorded with their PS3.6 Table 6-1
    /// keywords and no VR (PS3.5 2026a 7.5). Sequences and Items are descended whether
    /// their length is defined or undefined, so the elements of every Item are annotated;
    /// the Items of encapsulated Pixel Data (PS3.5 A.4) hold fragments, not elements, and
    /// are stepped over by their length (D145).
    private func buildTagPositionMap(fileData: Data, skipPreamble: Bool) -> [Int: TagInfo] {
        var positions: [Int: TagInfo] = [:]
        let data = fileData
        let base = data.startIndex
        let undefinedLength = 0xFFFF_FFFF

        func byteAt(_ i: Int) -> UInt8 { data[data.index(base, offsetBy: i)] }

        // Skip the 128-byte preamble + "DICM" only when the prefix is really there.
        let hasPrefix = data.count >= 132
            && byteAt(128) == 0x44 && byteAt(129) == 0x49 && byteAt(130) == 0x43 && byteAt(131) == 0x4D
        var offset = (skipPreamble && hasPrefix) ? 132 : 0

        // The 34 VRs of PS3.5 Table 6.2-1, and those with the 4-byte length field (Table 7.1-1)
        let knownVRs: Set<String> = [
            "AE","AS","AT","CS","DA","DS","DT","FL","FD","IS","LO","LT","OB","OD","OF",
            "OL","OV","OW","PN","SH","SL","SQ","SS","ST","SV","TM","UC","UI","UL","UN","UR","US","UT","UV"
        ]
        let extendedVRs: Set<String> = ["OB","OD","OF","OL","OV","OW","SQ","SV","UC","UR","UT","UN","UV"]

        // Inside undefined-length encapsulated Pixel Data the Items are fragments.
        var inEncapsulatedPixelData = false

        while offset + 8 <= data.count {
            let group = readUInt16LE(data, at: offset)
            let element = readUInt16LE(data, at: offset + 2)

            // Item / delimiters (FFFE,xxxx): 4-byte length, no VR (PS3.5 7.5).
            if group == 0xFFFE {
                let tag = Tag(group: group, element: element)
                let rawLength = Int(readUInt32LE(data, at: offset + 4))
                let undefined = rawLength == undefinedLength
                let isFragment = inEncapsulatedPixelData && element == 0xE000
                let span = (isFragment && !undefined) ? 8 + max(0, rawLength) : 8
                positions[offset] = TagInfo(
                    tag: tag,
                    vr: nil,
                    length: UInt32(truncatingIfNeeded: rawLength),
                    keyword: AttributeNames.delimiters[tag]?.keyword,
                    range: offset..<min(offset + span, data.count)
                )
                if element == 0xE0DD { inEncapsulatedPixelData = false }
                // Descend into an Item of a Sequence; step over a fragment.
                offset += span
                continue
            }

            // Detect explicit vs implicit VR from the two bytes after the tag.
            let vrCandidate = String(bytes: [byteAt(offset + 4), byteAt(offset + 5)], encoding: .ascii) ?? ""
            let vr: VR
            let headerLength: Int
            let valueLength: Int

            if knownVRs.contains(vrCandidate) {
                vr = VR(rawValue: vrCandidate) ?? .UN
                if extendedVRs.contains(vrCandidate) {
                    guard offset + 12 <= data.count else { break }
                    valueLength = Int(readUInt32LE(data, at: offset + 8))
                    headerLength = 12
                } else {
                    valueLength = Int(readUInt16LE(data, at: offset + 6))
                    headerLength = 8
                }
            } else {
                // Implicit VR: 4-byte length; VR taken from the dictionary.
                vr = DataElementDictionary.lookup(tag: Tag(group: group, element: element))?.vr.first ?? .UN
                valueLength = Int(readUInt32LE(data, at: offset + 4))
                headerLength = 8
            }

            let tag = Tag(group: group, element: element)
            let entry = DataElementDictionary.lookup(tag: tag)
            let undefined = (valueLength == undefinedLength)
            let span = undefined ? headerLength : headerLength + max(0, valueLength)
            let elementEnd = min(offset + span, data.count)
            positions[offset] = TagInfo(
                tag: tag,
                vr: vr,
                length: UInt32(truncatingIfNeeded: valueLength),
                keyword: entry?.keyword ?? (AttributeNames.isPrivateCreator(tag) ? AttributeNames.privateCreatorName : nil),
                range: offset..<max(offset + 1, elementEnd)
            )

            // Advance. A Sequence (SQ, defined or undefined length) is descended by its
            // header so its Items and their elements are walked; an undefined-length
            // non-SQ element is encapsulated Pixel Data (or UN holding a sequence) and
            // is descended too; any other value is stepped over.
            if undefined && vr != .SQ && vr != .UN {
                inEncapsulatedPixelData = true
            }
            offset += (vr == .SQ || undefined) ? headerLength : headerLength + max(0, valueLength)
        }

        return positions
    }

    /// Reads a little-endian UInt16 at a byte offset without alignment assumptions.
    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex
        let b0 = UInt16(data[data.index(base, offsetBy: offset)])
        let b1 = UInt16(data[data.index(base, offsetBy: offset + 1)])
        return b0 | (b1 << 8)
    }

    /// Reads a little-endian UInt32 at a byte offset without alignment assumptions.
    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex
        let b0 = UInt32(data[data.index(base, offsetBy: offset)])
        let b1 = UInt32(data[data.index(base, offsetBy: offset + 1)])
        let b2 = UInt32(data[data.index(base, offsetBy: offset + 2)])
        let b3 = UInt32(data[data.index(base, offsetBy: offset + 3)])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    /// Formats tag annotation for display
    private func formatTagAnnotation(_ tagInfo: TagInfo) -> String {
        let tagStr = String(format: "(%04X,%04X)", tagInfo.tag.group, tagInfo.tag.element)

        var annotation = tagStr

        if verbose {
            if let vr = tagInfo.vr { annotation += " VR=\(vr.rawValue)" }

            if tagInfo.length == 0xFFFFFFFF {
                annotation += " Len=undefined"
            } else {
                annotation += " Len=\(tagInfo.length)"
            }
        }

        if let keyword = tagInfo.keyword {
            annotation += " \(keyword)"
        }

        return annotation
    }

    /// ANSI color codes
    enum Color: String {
        case black = "30"
        case red = "31"
        case green = "32"
        case yellow = "33"
        case blue = "34"
        case magenta = "35"
        case cyan = "36"
        case white = "37"
        case reset = "0"
    }

    /// Applies ANSI color to string
    private func color(_ string: String, _ color: Color) -> String {
        "\u{001B}[\(color.rawValue)m\(string)\u{001B}[0m"
    }
}

/// Information about a DICOM tag found in raw data
struct TagInfo {
    let tag: Tag
    /// nil for Items and delimiters, which have no VR (PS3.5 7.5).
    let vr: VR?
    let length: UInt32
    let keyword: String?
    /// Byte range of the whole element (header + value) in the dumped data's index space.
    let range: Range<Int>
}
