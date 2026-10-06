// NEMA-verified: 2026a, checked 2026-10-06 — (0002,0017) Sending Application Entity Title / (0002,0018) Receiving Application Entity Title named per PS3.6 2026a Table 7-1 (A3); Maximum Length rules from PS3.8 2026a D.1 (outgoing P-DATA bounded by the peer's value, 0 = no maximum; own value sent in the A-ASSOCIATE-AC); SCP/SCU Role Selection reply per PS3.7 D.3.3.4; AE Title rules of PS3.5 Table 6.2-1 (≤16 chars, no backslash / control characters) via DICOMNetwork.AETitle; Query/Retrieve Level values of PS3.4 Tables C.6.1-1 (4) / C.6.2-1 (3) and the A900 failure of Table C.4-1..C.4-3 when the level is missing; final C-MOVE / C-GET status per C.4.2.3.1 / C.4.3.3.1 and Tables C.4-2 / C.4-3 (0000, B000, A702, FE00); the 3 accepted transfer syntaxes are PS3.6 2026a Table A-1 names
import Foundation
import DICOMCore
import DICOMKit
import DICOMNetwork
import DICOMDictionary

/// Protocol rules of dicom-server that need no socket, kept apart from `ServerSession`
/// so they can be unit-tested.
enum ServerProtocol {

    // MARK: - Implementation identity (PS3.7 D.3.3.2, PS3.10 Table 7.1-1)

    /// Implementation Class UID sent in the A-ASSOCIATE-AC and written to stored files:
    /// DICOMKit's own (root 1.2.826.0.1.3680043.10.511, see `DICOMFile.implementationClassUID`).
    static var implementationClassUID: String { DICOMFile.implementationClassUID }

    /// Implementation Version Name paired with `implementationClassUID`.
    static var implementationVersionName: String { DICOMFile.implementationVersionName }

    // MARK: - SOP Classes and Transfer Syntaxes

    static let verificationSOPClassUID = "1.2.840.10008.1.1" // Verification SOP Class

    /// Explicit VR Little Endian, Implicit VR Little Endian: Default Transfer Syntax for DICOM,
    /// Explicit VR Big Endian (Retired) — in the server's order of preference.
    static let acceptedTransferSyntaxes: [String] = [
        "1.2.840.10008.1.2.1", // Explicit VR Little Endian
        "1.2.840.10008.1.2",   // Implicit VR Little Endian: Default Transfer Syntax for DICOM
        "1.2.840.10008.1.2.2", // Explicit VR Big Endian (Retired)
    ]

    /// Query/Retrieve operation of a Q/R SOP Class
    enum QROperation: Sendable { case find, move, get }

    /// Query/Retrieve Information Model of a Q/R SOP Class
    enum QRModel: Sendable { case patientRoot, studyRoot }

    /// The six Query/Retrieve SOP Classes the server provides (PS3.4 C.6.1 / C.6.2).
    static let queryRetrieveSOPClasses: [String: (model: QRModel, operation: QROperation)] = [
        "1.2.840.10008.5.1.4.1.2.1.1": (.patientRoot, .find), // Patient Root Query/Retrieve Information Model - FIND
        "1.2.840.10008.5.1.4.1.2.1.2": (.patientRoot, .move), // Patient Root Query/Retrieve Information Model - MOVE
        "1.2.840.10008.5.1.4.1.2.1.3": (.patientRoot, .get),  // Patient Root Query/Retrieve Information Model - GET
        "1.2.840.10008.5.1.4.1.2.2.1": (.studyRoot, .find),   // Study Root Query/Retrieve Information Model - FIND
        "1.2.840.10008.5.1.4.1.2.2.2": (.studyRoot, .move),   // Study Root Query/Retrieve Information Model - MOVE
        "1.2.840.10008.5.1.4.1.2.2.3": (.studyRoot, .get),    // Study Root Query/Retrieve Information Model - GET
    ]

    /// Whether a UID is a Storage SOP Class of PS3.4 Table B.5-1 (DICOMDictionary registry).
    static func isStorageSOPClass(_ uid: String) -> Bool {
        StorageSOPClass.allUIDSet.contains(uid)
    }

    /// Abstract syntaxes accepted in association negotiation.
    static func isSupportedAbstractSyntax(_ uid: String) -> Bool {
        uid == verificationSOPClassUID || queryRetrieveSOPClasses[uid] != nil || isStorageSOPClass(uid)
    }

    // MARK: - AE Titles (PS3.5 Table 6.2-1 VR AE, PS3.8 9.3.2)

    /// Validates an AE title given on the command line or in the configuration file.
    ///
    /// - Returns: the title without its non-significant leading/trailing spaces
    /// - Throws: `ServerError.invalidConfiguration` naming the option
    static func validatedAETitle(_ value: String, option: String) throws -> String {
        do {
            return try AETitle(value).value
        } catch {
            throw ServerError.invalidConfiguration(
                "\(option) '\(value)' is not a valid AE title (PS3.5 Table 6.2-1 VR AE: 1-16 characters, "
                + "no backslash or control characters)")
        }
    }

    // MARK: - Maximum Length (PS3.8 D.1)

    /// Size to fragment outgoing P-DATA-TF PDUs to: the peer's Maximum Length Received.
    ///
    /// PS3.8 D.1: the acceptor "shall ensure in its fragmentation of the DICOM Messages that the
    /// list of PDVs included in each P-DATA request does not exceed this maximum length"; a value
    /// of 0 means no maximum is specified, and the server then uses its own value.
    static func outgoingMaxPDUSize(peer: UInt32, local: UInt32) -> UInt32 {
        if peer != 0 { return peer }
        return local != 0 ? local : defaultMaxPDUSize
    }

    /// Whether an incoming PDU exceeds the Maximum Length the server announced in its
    /// A-ASSOCIATE-AC. PS3.8 D.1 limits the P-DATA-TF PDUs only; 0 = no limit.
    static func exceedsLocalMaximum(pduType: UInt8, length: UInt32, localMax: UInt32) -> Bool {
        pduType == PDUType.dataTransfer.rawValue && localMax != 0 && length > localMax
    }

    // MARK: - Association negotiation

    /// Accepted presentation context
    struct AcceptedContext: Sendable, Equatable {
        let abstractSyntax: String
        let transferSyntax: String
        /// The requestor was granted the SCP role (PS3.7 D.3.3.4), so the server may send
        /// C-STORE requests on this context (C-GET sub-operations).
        let requestorIsSCP: Bool
    }

    /// Result of negotiating an A-ASSOCIATE-RQ
    struct Negotiation: Sendable {
        let results: [AcceptedPresentationContext]
        let accepted: [UInt8: AcceptedContext]
        let roleSelections: [SCPSCURoleSelection]
    }

    /// Negotiates presentation contexts and SCP/SCU roles.
    ///
    /// Results 0 / 3 / 4 per PS3.8 Table 9-18. Role selection (PS3.7 D.3.3.4): for a proposed
    /// Storage SOP Class the server accepts the SCP role the requestor proposes (it needs it to
    /// receive C-GET sub-operations) and keeps the requestor's SCU proposal; without a
    /// role-selection item the default roles apply (requestor SCU only).
    static func negotiate(
        presentationContexts: [PresentationContext],
        roleSelections proposedRoles: [SCPSCURoleSelection]
    ) -> Negotiation {
        var results: [AcceptedPresentationContext] = []
        var accepted: [UInt8: AcceptedContext] = [:]
        var replies: [SCPSCURoleSelection] = []

        var grantedSCP: Set<String> = []
        for role in proposedRoles where isStorageSOPClass(role.sopClassUID) {
            if !replies.contains(where: { $0.sopClassUID == role.sopClassUID }) {
                replies.append(SCPSCURoleSelection(
                    sopClassUID: role.sopClassUID, scuRole: role.scuRole, scpRole: role.scpRole))
                if role.scpRole { grantedSCP.insert(role.sopClassUID) }
            }
        }

        for pc in presentationContexts {
            guard isSupportedAbstractSyntax(pc.abstractSyntax) else {
                results.append(AcceptedPresentationContext(id: pc.id, result: .abstractSyntaxNotSupported))
                continue
            }
            guard let ts = acceptedTransferSyntaxes.first(where: { pc.transferSyntaxes.contains($0) }) else {
                results.append(AcceptedPresentationContext(id: pc.id, result: .transferSyntaxesNotSupported))
                continue
            }
            results.append(AcceptedPresentationContext(id: pc.id, result: .acceptance, transferSyntax: ts))
            accepted[pc.id] = AcceptedContext(
                abstractSyntax: pc.abstractSyntax,
                transferSyntax: ts,
                requestorIsSCP: grantedSCP.contains(pc.abstractSyntax))
        }

        // Only answer role selections for SOP Classes that were also proposed as contexts.
        let proposedSyntaxes = Set(presentationContexts.map(\.abstractSyntax))
        replies = replies.filter { proposedSyntaxes.contains($0.sopClassUID) }
        return Negotiation(results: results, accepted: accepted, roleSelections: replies)
    }

    // MARK: - Data set encoding (PS3.5 Section 10, PS3.10 7.1)

    /// Decodes a data set received in a P-DATA message in the negotiated transfer syntax.
    ///
    /// DICOMKit's public parser reads Part 10 streams; the bytes are therefore prefixed with a
    /// preamble, "DICM" and a File Meta Information group whose Transfer Syntax UID is the
    /// negotiated one, so the parser applies that syntax's VR and byte-order rules.
    static func decodeDataSet(_ data: Data, transferSyntaxUID: String) throws -> DataSet {
        var file = partTenHeader(fileMeta: transferSyntaxOnlyMeta(transferSyntaxUID))
        file.append(data)
        return try DICOMFile.read(from: file).dataSet
    }

    /// Encodes a data set in the given (uncompressed) transfer syntax.
    static func encodeDataSet(_ dataSet: DataSet, transferSyntaxUID: String) -> Data {
        let ts = TransferSyntax.from(uid: transferSyntaxUID)
        let writer = DICOMWriter(byteOrder: ts?.byteOrder ?? .littleEndian,
                                 explicitVR: ts?.isExplicitVR ?? true)
        return dataSet.write(using: writer)
    }

    /// File Meta Information of PS3.10 Table 7.1-1 for a received instance, built with
    /// `DICOMFile.create`: (0002,0001), (0002,0002), (0002,0003), (0002,0010), (0002,0012),
    /// (0002,0013), plus the Type 3 Source (0002,0016), Sending (0002,0017) and Receiving
    /// (0002,0018) Application Entity Titles. (0002,0000) is computed by `DICOMFile.write()`.
    static func fileMetaInformation(
        sopClassUID: String,
        sopInstanceUID: String,
        transferSyntaxUID: String,
        serverAETitle: String,
        callingAETitle: String?
    ) -> DataSet {
        var meta = DICOMFile.create(
            dataSet: DataSet(),
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            transferSyntaxUID: transferSyntaxUID
        ).fileMetaInformation
        meta.setString(serverAETitle, for: .sourceApplicationEntityTitle, vr: .AE)
        if let calling = callingAETitle, !calling.isEmpty {
            meta.setString(calling, for: Tag(group: 0x0002, element: 0x0017), vr: .AE) // Sending Application Entity Title
        }
        meta.setString(serverAETitle, for: Tag(group: 0x0002, element: 0x0018), vr: .AE) // Receiving Application Entity Title
        meta.remove(tag: .fileMetaInformationGroupLength) // recomputed by DICOMFile.write()
        return meta
    }

    /// Preamble, "DICM" prefix and the File Meta Information group (PS3.10 7.1), written by
    /// `DICOMFile.write()`; the data set bytes follow unchanged.
    static func partTenHeader(fileMeta: DataSet) -> Data {
        (try? DICOMFile(fileMetaInformation: fileMeta, dataSet: DataSet()).write()) ?? Data()
    }

    /// A stored instance ready to be sent in a C-STORE sub-operation
    struct StoredDataSet: Sendable {
        let sopClassUID: String
        let sopInstanceUID: String
        let transferSyntaxUID: String
        /// The data set bytes in `transferSyntaxUID`, as stored
        let dataSetData: Data
    }

    /// Reads a stored Part 10 file: its File Meta Information and the data set bytes that follow
    /// the File Meta Information group (whose length (0002,0000) gives, PS3.10 Table 7.1-1).
    static func readStoredFile(_ fileData: Data) throws -> StoredDataSet {
        let file = try DICOMFile.read(from: fileData)
        let meta = file.fileMetaInformation
        guard let ts = meta.string(for: .transferSyntaxUID), !ts.isEmpty else {
            throw ServerError.storageError("Stored file has no Transfer Syntax UID (0002,0010)")
        }
        let sopClass = meta.string(for: .mediaStorageSOPClassUID) ?? file.dataSet.string(for: .sopClassUID) ?? ""
        let sopInstance = meta.string(for: .mediaStorageSOPInstanceUID) ?? file.dataSet.string(for: .sopInstanceUID) ?? ""

        // Preamble (128) + "DICM" (4) + (0002,0000) UL element (12) = 144, then the group.
        var dataSetData: Data
        let base = fileData.startIndex
        if let groupLength = meta.uint32(for: .fileMetaInformationGroupLength),
           fileData.count >= 144,
           fileData[base + 132] == 0x02, fileData[base + 133] == 0x00,
           fileData[base + 134] == 0x00, fileData[base + 135] == 0x00,
           144 + Int(groupLength) <= fileData.count {
            dataSetData = Data(fileData[(base + 144 + Int(groupLength))...])
        } else {
            dataSetData = encodeDataSet(file.dataSet, transferSyntaxUID: ts)
        }
        if dataSetData.isEmpty { dataSetData = encodeDataSet(file.dataSet, transferSyntaxUID: ts) }
        return StoredDataSet(sopClassUID: sopClass, sopInstanceUID: sopInstance,
                             transferSyntaxUID: ts, dataSetData: dataSetData)
    }

    /// The data set bytes of a stored instance in another uncompressed transfer syntax
    /// (C-GET sub-operations over a context that accepted a different syntax).
    static func transcode(_ stored: StoredDataSet, to transferSyntaxUID: String) throws -> Data {
        if stored.transferSyntaxUID == transferSyntaxUID { return stored.dataSetData }
        guard acceptedTransferSyntaxes.contains(stored.transferSyntaxUID),
              acceptedTransferSyntaxes.contains(transferSyntaxUID) else {
            throw ServerError.storageError("Cannot convert \(stored.transferSyntaxUID) to \(transferSyntaxUID)")
        }
        let dataSet = try decodeDataSet(stored.dataSetData, transferSyntaxUID: stored.transferSyntaxUID)
        return encodeDataSet(dataSet, transferSyntaxUID: transferSyntaxUID)
    }

    private static func transferSyntaxOnlyMeta(_ transferSyntaxUID: String) -> DataSet {
        var meta = DataSet()
        meta.setString(transferSyntaxUID, for: .transferSyntaxUID, vr: .UI)
        return meta
    }

    // MARK: - Query/Retrieve Level (PS3.4 C.4.1.1.3.1, C.4.2.1.4.1, C.4.3.1.3.1)

    /// Failure for an Identifier that does not fit the SOP Class.
    ///
    /// PS3.4 Tables C.4-1 / C.4-2 / C.4-3: A900 "Error: Data Set does not match SOP Class",
    /// related fields Offending Element (0000,0901) and Error Comment (0000,0902).
    struct IdentifierError: Error, Equatable {
        let offendingElement: Tag
        let comment: String
        var status: DIMSEStatus { .errorIdentifierDoesNotMatchSOPClass }
    }

    /// Reads and checks Query/Retrieve Level (0008,0052).
    ///
    /// The request Identifier "shall contain" the level; the values are those of Table C.6.1-1
    /// (Patient Root: PATIENT, STUDY, SERIES, IMAGE) and C.6.2-1 (Study Root: STUDY, SERIES, IMAGE).
    static func queryRetrieveLevel(in identifier: DataSet, sopClassUID: String) -> Result<QueryLevel, IdentifierError> {
        guard let raw = identifier.string(for: .queryRetrieveLevel), !raw.isEmpty else {
            return .failure(IdentifierError(
                offendingElement: .queryRetrieveLevel,
                comment: "Query/Retrieve Level (0008,0052) missing"))
        }
        guard let level = QueryLevel(rawValue: raw) else {
            return .failure(IdentifierError(
                offendingElement: .queryRetrieveLevel,
                comment: "Query/Retrieve Level '\(raw)' unknown"))
        }
        if queryRetrieveSOPClasses[sopClassUID]?.model == .studyRoot, level == .patient {
            return .failure(IdentifierError(
                offendingElement: .queryRetrieveLevel,
                comment: "PATIENT level not in the Study Root model"))
        }
        return .success(level)
    }

    /// Adds Offending Element / Error Comment to a failure response (PS3.7 C.4).
    static func addErrorFields(_ error: IdentifierError, to commandSet: inout CommandSet) {
        // AT value: group then element, each 16-bit little endian (Implicit VR LE command set)
        let at = UInt32(error.offendingElement.element) << 16 | UInt32(error.offendingElement.group)
        commandSet.setUInt32(at, for: .offendingElement)
        commandSet.setString(String(error.comment.prefix(64)), for: .errorComment) // LO, 64 chars
    }

    // MARK: - Retrieve sub-operations (PS3.4 C.4.2.3.1, C.4.3.3.1)

    /// Sub-operation counters of a C-MOVE / C-GET
    struct SubOperationCounts: Sendable, Equatable {
        var remaining: UInt16
        var completed: UInt16 = 0
        var failed: UInt16 = 0
        var warning: UInt16 = 0
        var failedSOPInstanceUIDs: [String] = []

        init(total: Int) { remaining = UInt16(clamping: total) }

        /// Records the status of a C-STORE-RSP (PS3.4 Table B.2-1): 0000 completed,
        /// B000/B006/B007 warning, anything else failed.
        mutating func record(_ status: DIMSEStatus?, sopInstanceUID: String) {
            if remaining > 0 { remaining -= 1 }
            guard let status else {
                failed &+= 1; failedSOPInstanceUIDs.append(sopInstanceUID); return
            }
            if status.isSuccess {
                completed &+= 1
            } else if status.isWarning {
                warning &+= 1
            } else {
                failed &+= 1
                failedSOPInstanceUIDs.append(sopInstanceUID)
            }
        }
    }

    /// Final C-MOVE / C-GET status.
    ///
    /// C.4.2.3.1 / C.4.3.3.1: Success if all sub-operations completed; Warning (B000) if one or
    /// more completed and one or more failed or had a warning, or if all had a warning; Failure
    /// if all were unsuccessful — A702 "Refused: Out of resources - Unable to perform
    /// sub-operations", the Failure row of Tables C.4-2 / C.4-3 that carries the counts.
    static func finalRetrieveStatus(_ counts: SubOperationCounts, cancelled: Bool = false) -> DIMSEStatus {
        if cancelled { return .cancel }
        let attempted = Int(counts.completed) + Int(counts.failed) + Int(counts.warning)
        if counts.failed == 0 && counts.warning == 0 { return .success }
        if attempted > 0 && counts.failed == UInt16(clamping: attempted) { return .failedOutOfResources(0xA702) }
        return .warningCoercionOfDataElements // B000
    }

    /// Identifier of a final C-MOVE / C-GET response with Failure, Warning or Cancel status:
    /// Failed SOP Instance UID List (0008,0058) (C.4.2.1.4.2 / C.4.3.1.3.2), nil when no
    /// sub-operation failed.
    static func failedInstancesIdentifier(_ counts: SubOperationCounts) -> DataSet? {
        guard !counts.failedSOPInstanceUIDs.isEmpty else { return nil }
        var ds = DataSet()
        ds.setStrings(counts.failedSOPInstanceUIDs, for: .failedSOPInstanceUIDList, vr: .UI)
        return ds
    }
}
