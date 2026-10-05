// PrivateTagIdentifier.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent private DICOM tag vendor identification
//
// NEMA-verified: 2026a, checked 2026-10-05 — `isPrivateGroup` and `isPrivateCreator` checked against PS3.5 2026a
// 7.8.1: odd group, Private Creator Data Elements (gggg,0010-00FF); the five odd groups 7.8.1 excludes from private
// use (0001, 0003, 0005, 0007, FFFF) were reported as private and are now refused. `vendorCreators` is vendor data
// (private creator strings, not in NEMA text; cf. DCMTK private.dic) and was not compared.

import Foundation

/// Platform-independent helper for identifying private DICOM tag vendors.
///
/// Private DICOM tags use odd group numbers and often contain vendor-specific
/// data. This helper identifies the vendor based on the private creator
/// element value or known private group ranges.
public enum PrivateTagIdentifier: Sendable {

    /// Known vendor identifications based on private creator strings.
    private static let vendorCreators: [String: String] = [
        "SIEMENS MR HEADER": "Siemens",
        "SIEMENS CT VA0 GEN": "Siemens",
        "SIEMENS CT VA0 COAD": "Siemens",
        "SIEMENS MED": "Siemens",
        "SIEMENS MED DISPLAY": "Siemens",
        "SIEMENS MED NM": "Siemens",
        "SIEMENS CSA HEADER": "Siemens",
        "SIEMENS CSA NON-IMAGE": "Siemens",
        "SIEMENS SYNGO FRAME SET": "Siemens",
        "GE MEDICAL SYSTEMS GDXM": "GE Healthcare",
        "GEMS_GENIE_1": "GE Healthcare",
        "GEMS_ACQU_01": "GE Healthcare",
        "GEMS_RELA_01": "GE Healthcare",
        "GEMS_IMAG_01": "GE Healthcare",
        "GEMS_SERS_01": "GE Healthcare",
        "GEMS_STDY_01": "GE Healthcare",
        "GEMS_PARM_01": "GE Healthcare",
        "GEMS_DL_FRAME_01": "GE Healthcare",
        "Philips MR Imaging DD 001": "Philips",
        "Philips MR Imaging DD 002": "Philips",
        "Philips MR Imaging DD 003": "Philips",
        "Philips MR Imaging DD 004": "Philips",
        "Philips MR Imaging DD 005": "Philips",
        "PHILIPS MR": "Philips",
        "PHILIPS MR/PART": "Philips",
        "PHILIPS MR SPECTRO;1": "Philips",
        "ELSCINT1": "Elscint",
        "TOSHIBA_MEC_MR3": "Toshiba/Canon",
        "TOSHIBA_MEC_CT3": "Toshiba/Canon",
        "AGFA": "AGFA",
        "AGFA PACS Archive Mirroring 1.0": "AGFA",
        "HOLOGIC, Inc.": "Hologic",
        "FUJI PHOTO FILM Co., Ltd.": "Fujifilm",
        "Applicare/RadWorks/Version 5.0": "Applicare",
        "VARIAN Medical Systems VISION 8.0": "Varian",
        "SPI-P Release 1": "SPI",
    ]

    /// Identifies the vendor from a private creator string.
    ///
    /// - Parameter creator: The private creator element value.
    /// - Returns: The vendor name, or nil if unknown.
    public static func identifyVendor(creator: String) -> String? {
        let trimmed = creator.trimmingCharacters(in: .whitespaces)
        // Exact match first
        if let vendor = vendorCreators[trimmed] {
            return vendor
        }
        // Case-insensitive match
        let upper = trimmed.uppercased()
        for (key, vendor) in vendorCreators {
            if key.uppercased() == upper {
                return vendor
            }
        }
        // Partial match on known vendor prefixes
        return identifyVendorByPrefix(upper)
    }

    /// The odd groups PS3.5 7.8.1 excludes from private use: "Elements with Tags (0001,xxxx),
    /// (0003,xxxx), (0005,xxxx), (0007,xxxx) and (FFFF,xxxx) shall not be used."
    static let reservedOddGroups: Set<UInt16> = [0x0001, 0x0003, 0x0005, 0x0007, 0xFFFF]

    /// Determines if a tag group number is a private group.
    ///
    /// - Parameter group: The tag group number.
    /// - Returns: `true` if the group is odd and not one of the five odd groups PS3.5 7.8.1
    ///   reserves (0001, 0003, 0005, 0007, FFFF).
    public static func isPrivateGroup(_ group: UInt16) -> Bool {
        group % 2 != 0 && !reservedOddGroups.contains(group)
    }

    /// Determines if a tag is a private creator element.
    ///
    /// Private creator elements have an odd group and element 0x0010-0x00FF.
    ///
    /// - Parameters:
    ///   - group: The tag group number.
    ///   - element: The tag element number.
    /// - Returns: `true` if this is a private creator element.
    public static func isPrivateCreator(group: UInt16, element: UInt16) -> Bool {
        isPrivateGroup(group) && element >= 0x0010 && element <= 0x00FF
    }

    /// Returns a display string for a private tag.
    ///
    /// - Parameters:
    ///   - group: The tag group number.
    ///   - element: The tag element number.
    ///   - creator: The private creator string, if known.
    /// - Returns: A formatted display string.
    public static func displayString(group: UInt16, element: UInt16, creator: String?) -> String {
        let tagStr = String(format: "(%04X,%04X)", group, element)

        if let creator = creator {
            if let vendor = identifyVendor(creator: creator) {
                return "\(tagStr) [\(vendor): \(creator)]"
            }
            return "\(tagStr) [\(creator)]"
        }

        return "\(tagStr) [Private]"
    }

    // MARK: - Private

    private static func identifyVendorByPrefix(_ upper: String) -> String? {
        if upper.hasPrefix("SIEMENS") { return "Siemens" }
        if upper.hasPrefix("GE ") || upper.hasPrefix("GEMS_") { return "GE Healthcare" }
        if upper.hasPrefix("PHILIPS") { return "Philips" }
        if upper.hasPrefix("TOSHIBA") { return "Toshiba/Canon" }
        if upper.hasPrefix("AGFA") { return "AGFA" }
        if upper.hasPrefix("HOLOGIC") { return "Hologic" }
        if upper.hasPrefix("FUJI") { return "Fujifilm" }
        if upper.hasPrefix("VARIAN") { return "Varian" }
        return nil
    }
}
