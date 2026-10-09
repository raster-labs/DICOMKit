//
// PrintSCPTypes.swift
// DICOMNetwork
//
// Configuration, status codes, events, and delegate contract for the DICOM
// Print SCP (printer emulator). The protocol machine itself lives in
// `PrintSCP.swift`; the values it produces are declared here so that callers
// (Studio, the CLI, the film composer) can depend on them without touching the
// networking internals.
//
// Reference: PS3.4 Annex H — Print Management Service Class.
//

import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-10-01 — the 21 status codes text-diffed against PS3.7 2026a Annex C and PS3.4 2026a Annex H tables (Scripts/diff_network.py): 21 of 21 codes match; `explanation` now reads the verbatim Annex H Further Meaning / Annex C title from DIMSEServiceStatusText (19 of 21; 0000 "Success", C000 has no standard name) — D93; Image Display Format grammar per PS3.3 C.13.3

// MARK: - Print SCP Status Codes

/// Status codes an SCP returns for the N-services of the Print Management
/// Service Class.
///
/// Reference: PS3.4 H.4 (service-specific codes) and PS3.7 Annex C (general
/// N-service codes). Mapped onto ``DIMSEStatus`` for transmission.
public enum PrintSCPStatus: UInt16, Sendable, Hashable, CaseIterable {
    /// Operation completed (0x0000).
    case success = 0x0000

    // Warnings — the operation completed, with a caveat.

    /// Memory allocation not supported; the printer used its own value (0xB600).
    case warningMemoryAllocation = 0xB600
    /// Film Box was created with an image size that did not fit; image demagnified (0xB604).
    case warningImageDemagnified = 0xB604
    /// Requested Min Density / Max Density outside the printer's range (0xB605).
    case warningMinMaxDensityOutOfRange = 0xB605
    /// Film Box was created with an image size that did not fit; image cropped (0xB609).
    case warningImageCropped = 0xB609

    // Failures.

    /// Processing failure (0x0110).
    case processingFailure = 0x0110
    /// No such SOP Instance (0x0112) — unknown film box / image box / job UID.
    case noSuchSOPInstance = 0x0112
    /// Duplicate SOP Instance (0x0111) — e.g. a second Film Session on one association.
    case duplicateSOPInstance = 0x0111
    /// No such attribute (0x0105).
    case noSuchAttribute = 0x0105
    /// Invalid attribute value (0x0106) — e.g. an unsupported Film Size ID.
    case invalidAttributeValue = 0x0106
    /// Invalid object instance (0x0117).
    case invalidObjectInstance = 0x0117
    /// SOP Class / SOP Instance mismatch (0x0119).
    case classInstanceConflict = 0x0119
    /// Missing attribute (0x0120).
    case missingAttribute = 0x0120
    /// Missing attribute value (0x0121).
    case missingAttributeValue = 0x0121
    /// SOP Class not supported (0x0122).
    case sopClassNotSupported = 0x0122
    /// Unable to process (0xC000).
    case unableToProcess = 0xC000
    /// Film Session N-ACTION failure: "Film Session SOP Instance hierarchy
    /// does not contain Film Box SOP Instances" (0xC600, PS3.4 Table H.4-4).
    ///
    /// The case name predates the verified wording and is kept for source
    /// compatibility; the code has never meant "film session is printing".
    case filmSessionPrinting = 0xC600
    /// Film Session N-ACTION failure: "Unable to create Print Job SOP
    /// Instance; print queue is full" (0xC601, PS3.4 Table H.4-4). The Film
    /// Box N-ACTION equivalent is 0xC602 (Table H.4-9), see
    /// ``PrintSCPWireStatus/filmBoxPrintQueueFull``.
    case printQueueFull = 0xC601
    /// Image size is larger than the image box size (0xC603).
    case imageLargerThanImageBox = 0xC603
    /// Insufficient memory in printer to store the image (0xC605).
    case insufficientMemory = 0xC605
    /// Combined print image size is larger than the image box size (0xC613).
    case combinedImageLargerThanImageBox = 0xC613

    /// The wire status value.
    public var dimseStatus: DIMSEStatus { DIMSEStatus.from(rawValue) }

    /// Whether this code lets the operation proceed (success or warning).
    public var isSuccessOrWarning: Bool {
        rawValue == 0x0000 || (0xB000...0xBFFF).contains(rawValue)
    }

    /// The standard name of the code, used for Error Comment (0000,0902) (which
    /// the SCP truncates to the 64 characters of LO).
    ///
    /// Taken verbatim from ``DIMSEServiceStatusText``: the PS3.4 2026a Annex H
    /// "Further Meaning" for the B6xx / C6xx codes (B604 and B60A in the Basic
    /// Film Session N-ACTION wording of Table H.4-4), the PS3.7 2026a Annex C
    /// section title for the general DIMSE-N codes (0105, 0106, 0110, 0111,
    /// 0112, 0117 "Invalid SOP Instance", 0119, 0120, 0121, 0122). 0x0000 is
    /// "Success"; 0xC000 has no Annex H or Annex C name and stays "Unable to
    /// process" (D93, 2026-10-01: six B6xx/C6xx texts were paraphrases).
    public var explanation: String {
        switch self {
        case .success: return "Success"
        case .unableToProcess: return "Unable to process"
        default:
            if let (_, row) = DIMSEServiceStatusText.printRow(for: rawValue) { return row.furtherMeaning }
            if let general = DIMSEServiceStatusText.annexCRow(for: rawValue) { return general.name }
            return "Status 0x" + String(format: "%04X", rawValue)
        }
    }
}

/// An error carrying a Print SCP status code, thrown by the session state
/// machine and turned into a DIMSE failure response by the association handler.
public struct PrintSCPFailure: Error, Sendable, Equatable {
    public let status: PrintSCPStatus
    public let comment: String?

    public init(_ status: PrintSCPStatus, comment: String? = nil) {
        self.status = status
        self.comment = comment
    }

    /// The Error Comment (0000,0902) to return, falling back to the code's own text.
    public var effectiveComment: String { comment ?? status.explanation }
}

/// Print status codes the SCP puts on the wire that have no ``PrintSCPStatus``
/// case.
///
/// ``PrintSCPStatus`` is public API and adding cases would be a breaking
/// change for exhaustive switches, so the codes DICOM 2026a verification
/// added are expressed as raw values and travel through the same
/// `DIMSEStatus.from(_:)` path. References: PS3.4 Table H.4-4 (Film Session
/// N-ACTION), Table H.4-9 (Film Box N-ACTION), Table H.4.2.2.1.2-1 (Film Box
/// N-CREATE); PS3.7 §10.1.4.1.10 and Annex C for the DIMSE-N codes.
enum PrintSCPWireStatus {
    /// Warning: Film Session SOP Instance hierarchy does not contain Image
    /// Box SOP Instances (empty page) — Table H.4-4.
    static let filmSessionEmptyPage: UInt16 = 0xB602
    /// Warning: Film Box SOP Instance hierarchy does not contain Image Box
    /// SOP Instances (empty page) — Table H.4-9.
    static let filmBoxEmptyPage: UInt16 = 0xB603
    /// Warning: image or combined print image decimated to fit — Tables
    /// H.4-4 and H.4-9.
    static let imageDecimated: UInt16 = 0xB60A
    /// Failure: Film Box N-ACTION could not create the Print Job SOP
    /// Instance; print queue is full — Table H.4-9.
    static let filmBoxPrintQueueFull: UInt16 = 0xC602
    /// Failure: an existing Film Box has not been printed and N-ACTION at
    /// the Film Session level is not supported — Table H.4.2.2.1.2-1.
    static let unprintedFilmBoxExists: UInt16 = 0xC616
    /// Failure: "No such Action" — the Action Type ID is not supported
    /// (PS3.7 §10.1.4.1.10).
    static let noSuchAction: UInt16 = 0x0123
    /// Failure: "Unrecognized operation" (PS3.7 Annex C).
    static let unrecognizedOperation: UInt16 = 0x0211
}

/// A failure whose status code is one of ``PrintSCPWireStatus``.
///
/// Reported to ``PrintServerEvent/requestFailed(command:status:detail:)``
/// through `reportedAs`, the nearest public case, with the exact hex code
/// prepended to the detail so nothing is lost.
struct PrintSCPRawFailure: Error {
    let code: UInt16
    let comment: String
    let reportedAs: PrintSCPStatus

    init(_ code: UInt16, comment: String, reportedAs: PrintSCPStatus = .processingFailure) {
        self.code = code
        self.comment = comment
        self.reportedAs = reportedAs
    }
}

// MARK: - Configuration

/// Configuration for the DICOM Print SCP (printer emulator).
///
/// Mirrors ``StorageSCPConfiguration`` for the transport-level settings and adds
/// the printer characteristics an SCU can discover via N-GET on the Printer SOP
/// Instance, plus the limits the session state machine enforces.
public struct PrintSCPConfiguration: Sendable, Hashable {
    /// The local Application Entity title.
    public let aeTitle: AETitle

    /// The port to listen on.
    public let port: UInt16

    /// Maximum PDU size to accept.
    public let maxPDUSize: UInt32

    /// Implementation Class UID advertised in A-ASSOCIATE-AC.
    public let implementationClassUID: String

    /// Implementation Version Name advertised in A-ASSOCIATE-AC.
    public let implementationVersionName: String?

    /// Maximum number of concurrent associations.
    public let maxConcurrentAssociations: Int

    /// Calling AE Title whitelist; `nil` accepts every calling AE.
    public let callingAEWhitelist: Set<String>?

    /// Calling AE Title blacklist; takes precedence over the whitelist.
    public let callingAEBlacklist: Set<String>?

    /// Whether the Basic Color Image Box / Color Print Management Meta SOP
    /// Classes are accepted.
    public let supportsColor: Bool

    /// Film sizes this printer accepts (Film Size ID, 2010,0050).
    public let supportedFilmSizes: Set<FilmSize>

    /// Medium types this printer accepts (Medium Type, 2000,0030).
    public let supportedMediumTypes: Set<MediumType>

    /// Maximum number of image boxes a single film box may declare.
    public let maxImageBoxesPerFilm: Int

    /// Largest image dimension (rows or columns) accepted in an image box.
    public let maxImageBoxPixelDimension: UInt16

    /// Printer Name (2110,0030).
    public let printerName: String

    /// Manufacturer (0008,0070).
    public let manufacturer: String

    /// Manufacturer Model Name (0008,1090).
    public let manufacturerModelName: String

    /// Device Serial Number (0018,1000).
    public let deviceSerialNumber: String

    /// Software Version(s) (0018,1020).
    public let softwareVersion: String

    /// Whether Presentation LUT N-CREATE is accepted.
    public let acceptPresentationLUT: Bool

    /// Whether Basic Annotation Box N-CREATE / N-SET is accepted.
    public let acceptAnnotationBox: Bool

    /// How many Basic Annotation Boxes a film box offers when the SCU supplies
    /// an Annotation Display Format ID.
    ///
    /// A real printer derives this from its configured annotation layout; an
    /// emulator has no such layout, so it advertises a fixed number of positions
    /// and the SCU fills the ones it needs.
    public let annotationBoxesPerFilm: Int

    /// How long an established association may sit idle before the SCP aborts
    /// it, in seconds. `0` disables the timeout.
    ///
    /// A listener facing arbitrary modalities needs this: a peer that opens an
    /// association and then dies (crash, cable pull, NAT drop) otherwise holds
    /// its slot forever, and `maxConcurrentAssociations` dead peers wedge the
    /// printer. The clock is reset by every DIMSE message, so a slow operator
    /// pausing between films does not trip it.
    public let associationIdleTimeout: TimeInterval

    /// Whether to push Print Job N-EVENT-REPORTs (PENDING → PRINTING → DONE)
    /// to the SCU after an N-ACTION. Off by default: many SCUs ignore them and
    /// a few mishandle interleaved requests.
    public let pushPrintJobEvents: Bool

    /// Default Implementation Class UID for the DICOMKit Print SCP.
    public static let defaultImplementationClassUID = DICOMNetworkImplementation.classUID

    /// Default Implementation Version Name for the DICOMKit Print SCP.
    public static let defaultImplementationVersionName = "DICOMKIT_PRTSCP"

    /// The Print Management abstract syntaxes this SCP can accept.
    ///
    /// Both meta SOP Classes plus the individual classes, so an SCU that
    /// negotiates either style works. Verification is included so the same
    /// endpoint also answers C-ECHO.
    public static let grayscaleSOPClasses: Set<String> = [
        basicGrayscalePrintManagementMetaSOPClassUID,
        basicFilmSessionSOPClassUID,
        basicFilmBoxSOPClassUID,
        basicGrayscaleImageBoxSOPClassUID,
        printerSOPClassUID,
        printJobSOPClassUID,
        presentationLUTSOPClassUID,
        basicAnnotationBoxSOPClassUID,
        verificationSOPClassUID
    ]

    /// The additional abstract syntaxes accepted when ``supportsColor`` is set.
    public static let colorSOPClasses: Set<String> = [
        basicColorPrintManagementMetaSOPClassUID,
        basicColorImageBoxSOPClassUID
    ]

    /// Transfer syntaxes accepted for print contexts.
    ///
    /// Explicit **and** Implicit VR LE: real modalities frequently propose
    /// implicit-only, and the SCP reads both (see ``PrintDatasetReader``).
    public static let acceptedTransferSyntaxes: [String] = [
        explicitVRLittleEndianTransferSyntaxUID,
        implicitVRLittleEndianTransferSyntaxUID
    ]

    public init(
        aeTitle: AETitle,
        port: UInt16 = dicomAlternativePort,
        maxPDUSize: UInt32 = defaultMaxPDUSize,
        implementationClassUID: String = defaultImplementationClassUID,
        implementationVersionName: String? = defaultImplementationVersionName,
        maxConcurrentAssociations: Int = 10,
        callingAEWhitelist: Set<String>? = nil,
        callingAEBlacklist: Set<String>? = nil,
        supportsColor: Bool = true,
        supportedFilmSizes: Set<FilmSize> = Set(FilmSize.allCases),
        supportedMediumTypes: Set<MediumType> = Set(MediumType.allCases),
        maxImageBoxesPerFilm: Int = 64,
        maxImageBoxPixelDimension: UInt16 = 10000,
        printerName: String = "DICOMKIT-PRINTER",
        manufacturer: String = "DICOMKit",
        manufacturerModelName: String = "Print Emulator",
        deviceSerialNumber: String = "1",
        softwareVersion: String = "1.0",
        acceptPresentationLUT: Bool = true,
        acceptAnnotationBox: Bool = true,
        annotationBoxesPerFilm: Int = 6,
        associationIdleTimeout: TimeInterval = 300,
        pushPrintJobEvents: Bool = false
    ) {
        self.aeTitle = aeTitle
        self.port = port
        self.maxPDUSize = maxPDUSize
        self.implementationClassUID = implementationClassUID
        self.implementationVersionName = implementationVersionName
        self.maxConcurrentAssociations = max(1, maxConcurrentAssociations)
        self.callingAEWhitelist = callingAEWhitelist
        self.callingAEBlacklist = callingAEBlacklist
        self.supportsColor = supportsColor
        self.supportedFilmSizes = supportedFilmSizes
        self.supportedMediumTypes = supportedMediumTypes
        self.maxImageBoxesPerFilm = max(1, maxImageBoxesPerFilm)
        self.maxImageBoxPixelDimension = maxImageBoxPixelDimension
        self.printerName = printerName
        self.manufacturer = manufacturer
        self.manufacturerModelName = manufacturerModelName
        self.deviceSerialNumber = deviceSerialNumber
        self.softwareVersion = softwareVersion
        self.acceptPresentationLUT = acceptPresentationLUT
        self.acceptAnnotationBox = acceptAnnotationBox
        self.annotationBoxesPerFilm = max(0, annotationBoxesPerFilm)
        self.associationIdleTimeout = max(0, associationIdleTimeout)
        self.pushPrintJobEvents = pushPrintJobEvents
    }

    /// The abstract syntaxes accepted for this configuration.
    public var effectiveSOPClasses: Set<String> {
        supportsColor ? Self.grayscaleSOPClasses.union(Self.colorSOPClasses) : Self.grayscaleSOPClasses
    }

    /// Whether a calling AE title is allowed to associate.
    public func isCallingAEAllowed(_ callingAE: String) -> Bool {
        if let blacklist = callingAEBlacklist, blacklist.contains(callingAE) { return false }
        if let whitelist = callingAEWhitelist { return whitelist.contains(callingAE) }
        return true
    }
}

// MARK: - Received film

/// One image box of a received film, with its decoded pixel payload.
public struct ReceivedImageBox: Sendable, Equatable {
    /// The Image Box SOP Instance UID the SCP allocated.
    public let sopInstanceUID: String

    /// The Image Box SOP Class UID the SCU used (grayscale or color).
    public let sopClassUID: String

    /// Box attributes (position, polarity, requested size, decimate/crop).
    public let content: ImageBoxContent

    /// The image itself; `nil` when the SCU never filled this box.
    public let image: PrintImageData?

    /// Whether this box carried color (Preformatted Color Image Sequence).
    public var isColor: Bool { sopClassUID == basicColorImageBoxSOPClassUID }

    public init(
        sopInstanceUID: String,
        sopClassUID: String,
        content: ImageBoxContent,
        image: PrintImageData?
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.content = content
        self.image = image
    }
}

/// A complete film handed to the delegate when the SCU issues N-ACTION (print).
///
/// This is the SCP's product: everything a composer needs to lay out one sheet,
/// with no networking types attached.
public struct ReceivedFilm: Sendable, Equatable {
    /// The Print Job SOP Instance UID allocated for this film.
    public let printJobUID: String

    /// The film session this film belongs to.
    public let filmSession: FilmSession

    /// The film box attributes.
    public let filmBox: FilmBox

    /// The grid parsed from Image Display Format (2010,0010).
    public let layout: PrintLayout

    /// Image boxes in film order (by Image Box Position), including empty boxes.
    public let imageBoxes: [ReceivedImageBox]

    /// Min Density (2010,0120), when the SCU set it.
    public let minDensity: UInt16?

    /// Max Density (2010,0130), when the SCU set it.
    public let maxDensity: UInt16?

    /// Presentation LUT Shape referenced by the film box, when one was created.
    public let presentationLUTShape: PresentationLUTShape?

    /// Annotation Display Format ID (2010,0030), when the SCU set it.
    public let annotationDisplayFormatID: String?

    /// Annotations received via Basic Annotation Boxes, in position order.
    public let annotations: [PrintAnnotation]

    /// The calling AE title that sent the job.
    public let callingAETitle: String

    /// When the print action was received.
    public let timestamp: Date

    public init(
        printJobUID: String,
        filmSession: FilmSession,
        filmBox: FilmBox,
        layout: PrintLayout,
        imageBoxes: [ReceivedImageBox],
        minDensity: UInt16? = nil,
        maxDensity: UInt16? = nil,
        presentationLUTShape: PresentationLUTShape? = nil,
        annotationDisplayFormatID: String? = nil,
        annotations: [PrintAnnotation] = [],
        callingAETitle: String,
        timestamp: Date = Date()
    ) {
        self.printJobUID = printJobUID
        self.filmSession = filmSession
        self.filmBox = filmBox
        self.layout = layout
        self.imageBoxes = imageBoxes
        self.minDensity = minDensity
        self.maxDensity = maxDensity
        self.presentationLUTShape = presentationLUTShape
        self.annotationDisplayFormatID = annotationDisplayFormatID
        self.annotations = annotations
        self.callingAETitle = callingAETitle
        self.timestamp = timestamp
    }

    /// The image boxes that actually carry pixels.
    public var filledImageBoxes: [ReceivedImageBox] {
        imageBoxes.filter { $0.image != nil }
    }
}

extension ReceivedFilm: CustomStringConvertible {
    public var description: String {
        "ReceivedFilm(job=\(printJobUID), film=\(filmBox.filmSizeID.rawValue), "
            + "layout=\(layout.rows)x\(layout.columns), images=\(filledImageBoxes.count)/\(imageBoxes.count), "
            + "from=\(callingAETitle))"
    }
}

// MARK: - Events

/// Events emitted by the Print SCP for logging and UI.
public enum PrintServerEvent: Sendable {
    /// The listener bound its port.
    case started(port: UInt16)
    /// The listener stopped.
    case stopped
    /// An association was established.
    case associationEstablished(AssociationInfo)
    /// An association was released cleanly.
    case associationReleased(callingAE: String)
    /// An association was rejected.
    case associationRejected(callingAE: String, reason: String)
    /// A film session was created (N-CREATE).
    case filmSessionCreated(uid: String, callingAE: String)
    /// A film box was created (N-CREATE) with its allocated image box UIDs.
    case filmBoxCreated(uid: String, layout: PrintLayout, imageBoxUIDs: [String])
    /// An image box was filled (N-SET).
    case imageBoxReceived(uid: String, position: UInt16, rows: UInt16, columns: UInt16)
    /// An image box carried attributes the standard does not allow, and was
    /// corrected rather than refused.
    ///
    /// The film still prints. This exists so the sender's mistake is visible to
    /// whoever is watching the printer, since a corrected job otherwise looks
    /// exactly like a correct one — see ``PrintPixelDepthConformance``.
    case imageBoxCorrected(uid: String, position: UInt16, detail: String)
    /// A film was printed (N-ACTION) and handed to the delegate.
    case filmPrinted(ReceivedFilm)
    /// An object was deleted (N-DELETE).
    case deleted(uid: String)
    /// A DIMSE request failed with a print status code.
    case requestFailed(command: DIMSECommand, status: PrintSCPStatus, detail: String?)
    /// An association was closed because it sat idle past the configured timeout.
    case associationTimedOut(callingAE: String, afterSeconds: TimeInterval)
    /// A transport or processing error occurred.
    case error(Error)
}

// MARK: - Delegate

/// Handles the films a ``DICOMPrintServer`` receives.
///
/// The protocol machine calls ``didReceiveFilm(_:)`` once per printed film box.
/// Throwing from it makes the SCP answer N-ACTION with a processing failure, so
/// an SCU learns that the film was not produced.
public protocol PrintSCPDelegate: Sendable {
    /// Whether to accept an incoming association.
    func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool

    /// Called for each film printed by N-ACTION.
    func didReceiveFilm(_ film: ReceivedFilm) async throws

    /// The printer status to report via N-GET on the Printer SOP Instance.
    func printerStatus() async -> PrinterStatus

    /// Called when a film could not be processed.
    func didFail(error: Error, forPrintJob printJobUID: String?) async
}

extension PrintSCPDelegate {
    public func shouldAcceptAssociation(from info: AssociationInfo) async -> Bool { true }
    public func printerStatus() async -> PrinterStatus { PrinterStatus(status: "NORMAL") }
    public func didFail(error: Error, forPrintJob printJobUID: String?) async {}
}

/// A delegate that simply collects the films it receives.
///
/// Useful for tests, the CLI's JSON dump mode, and as a base for a sink-backed
/// handler before ``FilmComposer`` exists.
public actor CollectingPrintHandler: PrintSCPDelegate {
    /// Every film received, oldest first.
    public private(set) var films: [ReceivedFilm] = []

    /// The status reported to N-GET.
    public var status: PrinterStatus

    public init(status: PrinterStatus = PrinterStatus(status: "NORMAL")) {
        self.status = status
    }

    public func didReceiveFilm(_ film: ReceivedFilm) async throws {
        films.append(film)
    }

    public func printerStatus() async -> PrinterStatus { status }

    /// Replaces the reported printer status (e.g. to simulate a fault).
    public func setStatus(_ newStatus: PrinterStatus) {
        status = newStatus
    }

    /// Removes all collected films.
    public func reset() { films.removeAll() }
}

// MARK: - Image Display Format

/// A parsed Image Display Format (2010,0010).
///
/// `PrintLayout.layout(fromImageDisplayFormat:)` covers the `STANDARD\r,c` form
/// the SCU emits; an SCP has to cope with everything real modalities send, so
/// this type models the other PS3.3 C.13.3 forms too. The count it reports is
/// what the SCP allocates Image Box SOP Instance UIDs for.
public struct PrintImageDisplayFormat: Sendable, Equatable, Codable {
    /// The layout family.
    public enum Kind: Sendable, Equatable, Codable {
        /// `STANDARD\columns,rows` — a uniform grid.
        case standard(rows: Int, columns: Int)
        /// `ROW\c1,c2,…` — one entry per row, giving that row's image count.
        case row(counts: [Int])
        /// `COL\r1,r2,…` — one entry per column, giving that column's image count.
        case column(counts: [Int])
        /// `SLIDE` — a single 35mm slide image.
        case slide
        /// `SUPERSLIDE` — a single superslide image.
        case superslide
        /// `CUSTOM\i` — a printer-defined layout; the count is not derivable.
        case custom(id: String)
    }

    /// The raw attribute value as received.
    public let raw: String

    /// The interpreted layout.
    public let kind: Kind

    /// Number of image boxes the film box must allocate.
    public let imageBoxCount: Int

    /// The bounding grid, for callers that only understand rows × columns.
    public let layout: PrintLayout

    /// The Image Display Format a uniform grid is written as.
    public init(layout: PrintLayout) {
        self.raw = layout.imageDisplayFormat
        self.kind = .standard(rows: layout.rows, columns: layout.columns)
        self.imageBoxCount = layout.rows * layout.columns
        self.layout = layout
    }

    private init(raw: String, kind: Kind, imageBoxCount: Int, layout: PrintLayout) {
        self.raw = raw
        self.kind = kind
        self.imageBoxCount = imageBoxCount
        self.layout = layout
    }

    /// Parses an Image Display Format value; unrecognized values fall back to 1×1.
    public static func parse(_ raw: String) -> PrintImageDisplayFormat {
        validated(raw) ?? fallback(raw: raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")))
    }

    /// Parses an Image Display Format value, returning `nil` when the text is not
    /// one — the answer a UI or a command line needs, where "it fell back to 1×1"
    /// is indistinguishable from "the user asked for 1×1".
    public static func validated(_ raw: String) -> PrintImageDisplayFormat? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let parts = trimmed.split(separator: "\\", omittingEmptySubsequences: false)
        let head = parts.first.map(String.init)?.uppercased() ?? ""
        let argument = parts.count > 1 ? String(parts[1]) : ""

        func numbers(_ text: String) -> [Int] {
            text.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }.filter { $0 >= 1 }
        }

        switch head {
        case "STANDARD":
            // PS3.3 C.13.3: "STANDARD\C,R" — columns first, then rows.
            let dims = numbers(argument)
            guard dims.count == 2 else { return nil }
            let columns = dims[0], rows = dims[1]
            return PrintImageDisplayFormat(
                raw: trimmed,
                kind: .standard(rows: rows, columns: columns),
                imageBoxCount: rows * columns,
                layout: PrintLayout(rows: rows, columns: columns))

        case "ROW":
            let counts = numbers(argument)
            guard !counts.isEmpty else { return nil }
            return PrintImageDisplayFormat(
                raw: trimmed,
                kind: .row(counts: counts),
                imageBoxCount: counts.reduce(0, +),
                layout: PrintLayout(rows: counts.count, columns: counts.max() ?? 1))

        case "COL":
            let counts = numbers(argument)
            guard !counts.isEmpty else { return nil }
            return PrintImageDisplayFormat(
                raw: trimmed,
                kind: .column(counts: counts),
                imageBoxCount: counts.reduce(0, +),
                layout: PrintLayout(rows: counts.max() ?? 1, columns: counts.count))

        case "SLIDE":
            return PrintImageDisplayFormat(
                raw: trimmed, kind: .slide, imageBoxCount: 1, layout: PrintLayout(rows: 1, columns: 1))

        case "SUPERSLIDE":
            return PrintImageDisplayFormat(
                raw: trimmed, kind: .superslide, imageBoxCount: 1, layout: PrintLayout(rows: 1, columns: 1))

        case "CUSTOM":
            // Printer-defined: the standard gives no way to derive the box count,
            // so allocate a single box rather than guess a grid.
            return PrintImageDisplayFormat(
                raw: trimmed, kind: .custom(id: argument), imageBoxCount: 1,
                layout: PrintLayout(rows: 1, columns: 1))

        default:
            return nil
        }
    }

    private static func fallback(raw: String) -> PrintImageDisplayFormat {
        PrintImageDisplayFormat(
            raw: raw, kind: .standard(rows: 1, columns: 1), imageBoxCount: 1,
            layout: PrintLayout(rows: 1, columns: 1))
    }

    /// Whether every cell on the film is the same size — true only of `STANDARD`.
    ///
    /// The bands of `ROW\` and `COL\` are not a grid: a caller that describes a
    /// film by ``layout`` alone is describing the bounding box, not the film.
    public var isUniformGrid: Bool {
        if case .standard = kind { return true }
        return false
    }

    /// What the format lays out, in words: "2 × 3 grid, 6 images",
    /// "rows of 2, 1, 2 — 5 images".
    public var summary: String {
        func images(_ count: Int) -> String {
            "\(count) image\(count == 1 ? "" : "s")"
        }
        switch kind {
        case .standard(let rows, let columns):
            return "\(rows) × \(columns) grid, \(images(rows * columns))"
        case .row(let counts):
            return "rows of \(counts.map(String.init).joined(separator: ", ")) — \(images(imageBoxCount))"
        case .column(let counts):
            return "columns of \(counts.map(String.init).joined(separator: ", ")) — \(images(imageBoxCount))"
        case .slide:
            return "35 mm slide, 1 image"
        case .superslide:
            return "superslide, 1 image"
        case .custom(let id):
            return "printer-defined layout \(id.isEmpty ? "—" : id), 1 image"
        }
    }
}
