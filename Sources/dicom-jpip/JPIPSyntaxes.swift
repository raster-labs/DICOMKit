// NEMA-verified: 2026a, checked 2026-10-01 — the 4 JPIP Referenced Transfer Syntax UIDs and names diffed against PS3.6 2026a Table A-1 (4 / 4 match); Pixel Data Provider URL (0028,7FE0) per PS3.5 2026a 8.4.1, A.6, A.7, A.11, A.12 and PS3.6 Table 6-1 (UR); JPIP itself (ISO/IEC 15444-9) is out of scope
import Foundation
import DICOMCore
import DICOMKit

/// The JPIP Referenced Transfer Syntaxes (PS3.5 2026a 8.4.1, 10.8, Annex A.6, A.7, A.11, A.12).
/// In a Data Set encoded with one of them, Pixel Data (7FE0,0010) is absent and the pixel data
/// is referenced through Pixel Data Provider URL (0028,7FE0).
enum JPIPSyntaxes {
    struct Syntax {
        let uid: String
        /// PS3.6 Table A-1 name
        let name: String
        /// PS3.5 Annex section
        let annex: String
        let deflated: Bool
    }

    /// PS3.6 2026a Table A-1 rows whose name starts with "JPIP".
    static let all: [Syntax] = [
        Syntax(uid: "1.2.840.10008.1.2.4.94", name: "JPIP Referenced", annex: "A.6", deflated: false),
        Syntax(uid: "1.2.840.10008.1.2.4.95", name: "JPIP Referenced Deflate", annex: "A.7", deflated: true),
        Syntax(uid: "1.2.840.10008.1.2.4.204", name: "JPIP HTJ2K Referenced", annex: "A.11", deflated: false),
        Syntax(uid: "1.2.840.10008.1.2.4.205", name: "JPIP HTJ2K Referenced Deflate", annex: "A.12", deflated: true),
    ]

    static func syntax(_ uid: String) -> Syntax? {
        all.first { $0.uid == uid }
    }

    static func isJPIP(_ uid: String) -> Bool {
        syntax(uid) != nil
    }

    /// The Pixel Data Provider URL (0028,7FE0) of a Data Set encoded with a JPIP Referenced
    /// Transfer Syntax. `DICOMJPIPClient.jpipURI` serves all four (`TransferSyntax.isJPIP` knows
    /// the HTJ2K pair .204 / .205 since D109 was closed on 2026-10-01).
    static func pixelDataProviderURL(from dataset: DataSet, transferSyntaxUID: String) throws -> URL {
        try DICOMJPIPClient.jpipURI(from: dataset, transferSyntaxUID: transferSyntaxUID)
    }
}
