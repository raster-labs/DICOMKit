import Foundation
import Testing
import DICOMCore
import DICOMKit
@testable import DICOMStudio

/// WS-DORM-01/02 qualify the retained component directly. These tests do not
/// claim that the dormant MetadataView is reachable from the production app.
@Suite("Legacy metadata value integrity", .serialized)
@MainActor
struct MetadataValueIntegrityTests {
    private func tree(_ elements: [DataElement]) -> [MetadataTreeNode] {
        var ds = DataSet()
        for element in elements { ds[element.tag] = element }
        return MetadataViewModel().buildTree(from: DICOMFile(fileMetaInformation: DataSet(), dataSet: ds))
    }

    private func element(_ vr: VR, _ bytes: [UInt8], order: ByteOrder = .littleEndian) -> DataElement {
        DataElement(tag: Tag(group: 0x0019, element: 0x1010), vr: vr,
                    length: UInt32(bytes.count), valueData: Data(bytes), byteOrder: order)
    }

    @Test("Numeric VRs retain signedness, precision, byte order and every value",
          arguments: [ByteOrder.littleEndian, .bigEndian])
    func binaryNumbers(order: ByteOrder) throws {
        // Fixed byte vectors and literal expectations, independent of the writer.
        let vectors: [(VR, Int, [UInt8], String)] = [
            (.US, 2, [0x34, 0x12, 0xff, 0xff], "4660\\65535"),
            (.SS, 2, [0x00, 0x80, 0xff, 0x7f], "-32768\\32767"),
            (.UL, 4, [0xff, 0xff, 0xff, 0xff, 0x78, 0x56, 0x34, 0x12], "4294967295\\305419896"),
            (.SL, 4, [0x00, 0x00, 0x00, 0x80, 0xff, 0xff, 0xff, 0x7f], "-2147483648\\2147483647"),
            (.FL, 4, [0x00, 0x00, 0xc0, 0x3f, 0x00, 0x00, 0x00, 0x80], "1.5\\-0.0"),
            (.FD, 8, [0, 0, 0, 0, 0, 0, 0x04, 0xc0, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f], "-2.5\\1.0"),
            (.SV, 8, [0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f], "-9223372036854775808\\9223372036854775807"),
            (.UV, 8, [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 1, 0, 0, 0, 0, 0, 0x20, 0], "18446744073709551615\\9007199254740993"),
            (.AT, 2, [0x10, 0x00, 0x10, 0x00, 0x28, 0x00, 0x10, 0x00], "(0010,0010)\\(0028,0010)")
        ]
        for (vr, wordSize, littleEndian, expected) in vectors {
            let bytes = order == .littleEndian ? littleEndian : stride(from: 0, to: littleEndian.count, by: wordSize)
                .flatMap { Array(littleEndian[$0..<$0 + wordSize].reversed()) }
            let node = try #require(tree([element(vr, bytes, order: order)]).first)
            #expect(node.copyValue == expected, "\(vr) \(order)")
            #expect(node.value == expected.replacingOccurrences(of: "\\", with: " \\ "))
            #expect(!node.value.contains("bytes"))
        }
    }

    @Test("Binary float text round trips finite values and preserves non-finite categories")
    func floatingPrecision() throws {
        let values = [1.2345678901234567, -0.0, Double.infinity, -Double.infinity, Double.nan]
        let bytes = values.flatMap { value in
            (0..<8).map { UInt8(truncatingIfNeeded: value.bitPattern >> ($0 * 8)) }
        }
        let node = try #require(tree([element(.FD, bytes)]).first)
        let copied = node.copyValue.split(separator: "\\").map { Double($0) }
        #expect(copied.count == values.count)
        #expect(copied[0]?.bitPattern == values[0].bitPattern)
        #expect(copied[1]?.bitPattern == values[1].bitPattern)
        #expect(copied[2] == Double.infinity)
        #expect(copied[3] == -Double.infinity)
        #expect(copied[4]?.isNaN == true)
    }

    @Test("Empty numeric values copy empty and malformed widths are never partially decoded")
    func emptyAndMalformedNumbers() throws {
        for (vr, width) in [(VR.US, 2), (.SS, 2), (.UL, 4), (.SL, 4), (.FL, 4), (.FD, 8), (.SV, 8), (.UV, 8), (.AT, 4)] {
            let empty = try #require(tree([element(vr, [])]).first)
            #expect(empty.copyValue.isEmpty)
            #expect(empty.value == "(empty)")
            let malformed = element(vr, Array(repeating: 1, count: width + 1))
            #expect(DICOMValueParser.numericValues(for: malformed) == nil)
            #expect(tree([malformed]).first?.value == "[\(width + 1) bytes]")
        }
    }

    @Test("Decimal copy retains lexical precision and every empty value",
          arguments: ["1.23456789", "1\\\\3", "\\1\\", "+001.2300\\\\-0.0", ""])
    func decimalCopy(raw: String) throws {
        let node = try #require(tree([element(.DS, Array(raw.utf8))]).first)
        #expect(node.copyValue == raw)
        #expect(ClipboardHelper.formatNodeForClipboard(node).contains("\t\(raw)\t"))
        if !raw.isEmpty {
            #expect(node.value.filter { $0 == "\\" }.count == raw.filter { $0 == "\\" }.count)
        }
        if raw == "1.23456789" { #expect(node.value == "1.23457") }
    }

    @Test("Integer presentation does not discard leading, internal or trailing empty components")
    func integerMultiplicity() {
        #expect(DICOMValueParser.formatIntegerString("\\001\\\\3\\") == " \\ 1 \\  \\ 3 \\ ")
        #expect(DICOMValueParser.formatDecimalString("\\1.0\\\\3.0\\") == " \\ 1 \\  \\ 3 \\ ")
    }

    @Test("Text copy preserves meaningful whitespace, newlines, PN syntax and Unicode")
    func originalText() throws {
        for (vr, raw) in [(VR.PN, "  Müller^患者"), (.LT, "  Müller患者\n")] {
            let padded = raw.utf8.count.isMultiple(of: 2) ? raw : raw + " "
            let value = DataElement(tag: Tag(group: 0x0019, element: 0x1010), vr: vr,
                                    length: UInt32(padded.utf8.count),
                                    valueData: Data(padded.utf8), specificCharacterSet: "ISO_IR 192")
            let node = try #require(tree([value]).first)
            #expect(node.copyValue == raw)
            #expect(node.value != node.copyValue)
        }
    }

    @Test("Sequence descendants, filtering and bulk copy retain exact values")
    func nestedCopy() throws {
        var ds = DataSet()
        ds.setSequence([SequenceItem(elements: [element(.DS, Array("1.23456789".utf8))])], for: .referencedStudySequence)
        let nodes = tree(ds.allElements)
        let filtered = MetadataTreeBuilder.filter(nodes: nodes, searchText: "1.23456789")
        let leaf = try #require(filtered.first?.children.first?.children.first)
        #expect(leaf.copyValue == "1.23456789")
        #expect(leaf.value == "1.23457")
        let copied = ClipboardHelper.formatNodesForClipboard(filtered)
        #expect(copied.contains("\t1.23456789\t"))
        #expect(!copied.contains("\t1.23457\t"))
    }

    @Test("Part 10 parsing carries dataset byte order into metadata nodes",
          arguments: [ByteOrder.littleEndian, .bigEndian])
    func parsedFile(order: ByteOrder) throws {
        // A minimal, independently encoded Part 10 metadata fixture; not a full image IOD.
        let syntax = order == .littleEndian ? "1.2.840.10008.1.2.1" : "1.2.840.10008.1.2.2"
        var bytes = Data(repeating: 0, count: 128)
        bytes.append(contentsOf: Array("DICM".utf8))
        let uid = Array((syntax + "\0").utf8)
        bytes.append(contentsOf: [0x02, 0, 0x10, 0, 0x55, 0x49, UInt8(uid.count), 0] + uid)
        bytes.append(contentsOf: order == .littleEndian
                     ? [0x28, 0, 0x10, 0, 0x55, 0x53, 0x02, 0, 0x34, 0x12]
                     : [0, 0x28, 0, 0x10, 0x55, 0x53, 0, 0x02, 0x12, 0x34])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-endian-\(UUID().uuidString).dcm")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = MetadataViewModel()
        model.loadFile(at: url)
        #expect(model.errorMessage == nil)
        let node = try #require(model.nodes.first { $0.group == 0x0028 && $0.element == 0x0010 })
        #expect(node.value == "4660")
        #expect(node.copyValue == "4660")
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("The active Workshop info route retains its shared numeric and raw decimal output")
    func workshopUnchanged() async throws {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString("2.25.6260101", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(4660, for: .rows)
        ds.setString("1.23456789", for: .sliceThickness, vr: .DS)
        let bytes = try DICOMFile.create(dataSet: ds).write()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-workshop-\(UUID().uuidString).dcm")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = CLIWorkshopViewModel(service: CLIWorkshopService())
        model.selectTool(id: "dicom-info")
        model.updateParameterValue(parameterID: "inputPath", value: url.path)
        await model.executeCommand()
        #expect(model.consoleStatus == .success, "\(model.consoleOutput)")
        #expect(model.consoleOutput.contains("VR=US 4660"))
        #expect(model.consoleOutput.contains("VR=DS 1.23456789"))
        #expect(!model.consoleOutput.contains("VR=DS 1.23457\n"))
        #expect(try Data(contentsOf: url) == bytes)
    }
}
