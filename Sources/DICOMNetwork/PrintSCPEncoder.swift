//
// PrintSCPEncoder.swift
// DICOMNetwork
//
// Builds the data sets a Print SCP returns: the Referenced Image Box Sequence
// of an N-CREATE Film Box response, and the Printer / Print Job attribute sets
// answered by N-GET. Pure encoding — no networking — so it can be tested by
// feeding the output straight back through `PrintDatasetReader`.
//
// Reference: PS3.3 C.13 (Print Management modules), PS3.4 Annex H.
//

import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — Print Job N-GET attributes text-diffed against PS3.3 2026a Table C.13-8 and Printer attributes against Table C.13-9; Referenced Print Job Sequence per PS3.4 Tables H.4-3/H.4-8

/// A print job the SCP created in response to N-ACTION.
///
/// Named apart from ``PrintJobRecord``, which is the SCU's history entry for a
/// job it *sent*; this one is the SCP's record of a job it was *asked to print*.
public struct PrintSCPJobRecord: Sendable, Equatable {
    /// Print Job SOP Instance UID.
    public let printJobUID: String
    /// The film box this job prints.
    public let filmBoxUID: String
    /// The owning film session.
    public let filmSessionUID: String
    /// Execution Status (2100,0020): PENDING, PRINTING, DONE, or FAILURE.
    public var executionStatus: String
    /// Execution Status Info (2100,0030).
    public var executionStatusInfo: String
    /// Print Priority (2000,0020) inherited from the film session.
    public let printPriority: PrintPriority
    /// Number of copies inherited from the film session. Kept on the record
    /// for the delegate; it is a Film Session attribute (PS3.3 C.13.1) and is
    /// not returned by the Print Job N-GET (Table C.13-8).
    public let numberOfCopies: Int
    /// When the job was created.
    public let creationDate: Date

    public init(
        printJobUID: String,
        filmBoxUID: String,
        filmSessionUID: String,
        executionStatus: String = "PENDING",
        executionStatusInfo: String = "",
        printPriority: PrintPriority = .medium,
        numberOfCopies: Int = 1,
        creationDate: Date = Date()
    ) {
        self.printJobUID = printJobUID
        self.filmBoxUID = filmBoxUID
        self.filmSessionUID = filmSessionUID
        self.executionStatus = executionStatus
        self.executionStatusInfo = executionStatusInfo
        self.printPriority = printPriority
        self.numberOfCopies = numberOfCopies
        self.creationDate = creationDate
    }

    /// The value as returned by the Print Job SOP Class N-GET.
    public var status: PrintJobStatus {
        PrintJobStatus(
            printJobUID: printJobUID,
            executionStatus: executionStatus,
            executionStatusInfo: executionStatusInfo.isEmpty ? nil : executionStatusInfo,
            creationDate: creationDate,
            creationTime: creationDate)
    }
}

extension Tag {
    /// Referenced Print Job Sequence (2100,0500) — PS3.4 Tables H.4-3 / H.4-8.
    static let referencedPrintJobSequence = Tag(group: 0x2100, element: 0x0500)
}

/// Serializes the data sets a Print SCP returns.
public enum PrintSCPEncoder {

    /// Serializes elements in tag order using the negotiated VR.
    public static func serialize(_ elements: [DataElement], explicitVR: Bool) -> Data {
        let writer = DICOMWriter(explicitVR: explicitVR)
        var data = Data()
        for element in elements.sorted(by: { $0.tag < $1.tag }) {
            data.append(writer.serializeElement(element))
        }
        return data
    }

    /// A one-item Referenced SOP Sequence.
    static func referenceSequence(
        tag: Tag,
        sopClassUID: String,
        sopInstanceUIDs: [String]
    ) -> DataElement {
        let items = sopInstanceUIDs.map { uid in
            SequenceItem(elements: [
                DataElement.string(tag: .referencedSOPClassUID, vr: .UI, value: sopClassUID),
                DataElement.string(tag: .referencedSOPInstanceUID, vr: .UI, value: uid)
            ])
        }
        return DataElement(tag: tag, vr: .SQ, length: 0, valueData: Data(), sequenceItems: items)
    }

    /// The data set returned by a successful Basic Film Box N-CREATE.
    ///
    /// Carries the Referenced Film Session Sequence (2010,0500) and — the part
    /// every SCU depends on — the Referenced Image Box Sequence (2010,0510),
    /// with one item per image box the SCP allocated, in film order.
    public static func filmBoxCreateResponse(
        filmSessionUID: String,
        imageBoxSOPClassUID: String,
        imageBoxUIDs: [String],
        annotationBoxUIDs: [String] = [],
        explicitVR: Bool
    ) -> Data {
        var elements: [DataElement] = [
            referenceSequence(
                tag: .referencedFilmSessionSequence,
                sopClassUID: basicFilmSessionSOPClassUID,
                sopInstanceUIDs: [filmSessionUID]),
            referenceSequence(
                tag: .referencedImageBoxSequence,
                sopClassUID: imageBoxSOPClassUID,
                sopInstanceUIDs: imageBoxUIDs)
        ]
        if !annotationBoxUIDs.isEmpty {
            elements.append(referenceSequence(
                tag: .referencedBasicAnnotationBoxSequence,
                sopClassUID: basicAnnotationBoxSOPClassUID,
                sopInstanceUIDs: annotationBoxUIDs))
        }
        return serialize(elements, explicitVR: explicitVR)
    }

    /// The data set returned by a Basic Film Session N-CREATE that also lists
    /// its film boxes (sent on N-GET; N-CREATE itself returns no data set).
    public static func filmSessionAttributes(
        _ session: FilmSession,
        filmBoxUIDs: [String],
        explicitVR: Bool
    ) -> Data {
        var elements: [DataElement] = [
            DataElement.string(tag: .numberOfCopies, vr: .IS, value: String(session.numberOfCopies)),
            DataElement.string(tag: .printPriority, vr: .CS, value: session.printPriority.rawValue),
            DataElement.string(tag: .mediumType, vr: .CS, value: session.mediumType.wireValue),
            DataElement.string(tag: .filmDestination, vr: .CS, value: session.filmDestination.rawValue)
        ]
        if let label = session.filmSessionLabel {
            elements.append(DataElement.string(tag: .filmSessionLabel, vr: .LO, value: label))
        }
        if !filmBoxUIDs.isEmpty {
            elements.append(referenceSequence(
                tag: .referencedFilmBoxSequence,
                sopClassUID: basicFilmBoxSOPClassUID,
                sopInstanceUIDs: filmBoxUIDs))
        }
        return serialize(elements, explicitVR: explicitVR)
    }

    /// The Printer SOP Class attribute set returned by N-GET.
    ///
    /// Reference: PS3.3 C.13.9 (Printer module) plus the SOP Common device
    /// identification attributes SCUs commonly ask for.
    public static func printerAttributes(
        configuration: PrintSCPConfiguration,
        status: PrinterStatus,
        now: Date = Date(),
        explicitVR: Bool
    ) -> Data {
        var elements: [DataElement] = [
            DataElement.string(tag: .printerStatus, vr: .CS, value: status.status),
            DataElement.string(tag: .printerStatusInfo, vr: .CS, value: status.statusInfo ?? "NORMAL"),
            DataElement.string(tag: .printerName, vr: .LO,
                               value: status.printerName ?? configuration.printerName),
            DataElement.string(tag: Tag(group: 0x0008, element: 0x0070), vr: .LO,
                               value: status.manufacturer ?? configuration.manufacturer),
            DataElement.string(tag: Tag(group: 0x0008, element: 0x1090), vr: .LO,
                               value: status.manufacturerModelName ?? configuration.manufacturerModelName),
            DataElement.string(tag: Tag(group: 0x0018, element: 0x1000), vr: .LO,
                               value: configuration.deviceSerialNumber),
            DataElement.string(tag: Tag(group: 0x0018, element: 0x1020), vr: .LO,
                               value: configuration.softwareVersion),
            DataElement.string(tag: Tag(group: 0x0018, element: 0x1200), vr: .DA, value: dicomDate(now)),
            DataElement.string(tag: Tag(group: 0x0018, element: 0x1201), vr: .TM, value: dicomTime(now))
        ]
        // Keep the element list tag-ordered even if a caller adds more later.
        elements.sort { $0.tag < $1.tag }
        return serialize(elements, explicitVR: explicitVR)
    }

    /// The Print Job SOP Class attribute set returned by N-GET.
    ///
    /// Reference: PS3.3 C.13.8, Table C.13-8 (Print Job module): Execution
    /// Status, Execution Status Info, Creation Date, Creation Time, Print
    /// Priority, Printer Name and Originator. Number of Copies (2000,0010)
    /// belongs to the Film Session and is not a Print Job attribute.
    public static func printJobAttributes(
        _ job: PrintSCPJobRecord,
        printerName: String,
        explicitVR: Bool
    ) -> Data {
        printJobAttributes(job, printerName: printerName, originator: nil, explicitVR: explicitVR)
    }

    /// ``printJobAttributes(_:printerName:explicitVR:)`` with Originator
    /// (2100,0070), the AE title that issued the print operation, when the
    /// SCP knows it.
    static func printJobAttributes(
        _ job: PrintSCPJobRecord,
        printerName: String,
        originator: String?,
        explicitVR: Bool
    ) -> Data {
        var elements: [DataElement] = [
            DataElement.string(tag: .printPriority, vr: .CS, value: job.printPriority.rawValue),
            DataElement.string(tag: .executionStatus, vr: .CS, value: job.executionStatus),
            DataElement.string(tag: .executionStatusInfo, vr: .CS,
                               value: job.executionStatusInfo.isEmpty ? "NORMAL" : job.executionStatusInfo),
            DataElement.string(tag: .creationDate, vr: .DA, value: dicomDate(job.creationDate)),
            DataElement.string(tag: .creationTime, vr: .TM, value: dicomTime(job.creationDate)),
            DataElement.string(tag: .printerName, vr: .LO, value: printerName)
        ]
        if let originator, !originator.isEmpty {
            elements.append(DataElement.string(
                tag: .originatingPrintManagement, vr: .AE, value: originator))
        }
        return serialize(elements, explicitVR: explicitVR)
    }

    /// The data set of a successful Film Session / Film Box N-ACTION (Print)
    /// response: Referenced Print Job Sequence (2100,0500) with one item
    /// naming the Print Job SOP Instance the SCP created.
    ///
    /// Reference: PS3.4 Tables H.4-3 and H.4-8 — "-/MC, required if Print
    /// Job SOP is supported".
    static func printJobReference(printJobUID: String, explicitVR: Bool) -> Data {
        serialize([
            referenceSequence(
                tag: .referencedPrintJobSequence,
                sopClassUID: printJobSOPClassUID,
                sopInstanceUIDs: [printJobUID])
        ], explicitVR: explicitVR)
    }

    /// The data set accompanying a Printer SOP Class N-EVENT-REPORT.
    public static func printerEventAttributes(
        statusInfo: String,
        explicitVR: Bool
    ) -> Data {
        serialize([
            DataElement.string(tag: .printerStatusInfo, vr: .CS, value: statusInfo)
        ], explicitVR: explicitVR)
    }

    /// The data set accompanying a Print Job SOP Class N-EVENT-REPORT.
    public static func printJobEventAttributes(
        executionStatusInfo: String,
        filmSessionLabel: String?,
        printerName: String,
        explicitVR: Bool
    ) -> Data {
        var elements: [DataElement] = [
            DataElement.string(tag: .executionStatusInfo, vr: .CS, value: executionStatusInfo),
            DataElement.string(tag: .printerName, vr: .LO, value: printerName)
        ]
        if let label = filmSessionLabel {
            elements.append(DataElement.string(tag: .filmSessionLabel, vr: .LO, value: label))
        }
        return serialize(elements, explicitVR: explicitVR)
    }

    // MARK: - Date / time formatting

    /// Formats a DA value (YYYYMMDD).
    static func dicomDate(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d",
                      components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    /// Formats a TM value (HHMMSS).
    static func dicomTime(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d",
                      components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}
