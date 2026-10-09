// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (ICC.1 profile parsing)
//
// ICCProfileParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// Parser for ICC (International Color Consortium) Profile data
///
/// ICC profiles define color transformations to ensure consistent color reproduction
/// across different devices. This parser supports ICC.1:2004-10 specification (v2 and v4).
///
/// Reference: ICC.1:2004-10 - ICC Profile Format Specification
/// Reference: PS3.3 Section C.11.15 - ICC Profile Module
public struct ICCProfileParser: Sendable {
    
    /// Errors that can occur during ICC profile parsing
    public enum ParseError: Error, Sendable, CustomStringConvertible {
        case insufficientData
        case invalidHeader
        case invalidSignature
        case unsupportedVersion
        case invalidTagTable
        case invalidTag(String)
        case corruptedData
        
        public var description: String {
            switch self {
            case .insufficientData:
                return "ICC profile data is too small"
            case .invalidHeader:
                return "ICC profile header is invalid"
            case .invalidSignature:
                return "ICC profile signature mismatch (expected 'acsp')"
            case .unsupportedVersion:
                return "ICC profile version is not supported"
            case .invalidTagTable:
                return "ICC profile tag table is invalid"
            case .invalidTag(let name):
                return "ICC profile tag '\(name)' is invalid"
            case .corruptedData:
                return "ICC profile data is corrupted"
            }
        }
    }
    
    /// Parse ICC profile from data
    ///
    /// - Parameter data: ICC profile binary data
    /// - Returns: Parsed ICC profile information
    /// - Throws: `ParseError` if parsing fails
    public static func parse(_ data: Data) throws -> ParsedICCProfile {
        guard data.count >= 128 else {
            throw ParseError.insufficientData
        }
        
        // Parse header (first 128 bytes per ICC spec)
        let header = try parseHeader(from: data)
        
        // Parse tag table
        let tags = try parseTagTable(from: data, header: header)
        
        // Extract profile type and description
        let profileClass = header.deviceClass
        let description = tags[.profileDescription]?.extractText() ?? "Unknown"
        
        return ParsedICCProfile(
            header: header,
            tags: tags,
            profileClass: profileClass,
            description: description,
            versionMajor: header.version.0,
            versionMinor: header.version.1,
            versionBugfix: header.version.2
        )
    }
    
    // MARK: - Header Parsing
    
    private static func parseHeader(from data: Data) throws -> ICCProfileHeader {
        // ICC Profile Header Layout (128 bytes):
        // Offset | Size | Content
        // 0      | 4    | Profile size
        // 4      | 4    | Preferred CMM type
        // 8      | 4    | Profile version
        // 12     | 4    | Profile/Device class
        // 16     | 4    | Color space of data
        // 20     | 4    | Profile Connection Space (PCS)
        // 24     | 12   | Date and time
        // 36     | 4    | Profile file signature ('acsp')
        // 40     | 4    | Primary platform
        // 44     | 4    | Profile flags
        // 48     | 4    | Device manufacturer
        // 52     | 4    | Device model
        // 56     | 8    | Device attributes
        // 64     | 4    | Rendering intent
        // 68     | 12   | PCS illuminant (XYZ values)
        // 80     | 4    | Profile creator
        // 84     | 16   | Profile ID (MD5 hash)
        // 100    | 28   | Reserved (must be 0)
        
        let profileSize = data.readUInt32BE(at: 0) ?? 0
        let version = data.readUInt32BE(at: 8) ?? 0
        let deviceClass = data.readUInt32BE(at: 12) ?? 0
        let dataColorSpace = data.readUInt32BE(at: 16) ?? 0
        let pcs = data.readUInt32BE(at: 20) ?? 0
        let signature = data.readUInt32BE(at: 36) ?? 0
        let primaryPlatform = data.readUInt32BE(at: 40) ?? 0
        let renderingIntent = data.readUInt32BE(at: 64) ?? 0
        
        // Verify signature is 'acsp' (0x61637370)
        guard signature == 0x61637370 else {
            throw ParseError.invalidSignature
        }
        
        // Parse version (major.minor.bugfix)
        let majorVersion = (version >> 24) & 0xFF
        let minorVersion = (version >> 20) & 0x0F
        let bugfixVersion = (version >> 16) & 0x0F
        
        return ICCProfileHeader(
            profileSize: Int(profileSize),
            versionMajor: Int(majorVersion),
            versionMinor: Int(minorVersion),
            versionBugfix: Int(bugfixVersion),
            deviceClass: ICCDeviceClass(rawValue: deviceClass) ?? .unknown,
            dataColorSpace: ICCColorSpace(rawValue: dataColorSpace) ?? .unknown,
            pcs: ICCColorSpace(rawValue: pcs) ?? .unknown,
            primaryPlatform: ICCPlatform(rawValue: primaryPlatform) ?? .unknown,
            renderingIntent: ICCRenderingIntent(rawValue: renderingIntent) ?? .unknown
        )
    }
    
    // MARK: - Tag Table Parsing
    
    private static func parseTagTable(from data: Data, header: ICCProfileHeader) throws -> [ICCTagSignature: ICCTagData] {
        // Tag table starts at offset 128
        guard data.count >= 132 else {
            throw ParseError.invalidTagTable
        }
        
        let tagCount = data.readUInt32BE(at: 128) ?? 0
        var tags: [ICCTagSignature: ICCTagData] = [:]
        
        // Each tag entry is 12 bytes:
        // 0-3: Tag signature
        // 4-7: Offset to tag data
        // 8-11: Size of tag data
        
        for i in 0..<Int(tagCount) {
            let entryOffset = 132 + (i * 12)
            guard entryOffset + 12 <= data.count else {
                throw ParseError.invalidTagTable
            }
            
            let tagSig = data.readUInt32BE(at: entryOffset) ?? 0
            let tagOffset = Int(data.readUInt32BE(at: entryOffset + 4) ?? 0)
            let tagSize = Int(data.readUInt32BE(at: entryOffset + 8) ?? 0)
            
            // Validate offset and size
            guard tagOffset + tagSize <= data.count else {
                continue // Skip invalid tags
            }
            
            // Extract tag data
            let tagData = data.subdata(in: tagOffset..<(tagOffset + tagSize))
            let signature = ICCTagSignature(rawValue: tagSig) ?? .unknown
            
            tags[signature] = ICCTagData(
                signature: signature,
                data: tagData,
                offset: tagOffset,
                size: tagSize
            )
        }
        
        return tags
    }
}

// MARK: - Supporting Types

/// Parsed ICC profile with header and tag information
public struct ParsedICCProfile: Sendable, Hashable {
    /// ICC profile header
    public let header: ICCProfileHeader
    
    /// Parsed tags from the profile
    public let tags: [ICCTagSignature: ICCTagData]
    
    /// Profile device class
    public let profileClass: ICCDeviceClass
    
    /// Profile description
    public let description: String
    
    /// Profile version major number
    public let versionMajor: Int
    
    /// Profile version minor number
    public let versionMinor: Int
    
    /// Profile version bugfix number
    public let versionBugfix: Int
    
    /// Profile version as tuple (for compatibility)
    public var version: (Int, Int, Int) {
        (versionMajor, versionMinor, versionBugfix)
    }
    
    /// Check if profile is valid for a specific use
    public func isValid(for use: ICCProfileUse) -> Bool {
        switch use {
        case .inputDevice:
            return profileClass == .inputDevice
        case .displayDevice:
            return profileClass == .displayDevice
        case .outputDevice:
            return profileClass == .outputDevice
        case .colorSpace:
            return profileClass == .colorSpaceConversion
        case .deviceLink:
            return profileClass == .deviceLink
        }
    }
}

/// ICC profile header information
public struct ICCProfileHeader: Sendable, Hashable {
    public let profileSize: Int
    public let versionMajor: Int
    public let versionMinor: Int
    public let versionBugfix: Int
    public let deviceClass: ICCDeviceClass
    public let dataColorSpace: ICCColorSpace
    public let pcs: ICCColorSpace
    public let primaryPlatform: ICCPlatform
    public let renderingIntent: ICCRenderingIntent
    
    /// Version as tuple (for compatibility)
    public var version: (Int, Int, Int) {
        (versionMajor, versionMinor, versionBugfix)
    }
}

/// ICC profile device class
public enum ICCDeviceClass: UInt32, Sendable, Hashable {
    case inputDevice = 0x73636E72      // 'scnr'
    case displayDevice = 0x6D6E7472    // 'mntr'
    case outputDevice = 0x70727472     // 'prtr'
    case deviceLink = 0x6C696E6B       // 'link'
    case colorSpaceConversion = 0x73706163 // 'spac'
    case abstract = 0x61627374          // 'abst'
    case namedColor = 0x6E6D636C       // 'nmcl'
    case unknown = 0
}

/// ICC color space types
public enum ICCColorSpace: UInt32, Sendable, Hashable {
    case xyz = 0x58595A20      // 'XYZ '
    case lab = 0x4C616220      // 'Lab '
    case rgb = 0x52474220      // 'RGB '
    case gray = 0x47524159     // 'GRAY'
    case cmyk = 0x434D594B     // 'CMYK'
    case unknown = 0
}

/// ICC primary platform
public enum ICCPlatform: UInt32, Sendable, Hashable {
    case apple = 0x4150504C     // 'APPL'
    case microsoft = 0x4D534654 // 'MSFT'
    case sgi = 0x53474920       // 'SGI '
    case sun = 0x53554E57       // 'SUNW'
    case unknown = 0
}

/// ICC rendering intent
public enum ICCRenderingIntent: UInt32, Sendable, Hashable {
    case perceptual = 0
    case relativeColorimetric = 1
    case saturation = 2
    case absoluteColorimetric = 3
    case unknown = 0xFF
}

/// ICC tag signature (common tags)
public enum ICCTagSignature: UInt32, Sendable, Hashable {
    case profileDescription = 0x64657363  // 'desc'
    case copyright = 0x63707274           // 'cprt'
    case redTRC = 0x72545243              // 'rTRC'
    case greenTRC = 0x67545243            // 'gTRC'
    case blueTRC = 0x62545243             // 'bTRC'
    case redColorant = 0x7258595A         // 'rXYZ'
    case greenColorant = 0x6758595A       // 'gXYZ'
    case blueColorant = 0x6258595A        // 'bXYZ'
    case whitePoint = 0x77747074          // 'wtpt'
    case aToB0 = 0x41324230               // 'A2B0' - Device to PCS
    case aToB1 = 0x41324231               // 'A2B1'
    case aToB2 = 0x41324232               // 'A2B2'
    case bToA0 = 0x42324130               // 'B2A0' - PCS to Device
    case bToA1 = 0x42324131               // 'B2A1'
    case bToA2 = 0x42324132               // 'B2A2'
    case chromaticAdaptation = 0x63686164 // 'chad'
    case unknown = 0
}

/// ICC tag data
public struct ICCTagData: Sendable, Hashable {
    public let signature: ICCTagSignature
    public let data: Data
    public let offset: Int
    public let size: Int
    
    /// Extract text from tag data (for text-based tags)
    public func extractText() -> String? {
        // Text tags typically start with type signature (4 bytes) followed by reserved (4 bytes)
        guard data.count >= 8 else { return nil }
        
        // Common text type signatures: 'desc', 'mluc', 'text'
        let textData = data.dropFirst(8)
        
        // Try UTF-8 decoding
        if let text = String(data: textData, encoding: .utf8) {
            return text.trimmingCharacters(in: .controlCharacters)
        }
        
        // Try ASCII decoding
        if let text = String(data: textData, encoding: .ascii) {
            return text.trimmingCharacters(in: .controlCharacters)
        }
        
        return nil
    }
    
    /// Extract TRC (Tone Reproduction Curve) data
    ///
    /// TRC defines the gamma curve for color reproduction
    ///
    /// - Returns: Array of curve values if TRC tag, nil otherwise
    public func extractTRCCurve() -> [UInt16]? {
        guard data.count >= 12 else { return nil }
        
        // TRC type signature (4 bytes): 'curv' or 'para'
        let typeSignature = data.readUInt32BE(at: 0) ?? 0
        
        if typeSignature == 0x63757276 { // 'curv'
            // Reserved (4 bytes)
            // Count (4 bytes)
            let count = Int(data.readUInt32BE(at: 8) ?? 0)
            
            guard count > 0, data.count >= 12 + (count * 2) else {
                return nil
            }
            
            var curve: [UInt16] = []
            curve.reserveCapacity(count)
            
            for i in 0..<count {
                let offset = 12 + (i * 2)
                if let value = data.readUInt16BE(at: offset) {
                    curve.append(value)
                }
            }
            
            return curve
        }
        
        return nil
    }
    
    /// Extract XYZ color coordinates
    ///
    /// Used for colorant tags (rXYZ, gXYZ, bXYZ) and white point
    ///
    /// - Returns: XYZ coordinates if XYZ tag, nil otherwise
    public func extractXYZ() -> (x: Double, y: Double, z: Double)? {
        guard data.count >= 20 else { return nil }
        
        // XYZ type signature: 'XYZ '
        let typeSignature = data.readUInt32BE(at: 0) ?? 0
        guard typeSignature == 0x58595A20 else { return nil }
        
        // Reserved (4 bytes)
        // X, Y, Z values (4 bytes each, s15Fixed16Number format)
        let xRaw = Int32(bitPattern: data.readUInt32BE(at: 8) ?? 0)
        let yRaw = Int32(bitPattern: data.readUInt32BE(at: 12) ?? 0)
        let zRaw = Int32(bitPattern: data.readUInt32BE(at: 16) ?? 0)
        
        // Convert s15Fixed16Number to Double (divide by 2^16)
        let x = Double(xRaw) / 65536.0
        let y = Double(yRaw) / 65536.0
        let z = Double(zRaw) / 65536.0
        
        return (x: x, y: y, z: z)
    }
}

/// ICC profile use cases
public enum ICCProfileUse: Sendable {
    case inputDevice
    case displayDevice
    case outputDevice
    case colorSpace
    case deviceLink
}
