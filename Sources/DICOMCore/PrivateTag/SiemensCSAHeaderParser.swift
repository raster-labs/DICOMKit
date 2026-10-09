// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (vendor-private CSA binary format). C1 classification confirmed.

import Foundation

/// Siemens CSA Header Parser
///
/// Parses Siemens proprietary CSA (Common Siemens Architecture) headers.
/// These headers contain additional MR acquisition parameters not in standard DICOM.
///
/// Reference: Siemens CSA Header format (reverse-engineered specification)
public struct SiemensCSAHeader: Sendable {
    /// CSA header version (SV10 or earlier)
    public let version: String
    
    /// CSA tags (name-value pairs)
    public let tags: [String: CSATag]
    
    /// CSA Tag
    public struct CSATag: Sendable {
        /// Tag name
        public let name: String
        
        /// Tag VM (value multiplicity)
        public let vm: Int
        
        /// Tag VR (value representation as string)
        public let vr: String
        
        /// Tag values
        public let values: [String]
        
        /// Syngo DT (data type)
        public let syngoDT: Int
        
        /// Number of items
        public let numberOfItems: Int
    }
}

/// Siemens CSA Header Parser
public struct SiemensCSAHeaderParser: Sendable {
    /// Parse CSA header from binary data
    /// - Parameter data: CSA header binary data
    /// - Returns: Parsed CSA header, or nil if parsing fails
    public static func parse(_ input: Data) -> SiemensCSAHeader? {
        guard input.count >= 4 else { return nil }

        // Normalize to 0-based storage. This parser mixes subdata(in:) (which
        // uses Data's own index space) with withUnsafeBytes/loadUnaligned
        // (0-based); on a sliced Data with a non-zero startIndex the two
        // disagree, causing wrong reads or a trap. Rebasing makes them consistent.
        let data = input.withUnsafeBytes { Data($0) }

        var offset = 0
        
        // Read version string (4 bytes for "SV10" or earlier)
        guard let versionData = data.subdata(in: offset..<min(offset + 4, data.count)) as Data?,
              let version = String(data: versionData, encoding: .ascii) else {
            return nil
        }
        offset += 4
        
        // Check for known version
        guard version == "SV10" else {
            // Try to parse older format - not fully implemented
            return nil
        }
        
        // Read unused bytes (4 bytes)
        offset += 4
        
        // Read number of tags (4 bytes, little endian)
        guard offset + 4 <= data.count else { return nil }
        let numberOfTags = data.withUnsafeBytes { bytes in
            bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        
        // Read unused bytes (4 bytes)
        offset += 4
        
        var tags: [String: SiemensCSAHeader.CSATag] = [:]
        
        // Parse each tag
        for _ in 0..<numberOfTags {
            guard let tag = parseCSATag(from: data, offset: &offset) else {
                break
            }
            tags[tag.name] = tag
        }
        
        return SiemensCSAHeader(version: version, tags: tags)
    }
    
    private static func parseCSATag(from data: Data, offset: inout Int) -> SiemensCSAHeader.CSATag? {
        // Tag name (64 bytes, null-terminated)
        guard offset + 64 <= data.count else { return nil }
        let nameData = data.subdata(in: offset..<offset + 64)
        guard let name = String(data: nameData, encoding: .ascii)?.components(separatedBy: "\0").first else {
            return nil
        }
        offset += 64
        
        // VM (4 bytes)
        guard offset + 4 <= data.count else { return nil }
        let vm = data.withUnsafeBytes { bytes in
            Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
        offset += 4
        
        // VR (4 bytes, null-terminated string)
        guard offset + 4 <= data.count else { return nil }
        let vrData = data.subdata(in: offset..<offset + 4)
        let vr = String(data: vrData, encoding: .ascii)?.components(separatedBy: "\0").first ?? ""
        offset += 4
        
        // Syngo DT (4 bytes)
        guard offset + 4 <= data.count else { return nil }
        let syngoDT = data.withUnsafeBytes { bytes in
            Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
        offset += 4
        
        // Number of items (4 bytes)
        guard offset + 4 <= data.count else { return nil }
        let numberOfItems = data.withUnsafeBytes { bytes in
            Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
        offset += 4
        
        // Unused (4 bytes)
        offset += 4
        
        var values: [String] = []
        
        // Parse items
        for _ in 0..<numberOfItems {
            // Length of item (4 bytes, includes padding to 4-byte boundary)
            guard offset + 4 <= data.count else { break }
            let length = data.withUnsafeBytes { bytes in
                Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            offset += 4
            
            // Item value
            guard offset + length <= data.count else { break }
            let valueData = data.subdata(in: offset..<offset + length)
            if let value = String(data: valueData, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) {
                values.append(value)
            }
            
            // Skip padding to 4-byte boundary
            let paddedLength = (length + 3) & ~3
            offset += paddedLength
            
            // Skip delimiter (4 bytes of 0x4D)
            offset += 4
        }
        
        return SiemensCSAHeader.CSATag(
            name: name,
            vm: vm,
            vr: vr,
            values: values,
            syngoDT: syngoDT,
            numberOfItems: numberOfItems
        )
    }
}
