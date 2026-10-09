//
// PrintPresentationContexts.swift
// DICOMNetwork
//
// Presentation-context negotiation for the Print SCU.
//
// A Print SCU that proposes only the Basic Grayscale/Color Print Management
// **Meta** SOP Class works with most printers and fails outright with the rest:
// plenty of conformance statements list only the individual SOP Classes (Film
// Session, Film Box, Image Box, Printer, Print Job, Presentation LUT,
// Annotation Box). Proposing both, and routing each N-service to a context that
// actually carries its SOP Class, is what "works with any printer" requires.
//
// Reference: PS3.4 H.3.2.2 (Print Management Meta SOP Classes), H.3.3
// (optional SOP Classes), H.4 (Print Management SOP Classes); PS3.8 7.1.1.13
// (presentation context identifiers must be odd).
//

import Foundation
import DICOMCore
// NEMA-verified: 2026a, checked 2026-09-28 — Meta SOP Class membership text-diffed against PS3.4 2026a Tables H.3.2.2.1-1, H.3.2.2.2-1 and H.3.3.2-1; context IDs odd per PS3.8 §9.3.2.2

// MARK: - Proposal

/// Builds the presentation contexts a Print SCU proposes.
public enum PrintPresentationContexts {

    /// Context IDs, fixed so logs and packet captures stay readable.
    /// PS3.8 requires odd identifiers.
    public enum ID {
        /// The Print Management Meta SOP Class (grayscale or color).
        public static let meta: UInt8 = 1
        public static let filmSession: UInt8 = 3
        public static let filmBox: UInt8 = 5
        public static let imageBox: UInt8 = 7
        public static let printer: UInt8 = 9
        public static let printJob: UInt8 = 11
        public static let presentationLUT: UInt8 = 13
        public static let annotationBox: UInt8 = 15
    }

    /// Transfer syntaxes proposed for every print context: Explicit VR LE
    /// preferred, Implicit VR LE accepted as a fallback (printers that speak
    /// implicit-only are common).
    public static let transferSyntaxes = [
        explicitVRLittleEndianTransferSyntaxUID,
        implicitVRLittleEndianTransferSyntaxUID
    ]

    /// The meta SOP Class for a color mode.
    public static func metaSOPClassUID(for colorMode: PrintColorMode) -> String {
        colorMode == .color
            ? basicColorPrintManagementMetaSOPClassUID
            : basicGrayscalePrintManagementMetaSOPClassUID
    }

    /// The Image Box SOP Class for a color mode.
    public static func imageBoxSOPClassUID(for colorMode: PrintColorMode) -> String {
        colorMode == .color ? basicColorImageBoxSOPClassUID : basicGrayscaleImageBoxSOPClassUID
    }

    /// The full context set: the meta SOP Class plus every individual class the
    /// workflow may need.
    ///
    /// A printer that supports only the meta class accepts context 1 and rejects
    /// the rest; one that supports only individual classes does the opposite.
    /// Either way ``PrintContextResolver`` finds a usable route for each
    /// N-service, and only a printer that accepts *nothing* fails the job.
    public static func propose(colorMode: PrintColorMode) throws -> [PresentationContext] {
        let pairs: [(UInt8, String)] = [
            (ID.meta, metaSOPClassUID(for: colorMode)),
            (ID.filmSession, basicFilmSessionSOPClassUID),
            (ID.filmBox, basicFilmBoxSOPClassUID),
            (ID.imageBox, imageBoxSOPClassUID(for: colorMode)),
            (ID.printer, printerSOPClassUID),
            (ID.printJob, printJobSOPClassUID),
            (ID.presentationLUT, presentationLUTSOPClassUID),
            (ID.annotationBox, basicAnnotationBoxSOPClassUID)
        ]
        return try pairs.map { id, abstractSyntax in
            try PresentationContext(
                id: id, abstractSyntax: abstractSyntax, transferSyntaxes: transferSyntaxes)
        }
    }
}

// MARK: - Routing

/// Routes each Print N-service to an accepted presentation context.
///
/// Preference order for a given SOP Class:
/// 1. a context proposed with exactly that abstract syntax, if accepted;
/// 2. the meta-class context, for the four SOP Classes PS3.4 Tables
///    H.3.2.2.1-1 / H.3.2.2.2-1 put in the Print Management Meta SOP Class
///    (Film Session, Film Box, the negotiated Image Box, Printer).
///
/// Print Job, Presentation LUT and Basic Annotation Box are optional classes
/// with contexts of their own (Table H.3.3.2-1); ``supports(_:)`` answers
/// `false` for them unless that context was accepted.
public struct PrintContextResolver: Sendable {

    /// Accepted context ID → abstract syntax.
    private let acceptedByID: [UInt8: String]

    /// Accepted context ID → whether Explicit VR LE was negotiated.
    private let explicitVRByID: [UInt8: Bool]

    /// The meta SOP Class that was proposed (and its context ID, if accepted).
    private let metaSOPClassUID: String
    private let metaContextID: UInt8?

    /// The SOP Classes the negotiated meta class subsumes — exactly four.
    ///
    /// PS3.4 Table H.3.2.2.1-1: Basic Grayscale Print Management Meta = Basic
    /// Film Session, Basic Film Box, Basic Grayscale Image Box, Printer.
    /// Table H.3.2.2.2-1: Basic Color Print Management Meta = Basic Film
    /// Session, Basic Film Box, Basic Color Image Box, Printer. Print Job,
    /// Presentation LUT and Basic Annotation Box are optional SOP Classes that
    /// need a presentation context of their own (Table H.3.3.2-1), so they are
    /// never routed through the meta context.
    private static func metaMembers(for colorMode: PrintColorMode) -> Set<String> {
        [
            basicFilmSessionSOPClassUID,
            basicFilmBoxSOPClassUID,
            PrintPresentationContexts.imageBoxSOPClassUID(for: colorMode),
            printerSOPClassUID
        ]
    }

    /// The members of the meta class that was proposed.
    private let metaMembers: Set<String>

    /// Builds a resolver from what the printer accepted.
    ///
    /// - Throws: `DICOMNetworkError.sopClassNotSupported` when the printer
    ///   accepted no usable context at all.
    public init(
        negotiated: NegotiatedAssociation,
        proposed: [PresentationContext],
        colorMode: PrintColorMode
    ) throws {
        let proposedByID = Dictionary(
            proposed.map { ($0.id, $0.abstractSyntax) }, uniquingKeysWith: { first, _ in first })

        var accepted: [UInt8: String] = [:]
        var explicitVR: [UInt8: Bool] = [:]
        for context in negotiated.acceptedPresentationContexts where context.isAccepted {
            guard let abstractSyntax = proposedByID[context.id] else { continue }
            accepted[context.id] = abstractSyntax
            explicitVR[context.id] = context.transferSyntax != implicitVRLittleEndianTransferSyntaxUID
        }

        let meta = PrintPresentationContexts.metaSOPClassUID(for: colorMode)
        self.acceptedByID = accepted
        self.explicitVRByID = explicitVR
        self.metaSOPClassUID = meta
        self.metaContextID = accepted.first { $0.value == meta }?.key
        self.metaMembers = Self.metaMembers(for: colorMode)

        guard !accepted.isEmpty else {
            throw DICOMNetworkError.sopClassNotSupported(meta)
        }
    }

    /// The context ID to send a request for `sopClassUID` on.
    ///
    /// - Throws: `DICOMNetworkError.sopClassNotSupported` when neither the class
    ///   itself nor a covering meta class was accepted. An optional class
    ///   (Print Job, Presentation LUT, Annotation Box) is only ever carried by
    ///   its own context.
    public func contextID(for sopClassUID: String) throws -> UInt8 {
        if let direct = acceptedByID.first(where: { $0.value == sopClassUID })?.key {
            return direct
        }
        if let metaContextID, metaMembers.contains(sopClassUID) {
            return metaContextID
        }
        throw DICOMNetworkError.sopClassNotSupported(sopClassUID)
    }

    /// Whether Explicit VR LE was negotiated on a context.
    public func usesExplicitVR(_ contextID: UInt8) -> Bool {
        explicitVRByID[contextID] ?? true
    }

    /// Whether any context can carry `sopClassUID`.
    public func supports(_ sopClassUID: String) -> Bool {
        (try? contextID(for: sopClassUID)) != nil
    }

    /// The accepted contexts, for diagnostics: "1=meta, 7=image box".
    public var acceptedSummary: String {
        acceptedByID
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}
