// ViewerContentKindTests.swift
// DICOMStudioTests
//
// Telling a report from a picture.
//
// The bug this pins: everything that was not a waveform went down the pixel
// path, so a valid SR or encapsulated PDF was reported to the user as an image
// that failed to decode.

import Testing
@testable import DICOMStudio
import DICOMCore
import DICOMKit
import Foundation

@Suite("Viewer Content Kind Tests")
struct ViewerContentKindTests {

    @Test("Structured report SOP classes are reports")
    func testStructuredReports() {
        // Basic Text SR, Enhanced SR, Comprehensive SR, Mammography CAD SR.
        for uid in ["1.2.840.10008.5.1.4.1.1.88.11",
                    "1.2.840.10008.5.1.4.1.1.88.22",
                    "1.2.840.10008.5.1.4.1.1.88.33",
                    "1.2.840.10008.5.1.4.1.1.88.50"] {
            #expect(ViewerContentKind.kind(forSOPClassUID: uid) == .report, "\(uid)")
        }
    }

    @Test("Key Object Selection is called out separately from other reports")
    func testKeyObjectSelection() {
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.88.59")
                == .keyObjectSelection)
    }

    @Test("Encapsulated documents are documents")
    func testEncapsulatedDocuments() {
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.104.1")
                == .document, "PDF")
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.104.2")
                == .document, "CDA")
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.104.3")
                == .document, "STL")
    }

    @Test("Presentation states and waveforms are named rather than drawn as images")
    func testOtherNonImageFamilies() {
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.11.1")
                == .presentationState)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.9.1.1")
                == .waveform)
        // PS3.4 2026a Table B.5-1: the arc runs to Variable Modality LUT Softcopy
        // Presentation State (…11.12) and Body Position Waveform (…9.8.1).
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.11.12")
                == .presentationState)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.9.8.1")
                == .waveform)
    }

    @Test("Families are OID arcs, not string prefixes")
    func testFamiliesAreOIDArcs() {
        // PS3.6 2026a Table A-1: Content Assessment Results Storage (…1.1.90.1) and
        // Microscopy Bulk Simple Annotations Storage (…1.1.91.1) share the characters
        // "…1.1.9" with the waveform arc and are not waveforms.
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.90.1") != .waveform)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.91.1") != .waveform)
        // The retired Standalone Curve (…1.1.9) and Standalone VOI LUT (…1.1.11) are
        // not members of the arcs that start below them.
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.9") != .waveform)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.11") != .presentationState)
    }

    @Test("Waveform presentation states are presentation states (PS3.3 A.92)")
    func testWaveformPresentationStates() {
        // PS3.4 2026a Table B.5-1: …9.100.1 Waveform Presentation State Storage,
        // …9.100.2 Waveform Acquisition Presentation State Storage.
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.9.100.1")
                == .presentationState)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.9.100.2")
                == .presentationState)
    }

    @Test("Raw Data is named as something the viewer cannot show")
    func testRawData() {
        let kind = ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.66")
        #expect(kind == .rawData)
        #expect(!kind.isImage)
        // The viewer says why rather than failing to render an image that was
        // never there.
        #expect(kind.cannotDisplayReason != nil)
        #expect(ViewerContentKind.image.cannotDisplayReason == nil)
        #expect(ViewerContentKind.report.cannotDisplayReason == nil)
    }

    @Test("A raw data object is summarised, with its protocol if it has one")
    func testRawDataSummary() throws {
        let content = try #require(ViewerNonImageContentReader.content(
            of: dataSet([
                (0x0008, 0x0060, "MR", .CS),
                (0x0018, 0x1030, "T1_MPRAGE", .LO)
            ]),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.66"))

        #expect(content.kind == .rawData)
        guard case .summary(_, _, let rows) = content else {
            Issue.record("expected a summary")
            return
        }
        #expect(rows.contains { $0.label == "Protocol" && $0.value == "T1_MPRAGE" })
    }

    @Test("Image storage classes stay images, and an unknown object is treated as one")
    func testImages() {
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.2") == .image,
                "CT")
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.4") == .image,
                "MR")
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.840.10008.5.1.4.1.1.1.1") == .image,
                "Digital X-Ray")
        // Nothing to go on: the pixel path is the one that can still report a
        // real failure, so an unclassifiable object goes there.
        #expect(ViewerContentKind.kind(forSOPClassUID: nil) == .image)
        #expect(ViewerContentKind.kind(forSOPClassUID: "") == .image)
        #expect(ViewerContentKind.kind(forSOPClassUID: "1.2.3.4.5.6") == .image)
    }

    @Test("Only image kinds are rendered as pixels")
    func testIsImage() {
        #expect(ViewerContentKind.image.isImage)
        #expect(!ViewerContentKind.report.isImage)
        #expect(!ViewerContentKind.document.isImage)
        #expect(!ViewerContentKind.presentationState.isImage)
    }

    // MARK: - Reading content from a data set

    private func dataSet(_ values: [(UInt16, UInt16, String, VR)]) -> DataSet {
        DataSet(elements: values.map { group, element, value, vr in
            let padded = value.count % 2 == 0 ? value : value + " "
            let data = Data(padded.utf8)
            return DataElement(
                tag: Tag(group: group, element: element), vr: vr,
                length: UInt32(data.count), valueData: data)
        })
    }

    @Test("An image data set has no non-image content to show")
    func testImageHasNoDocumentContent() {
        let content = ViewerNonImageContentReader.content(
            of: dataSet([(0x0008, 0x0060, "CT", .CS)]),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2")
        #expect(content == nil)
    }

    @Test("A thin SR is still a report, never an image that failed to decode")
    func testThinReportIsStillAReport() throws {
        let content = try #require(ViewerNonImageContentReader.content(
            of: dataSet([
                (0x0008, 0x0060, "SR", .CS),
                (0x0008, 0x103E, "Radiology Report", .LO),
                (0x0020, 0x0011, "99", .IS)
            ]),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.88.11"))

        #expect(content.kind == .report)
    }

    @Test("A document whose bytes cannot be parsed is summarised, not refused")
    func testUnparsableDocumentFallsBackToASummary() throws {
        // An Encapsulated PDF instance missing the MIME type and UIDs the
        // document parser insists on. It is still a document, and the viewer
        // must say so rather than hand it to the pixel path.
        let content = try #require(ViewerNonImageContentReader.content(
            of: dataSet([
                (0x0008, 0x0060, "DOC", .CS),
                (0x0008, 0x103E, "Discharge Summary", .LO),
                (0x0020, 0x0011, "99", .IS)
            ]),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.104.1"))

        #expect(content.kind == .document)
        guard case .summary(_, _, let rows) = content else {
            Issue.record("expected a summary for an unparsable document")
            return
        }
        #expect(rows.contains { $0.label == "Description" && $0.value == "Discharge Summary" })
        #expect(rows.contains { $0.label == "SOP Class" })
    }

    @Test("A presentation state is summarised rather than refused")
    func testPresentationStateSummary() throws {
        let content = try #require(ViewerNonImageContentReader.content(
            of: dataSet([(0x0008, 0x0060, "PR", .CS)]),
            sopClassUID: "1.2.840.10008.5.1.4.1.1.11.1"))

        #expect(content.kind == .presentationState)
        #expect(content.title == ViewerContentKind.presentationState.displayName)
    }
}

#if canImport(SwiftUI)
import DICOMCore

@Suite("Structured Report Narrative Values")
struct StructuredReportNarrativeValueTests {
    @Test("Every PS3.3 Table C.17.3-7 value type reads as something, TABLE included")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testTableValueType() {
        // PS3.3 2026a Table C.17.3-7 lists 16 Value Types; TABLE (CP-2174) had no branch.
        let table = TableContentItem(rows: 2, columns: 3, cells: [])
        #expect(StructuredReportNarrativeView.value(of: AnyContentItem(table)) == "(table, 2 × 3)")
        let text = TextContentItem(conceptName: nil, textValue: "Normal study")
        #expect(StructuredReportNarrativeView.value(of: AnyContentItem(text)) == "Normal study")
    }
}
#endif
