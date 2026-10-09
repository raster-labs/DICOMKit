// NEMA-verified: 2026a, checked 2026-10-01 — PS3.3 2026a Table A.8-1 (Secondary Capture Image IOD: Image Pixel C.7.6.3 M, SC Image C.8.6.2 M; 30 module rows dumped); image Storage SOP Classes = DICOMDictionary.StorageSOPClass (PS3.4 2026a Table B.5-1/B.6-1) whose PS3.6 Table A-1 name ends in "Image Storage" or "Image Storage (Retired)"; P-GATEWAY-SC option (a), closes D104; listen --forward builds no template-less data set and reports the same reason (D214)
import Foundation
import DICOMKit
import DICOMCore
import DICOMDictionary

/// P-GATEWAY-SC (closes D104). `hl7-to-dicom` and `fhir-to-dicom` carry demographics and
/// order data, never an image. Without `--template` they used to write a data set that
/// claimed Secondary Capture Image Storage (1.2.840.10008.5.1.4.1.1.7) with no Image Pixel
/// Module and no Conversion Type — not a Secondary Capture Image IOD, whose Image Pixel
/// (C.7.6.3) and SC Image (C.8.6.2) Modules are Mandatory (PS3.3 2026a Table A.8-1).
/// The output is now refused (exit 1) whenever it would claim an image Storage SOP Class
/// with no image: with no `--template`, or with a template that claims one but holds no
/// Pixel Data.
enum GatewayOutputRules {

    /// Why a data set built from HL7/FHIR without a template is not written or sent.
    static let noImageReason = "the output would claim Secondary Capture "
        + "Image Storage (1.2.840.10008.5.1.4.1.1.7) with no image, but the Secondary Capture Image IOD "
        + "requires the Image Pixel and SC Image Modules (PS3.3 2026a Table A.8-1)"

    /// The refusal when `--template` is absent.
    static func missingTemplateMessage(command: String) -> String {
        "\(command) needs --template <file.dcm>: without it \(noImageReason). Give a template "
            + "whose SOP Class the HL7/FHIR data should populate"
    }

    /// D214: `listen --forward` takes no `--template`, so it builds no data set from the HL7
    /// message (the template-less one would be the non-conforming Secondary Capture that
    /// P-GATEWAY-SC refuses) and forwards nothing — C-STORE forwarding is not implemented
    /// (D103). Throws when `destination` is not `scheme://host:port`.
    static func listenerForwardSkipMessage(messageType: String, destination: String) throws -> String {
        guard let url = URL(string: destination) else {
            throw GatewayError.invalidInput("Invalid destination URL: \(destination)")
        }
        guard let host = url.host, let port = url.port else {
            throw GatewayError.invalidInput("Invalid PACS destination format")
        }
        return "Not forwarded to \(host):\(port): \(messageType) message not converted, because listen "
            + "takes no --template and without one \(noImageReason); C-STORE forwarding is not implemented (D103)"
    }

    /// Throws (exit 1) when `--template` is absent.
    static func requireTemplate(_ template: String?, command: String) throws {
        guard let template = template, !template.isEmpty else {
            throw GatewayError.invalidInput(missingTemplateMessage(command: command))
        }
    }

    /// Whether `sopClassUID` is an image Storage SOP Class: a Storage SOP Class of PS3.4
    /// Table B.5-1 / B.6-1 whose PS3.6 Table A-1 name is "… Image Storage".
    static func isImageStorage(_ sopClassUID: String) -> Bool {
        guard StorageSOPClass.isStorage(sopClassUID),
              let name = UIDDictionary.lookup(uid: sopClassUID)?.name else { return false }
        let base = name.hasSuffix(" (Retired)") ? String(name.dropLast(" (Retired)".count)) : name
        return base.hasSuffix("Image Storage")
    }

    /// Pixel Data (7FE0,0010), Float Pixel Data (7FE0,0008) or Double Float Pixel Data (7FE0,0009).
    static func hasPixelData(_ dataSet: DataSet) -> Bool {
        [Tag(group: 0x7FE0, element: 0x0010), Tag(group: 0x7FE0, element: 0x0008),
         Tag(group: 0x7FE0, element: 0x0009)].contains { dataSet[$0] != nil }
    }

    /// Throws (exit 1) when the template claims an image Storage SOP Class but holds no image.
    static func checkTemplate(_ file: DICOMFile, path: String) throws {
        let sopClass = file.dataSet.string(for: .sopClassUID)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
        guard isImageStorage(sopClass), !hasPixelData(file.dataSet) else { return }
        let name = UIDDictionary.lookup(uid: sopClass)?.name ?? sopClass
        throw GatewayError.invalidInput(
            "template \(path) claims \(name) (\(sopClass)) but has no Pixel Data (7FE0,0010); the output "
                + "would claim an image Storage SOP Class with no image (PS3.3 2026a Table A.8-1 / C.7.6.3 "
                + "Image Pixel Module). Use a template that carries its image")
    }
}
