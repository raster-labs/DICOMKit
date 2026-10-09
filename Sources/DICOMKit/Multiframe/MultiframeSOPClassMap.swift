// NEMA-verified: 2026a, checked 2026-09-29 — 37 SOP Class UIDs and names match PS3.6 2026a Table A-1; Sup 157 kept as provenance
import Foundation
import DICOMCore

/// The single table describing how each multi-frame SOP Class splits into
/// single-frame instances and which single-frame classes may be merged into it.
///
/// Both `dicom-split`/`dicom-merge` and the Studio Workshop derive their
/// behaviour (and their pickers) from this table — never re-hardcode a UID in a
/// tool. Reference: PS3.4 Table B.5-1, PS3.3 A.35–A.38, Sup 157 (Legacy Converted).
public enum MultiframeSOPClassMap {

    // MARK: - UIDs

    public enum UID {
        public static let ctImage = "1.2.840.10008.5.1.4.1.1.2"
        public static let enhancedCT = "1.2.840.10008.5.1.4.1.1.2.1"
        public static let legacyConvertedEnhancedCT = "1.2.840.10008.5.1.4.1.1.2.2"
        public static let mrImage = "1.2.840.10008.5.1.4.1.1.4"
        public static let enhancedMR = "1.2.840.10008.5.1.4.1.1.4.1"
        public static let mrSpectroscopy = "1.2.840.10008.5.1.4.1.1.4.2"
        public static let enhancedMRColor = "1.2.840.10008.5.1.4.1.1.4.3"
        public static let legacyConvertedEnhancedMR = "1.2.840.10008.5.1.4.1.1.4.4"
        public static let petImage = "1.2.840.10008.5.1.4.1.1.128"
        public static let legacyConvertedEnhancedPET = "1.2.840.10008.5.1.4.1.1.128.1"
        public static let enhancedPET = "1.2.840.10008.5.1.4.1.1.130"
        public static let xaImage = "1.2.840.10008.5.1.4.1.1.12.1"
        public static let enhancedXA = "1.2.840.10008.5.1.4.1.1.12.1.1"
        public static let xrfImage = "1.2.840.10008.5.1.4.1.1.12.2"
        public static let enhancedXRF = "1.2.840.10008.5.1.4.1.1.12.2.1"
        public static let xRay3DAngiographic = "1.2.840.10008.5.1.4.1.1.13.1.1"
        public static let xRay3DCraniofacial = "1.2.840.10008.5.1.4.1.1.13.1.2"
        public static let breastTomosynthesis = "1.2.840.10008.5.1.4.1.1.13.1.3"
        public static let breastProjectionPresentation = "1.2.840.10008.5.1.4.1.1.13.1.4"
        public static let breastProjectionProcessing = "1.2.840.10008.5.1.4.1.1.13.1.5"
        public static let usImage = "1.2.840.10008.5.1.4.1.1.6.1"
        public static let usMultiframe = "1.2.840.10008.5.1.4.1.1.3.1"
        public static let enhancedUSVolume = "1.2.840.10008.5.1.4.1.1.6.2"
        public static let nmImage = "1.2.840.10008.5.1.4.1.1.20"
        public static let secondaryCapture = "1.2.840.10008.5.1.4.1.1.7"
        public static let multiframeSingleBitSC = "1.2.840.10008.5.1.4.1.1.7.1"
        public static let multiframeGrayscaleByteSC = "1.2.840.10008.5.1.4.1.1.7.2"
        public static let multiframeGrayscaleWordSC = "1.2.840.10008.5.1.4.1.1.7.3"
        public static let multiframeTrueColorSC = "1.2.840.10008.5.1.4.1.1.7.4"
        public static let rtImage = "1.2.840.10008.5.1.4.1.1.481.1"
        public static let ophthalmicTomography = "1.2.840.10008.5.1.4.1.1.77.1.5.4"
        public static let wideFieldOphthalmicStereographic = "1.2.840.10008.5.1.4.1.1.77.1.5.5"
        public static let wideFieldOphthalmic3D = "1.2.840.10008.5.1.4.1.1.77.1.5.6"
        public static let ivoctPresentation = "1.2.840.10008.5.1.4.1.1.14.1"
        public static let ivoctProcessing = "1.2.840.10008.5.1.4.1.1.14.2"
        public static let segmentation = "1.2.840.10008.5.1.4.1.1.66.4"
        public static let parametricMap = "1.2.840.10008.5.1.4.1.1.30"
    }

    // MARK: - Split side

    /// What `dicom-split` produces for a given multi-frame SOP Class.
    public enum SplitTarget: Sendable, Equatable {
        /// Rewrite to the classic single-frame SOP Class (Enhanced CT → CT Image …).
        case convert(toSOPClassUID: String)
        /// Keep the SOP Class; the IOD is multi-frame by nature and a one-frame
        /// instance is conformant (NM, Breast Tomo, Enhanced US Volume …).
        case sameClass
        /// Splitting into instances makes no sense for this IOD.
        case refuse(reason: String)
    }

    /// Which legacy (non-functional-group) per-frame vector attributes the IOD carries.
    public enum LegacyVectorKind: Sendable, Equatable {
        case none
        /// Cine module: Frame Increment Pointer → Frame Time / Frame Time Vector.
        case cine
        /// NM Image module: Energy Window / Detector / Phase / Rotation / … vectors.
        case nuclearMedicine
    }

    public struct Entry: Sendable {
        public let uid: String
        public let name: String
        public let splitTarget: SplitTarget
        /// True when the IOD uses the Multi-frame Functional Groups module.
        public let hasFunctionalGroups: Bool
        public let legacyVectors: LegacyVectorKind
    }

    /// Every multi-frame SOP Class the tools know about, grouped by family.
    public static let entries: [Entry] = [
        // Enhanced family with a classic counterpart (dcm4che emf2sf parity)
        Entry(uid: UID.enhancedCT, name: "Enhanced CT Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.ctImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedMR, name: "Enhanced MR Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.mrImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedPET, name: "Enhanced PET Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.petImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedXA, name: "Enhanced XA Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.xaImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedXRF, name: "Enhanced XRF Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.xrfImage), hasFunctionalGroups: true, legacyVectors: .none),

        // Legacy Converted (Sup 157) — round-trips to the classic classes by design
        Entry(uid: UID.legacyConvertedEnhancedCT, name: "Legacy Converted Enhanced CT Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.ctImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.legacyConvertedEnhancedMR, name: "Legacy Converted Enhanced MR Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.mrImage), hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.legacyConvertedEnhancedPET, name: "Legacy Converted Enhanced PET Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.petImage), hasFunctionalGroups: true, legacyVectors: .none),

        // Legacy multi-frame with a classic counterpart
        Entry(uid: UID.usMultiframe, name: "Ultrasound Multi-frame Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.usImage), hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.multiframeSingleBitSC, name: "Multi-frame Single Bit Secondary Capture Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.secondaryCapture), hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.multiframeGrayscaleByteSC, name: "Multi-frame Grayscale Byte Secondary Capture Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.secondaryCapture), hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.multiframeGrayscaleWordSC, name: "Multi-frame Grayscale Word Secondary Capture Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.secondaryCapture), hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.multiframeTrueColorSC, name: "Multi-frame True Color Secondary Capture Image Storage",
              splitTarget: .convert(toSOPClassUID: UID.secondaryCapture), hasFunctionalGroups: false, legacyVectors: .cine),

        // Multi-frame by nature, no functional groups: keep the class, slice the vectors
        Entry(uid: UID.nmImage, name: "Nuclear Medicine Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: false, legacyVectors: .nuclearMedicine),
        Entry(uid: UID.xaImage, name: "X-Ray Angiographic Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.xrfImage, name: "X-Ray Radiofluoroscopic Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: false, legacyVectors: .cine),
        Entry(uid: UID.rtImage, name: "RT Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: false, legacyVectors: .cine),

        // Enhanced family without a classic counterpart: keep the class, one frame each
        Entry(uid: UID.xRay3DAngiographic, name: "X-Ray 3D Angiographic Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.xRay3DCraniofacial, name: "X-Ray 3D Craniofacial Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.breastTomosynthesis, name: "Breast Tomosynthesis Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.breastProjectionPresentation, name: "Breast Projection X-Ray Image Storage - For Presentation",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.breastProjectionProcessing, name: "Breast Projection X-Ray Image Storage - For Processing",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedUSVolume, name: "Enhanced US Volume Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.enhancedMRColor, name: "Enhanced MR Color Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.ophthalmicTomography, name: "Ophthalmic Tomography Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.wideFieldOphthalmicStereographic, name: "Wide Field Ophthalmic Photography Stereographic Projection Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.wideFieldOphthalmic3D, name: "Wide Field Ophthalmic Photography 3D Coordinates Image Storage",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.ivoctPresentation, name: "Intravascular OCT Image Storage - For Presentation",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.ivoctProcessing, name: "Intravascular OCT Image Storage - For Processing",
              splitTarget: .sameClass, hasFunctionalGroups: true, legacyVectors: .none),

        // Inherently multi-frame objects: splitting into instances is meaningless
        Entry(uid: UID.segmentation, name: "Segmentation Storage",
              splitTarget: .refuse(reason: "Segmentation objects are inherently multi-frame; split into a concatenation instead"),
              hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.parametricMap, name: "Parametric Map Storage",
              splitTarget: .refuse(reason: "Parametric Map objects are inherently multi-frame; split into a concatenation instead"),
              hasFunctionalGroups: true, legacyVectors: .none),
        Entry(uid: UID.mrSpectroscopy, name: "MR Spectroscopy Storage",
              splitTarget: .refuse(reason: "MR Spectroscopy carries spectroscopy data, not image frames"),
              hasFunctionalGroups: true, legacyVectors: .none),
    ]

    private static let entriesByUID: [String: Entry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.uid, $0) })

    /// The table entry for a SOP Class UID (trailing NUL/space padding tolerated).
    public static func entry(for sopClassUID: String?) -> Entry? {
        guard let uid = sopClassUID else { return nil }
        return entriesByUID[normalize(uid)]
    }

    /// Strips the padding a UI value may carry on disk.
    public static func normalize(_ uid: String) -> String {
        uid.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    /// Whether the SOP Class is a multi-frame IOD (i.e. NumberOfFrames > 1 is conformant).
    public static func isMultiframeIOD(_ sopClassUID: String?) -> Bool {
        entry(for: sopClassUID) != nil
    }

    /// Whether the IOD carries Shared/Per-frame Functional Groups.
    public static func hasFunctionalGroups(_ sopClassUID: String?) -> Bool {
        entry(for: sopClassUID)?.hasFunctionalGroups ?? false
    }

    // MARK: - Merge side

    /// The classic single-frame SOP Classes that may be merged into `targetSOPClassUID`.
    /// `nil` means the target accepts any source (e.g. Secondary Capture).
    public static func allowedMergeSources(forTarget targetSOPClassUID: String) -> Set<String>? {
        // Multi-frame sources of the same family are accepted too (their frames
        // are flattened and re-factored), e.g. re-merging Enhanced CT chunks.
        switch normalize(targetSOPClassUID) {
        case UID.enhancedCT, UID.legacyConvertedEnhancedCT:
            return [UID.ctImage, UID.enhancedCT, UID.legacyConvertedEnhancedCT]
        case UID.enhancedMR, UID.legacyConvertedEnhancedMR:
            return [UID.mrImage, UID.enhancedMR, UID.legacyConvertedEnhancedMR]
        case UID.enhancedPET, UID.legacyConvertedEnhancedPET:
            return [UID.petImage, UID.enhancedPET, UID.legacyConvertedEnhancedPET]
        case UID.enhancedXA:
            return [UID.xaImage, UID.enhancedXA]
        case UID.enhancedXRF:
            return [UID.xrfImage, UID.enhancedXRF]
        case UID.usMultiframe:
            return [UID.usImage, UID.usMultiframe]
        case UID.multiframeGrayscaleByteSC, UID.multiframeGrayscaleWordSC,
             UID.multiframeTrueColorSC, UID.multiframeSingleBitSC:
            return nil
        default:
            return nil
        }
    }

    /// The Modality expected for a merge target (used for the Enhanced Series module).
    public static func modality(forTarget targetSOPClassUID: String) -> Modality? {
        switch normalize(targetSOPClassUID) {
        case UID.enhancedCT, UID.legacyConvertedEnhancedCT: return .ct
        case UID.enhancedMR, UID.legacyConvertedEnhancedMR: return .mr
        case UID.enhancedPET, UID.legacyConvertedEnhancedPET: return .pt
        case UID.enhancedXA: return .xa
        case UID.enhancedXRF: return .rf
        case UID.usMultiframe: return .us
        default: return nil
        }
    }

    /// The best multi-frame target for a classic source SOP Class when the user
    /// asks for `--format auto`: Legacy Converted for CT/MR/PET (the standard's
    /// intended container for converted classic series), the legacy multi-frame
    /// classes for US/SC, and `nil` when the source is already a multi-frame IOD
    /// (XA/XRF/NM/RT) so the standard merge applies.
    public static func automaticMergeTarget(
        forSource sopClassUID: String,
        bitsAllocated: Int,
        samplesPerPixel: Int
    ) -> String? {
        switch normalize(sopClassUID) {
        case UID.ctImage: return UID.legacyConvertedEnhancedCT
        case UID.mrImage: return UID.legacyConvertedEnhancedMR
        case UID.petImage: return UID.legacyConvertedEnhancedPET
        case UID.usImage: return UID.usMultiframe
        case UID.secondaryCapture:
            if samplesPerPixel == 3 { return UID.multiframeTrueColorSC }
            if bitsAllocated == 1 { return UID.multiframeSingleBitSC }
            return bitsAllocated > 8 ? UID.multiframeGrayscaleWordSC : UID.multiframeGrayscaleByteSC
        default:
            return nil
        }
    }
}
