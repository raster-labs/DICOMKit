import Foundation

// NEMA-verified: 2026a, checked 2026-09-28 — payload syntax read against PS3.18 2026a 8.6.1.2.1 (boundary line, per-part Content-Type, CRLF framing, closing delimiter) and RFC 2046 §5.1.1; no table data
/// Parser and generator for multipart MIME messages
///
/// Handles the multipart/related format used in DICOMweb for
/// transferring multiple DICOM objects or parts.
///
/// Reference: PS3.18 Section 8.6.1.2 - Multipart Payload; 8.7.1 - Multipart Media Types
public struct MultipartMIME: Sendable {
    
    // MARK: - Types
    
    /// A single part in a multipart message
    public struct Part: Sendable {
        /// Content-Type header of this part
        public let contentType: DICOMMediaType
        
        /// Additional headers for this part
        public let headers: [String: String]
        
        /// Body data of this part
        public let body: Data
        
        /// Creates a multipart part
        /// - Parameters:
        ///   - contentType: The content type of this part
        ///   - headers: Additional headers
        ///   - body: The body data
        public init(contentType: DICOMMediaType, headers: [String: String] = [:], body: Data) {
            self.contentType = contentType
            self.headers = headers
            self.body = body
        }
        
        /// Creates a DICOM part with Part 10 file data
        /// - Parameter data: The DICOM Part 10 file data
        /// - Returns: A multipart part with application/dicom content type
        public static func dicom(_ data: Data, transferSyntax: String? = nil) -> Part {
            var mediaType = DICOMMediaType.dicom
            if let ts = transferSyntax {
                mediaType = mediaType.withParameter("transfer-syntax", value: ts)
            }
            return Part(contentType: mediaType, body: data)
        }
        
        /// Creates a JSON part
        /// - Parameter data: The JSON data
        /// - Returns: A multipart part with application/dicom+json content type
        public static func dicomJSON(_ data: Data) -> Part {
            return Part(contentType: .dicomJSON, body: data)
        }
        
        /// Creates a bulk data part
        /// - Parameters:
        ///   - data: The binary data
        ///   - contentID: Optional Content-ID header value
        /// - Returns: A multipart part with application/octet-stream content type
        public static func bulkData(_ data: Data, contentID: String? = nil) -> Part {
            var headers: [String: String] = [:]
            if let cid = contentID {
                headers["Content-ID"] = "<\(cid)>"
            }
            return Part(contentType: .octetStream, headers: headers, body: data)
        }
    }
    
    // MARK: - Properties
    
    /// The boundary string used to separate parts
    public let boundary: String
    
    /// The type of the root part (first part)
    public let rootType: DICOMMediaType?
    
    /// The parts in this multipart message
    public let parts: [Part]
    
    // MARK: - Initialization
    
    /// Creates a multipart message
    /// - Parameters:
    ///   - boundary: The boundary string (auto-generated if nil)
    ///   - rootType: The type of the root part
    ///   - parts: The parts to include
    public init(boundary: String? = nil, rootType: DICOMMediaType? = nil, parts: [Part] = []) {
        self.boundary = boundary ?? Self.generateBoundary()
        self.rootType = rootType ?? parts.first?.contentType
        self.parts = parts
    }
    
    // MARK: - Encoding
    
    /// Encodes the multipart message to data
    /// - Returns: The encoded multipart data
    public func encode() -> Data {
        var result = Data()
        
        for part in parts {
            // Boundary delimiter
            result.append(Data("--\(boundary)\r\n".utf8))
            
            // Content-Type header
            result.append(Data("Content-Type: \(part.contentType.description)\r\n".utf8))
            
            // Additional headers
            for (name, value) in part.headers.sorted(by: { $0.key < $1.key }) {
                result.append(Data("\(name): \(value)\r\n".utf8))
            }
            
            // Blank line before body
            result.append(Data("\r\n".utf8))
            
            // Body
            result.append(part.body)
            
            // End of body
            result.append(Data("\r\n".utf8))
        }
        
        // Final boundary
        result.append(Data("--\(boundary)--\r\n".utf8))
        
        return result
    }
    
    /// Returns the Content-Type header value for this multipart message
    public var contentType: DICOMMediaType {
        var mediaType = DICOMMediaType.multipartRelated
            .withParameter("boundary", value: boundary)
        
        if let root = rootType {
            mediaType = mediaType.withParameter("type", value: root.description)
        }
        
        return mediaType
    }
    
    // MARK: - Decoding
    
    /// Parses a multipart message from data
    /// - Parameters:
    ///   - data: The multipart data to parse
    ///   - boundary: The boundary string (if known from Content-Type header)
    /// - Returns: The parsed MultipartMIME
    /// - Throws: DICOMwebError if parsing fails
    public static func parse(data: Data, boundary: String? = nil) throws -> MultipartMIME {
        let boundaryStr: String
        
        if let b = boundary {
            boundaryStr = b
        } else {
            // Try to detect boundary from the data
            guard let detected = detectBoundary(in: data) else {
                throw DICOMwebError.invalidMultipart(reason: "Could not detect boundary")
            }
            boundaryStr = detected
        }
        
        let parts = try parseParts(data: data, boundary: boundaryStr)
        let rootType = parts.first?.contentType
        
        return MultipartMIME(boundary: boundaryStr, rootType: rootType, parts: parts)
    }
    
    /// Parses a multipart message from data using Content-Type header
    /// - Parameters:
    ///   - data: The multipart data to parse
    ///   - contentType: The Content-Type header value
    /// - Returns: The parsed MultipartMIME
    /// - Throws: DICOMwebError if parsing fails
    public static func parse(data: Data, contentType: String) throws -> MultipartMIME {
        guard let mediaType = DICOMMediaType.parse(contentType) else {
            throw DICOMwebError.invalidMultipart(reason: "Invalid Content-Type: \(contentType)")
        }
        
        guard mediaType.type == "multipart" else {
            throw DICOMwebError.invalidMultipart(reason: "Expected multipart type, got: \(mediaType.type)")
        }
        
        guard let boundary = mediaType.parameters["boundary"] else {
            throw DICOMwebError.invalidMultipart(reason: "Missing boundary parameter")
        }
        
        return try parse(data: data, boundary: boundary)
    }
    
    // MARK: - Private Methods
    
    private static func generateBoundary() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<24).map { _ in chars.randomElement()! })
        return "----DICOMKitBoundary\(randomPart)"
    }
    
    private static func detectBoundary(in data: Data) -> String? {
        // Look for the first line starting with "--"
        guard let string = String(data: data.prefix(1000), encoding: .utf8) else {
            return nil
        }
        
        let lines = string.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--") && trimmed.count > 2 && !trimmed.hasSuffix("--") {
                return String(trimmed.dropFirst(2))
            }
        }
        
        return nil
    }
    
    private static func parseParts(data: Data, boundary: String) throws -> [Part] {
        var parts: [Part] = []
        
        let delimiterBytes = Data("--\(boundary)".utf8)
        
        // Find all boundary positions by scanning raw bytes
        let positions = findBoundaryPositions(in: data, delimiter: delimiterBytes)
        
        guard positions.count >= 2 else {
            // Need at least opening and closing boundary
            throw DICOMwebError.invalidMultipart(reason: "No valid boundary delimiters found")
        }
        
        for i in 0 ..< positions.count - 1 {
            let boundaryEnd = positions[i] + delimiterBytes.count
            
            // Check if this is the closing boundary (followed by "--")
            if boundaryEnd + 1 < data.count,
               data[boundaryEnd] == 0x2D, // '-'
               data[boundaryEnd + 1] == 0x2D { // '-'
                break
            }
            
            // Part data starts after the boundary line's CRLF/LF
            let partStart = skipLineEnding(in: data, from: boundaryEnd)
            let partEnd = positions[i + 1]
            
            guard partStart < partEnd else { continue }
            
            // Trim trailing CRLF before next boundary
            var trimmedEnd = partEnd
            if trimmedEnd >= 2, data[trimmedEnd - 2] == 0x0D, data[trimmedEnd - 1] == 0x0A {
                trimmedEnd -= 2
            } else if trimmedEnd >= 1, data[trimmedEnd - 1] == 0x0A {
                trimmedEnd -= 1
            }
            
            let partData = data[partStart ..< trimmedEnd]
            if let part = parsePartData(partData) {
                parts.append(part)
            }
        }
        
        return parts
    }
    
    /// Find all byte offsets where the boundary delimiter occurs at a line boundary.
    ///
    /// Per RFC 2046 §5.1.1, boundary delimiters MUST occur at the beginning of a line,
    /// i.e. at position 0 or immediately following a CRLF (or bare LF).
    /// Matching at arbitrary positions inside binary DICOM pixel data would produce
    /// false positives that truncate multi-instance responses.
    private static func findBoundaryPositions(in data: Data, delimiter: Data) -> [Int] {
        var positions: [Int] = []
        let count = data.count
        let delimCount = delimiter.count
        guard delimCount > 0, count >= delimCount else { return positions }
        
        var i = 0
        while i <= count - delimCount {
            if data[data.startIndex.advanced(by: i) ..< data.startIndex.advanced(by: i + delimCount)] == delimiter {
                // Boundary is valid only at position 0 or after CRLF / bare LF
                let isLineStart: Bool
                if i == 0 {
                    isLineStart = true
                } else if i >= 2,
                          data[data.startIndex.advanced(by: i - 2)] == 0x0D,
                          data[data.startIndex.advanced(by: i - 1)] == 0x0A {
                    isLineStart = true
                } else if data[data.startIndex.advanced(by: i - 1)] == 0x0A {
                    isLineStart = true
                } else {
                    isLineStart = false
                }
                
                if isLineStart {
                    positions.append(i)
                    i += delimCount
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return positions
    }
    
    /// Skip past CRLF or LF at the given position
    private static func skipLineEnding(in data: Data, from offset: Int) -> Int {
        var pos = offset
        if pos < data.count, data[pos] == 0x0D { pos += 1 } // CR
        if pos < data.count, data[pos] == 0x0A { pos += 1 } // LF
        return pos
    }
    
    /// Parse a single part's raw data (headers + blank line + body) in binary
    private static func parsePartData(_ partData: Data) -> Part? {
        guard !partData.isEmpty else { return nil }
        
        // Find the blank line (CRLFCRLF or LFLF) that separates headers from body
        let separatorResult = findHeaderBodySeparator(in: partData)
        
        let headerData: Data
        let bodyData: Data
        
        if let (sepOffset, sepLength) = separatorResult {
            headerData = partData[partData.startIndex ..< partData.startIndex.advanced(by: sepOffset)]
            let bodyStart = partData.startIndex.advanced(by: sepOffset + sepLength)
            bodyData = partData[bodyStart ..< partData.endIndex]
        } else {
            // No header/body separator found — treat entire content as body
            return Part(contentType: .octetStream, body: Data(partData))
        }
        
        // Parse headers as ASCII/UTF-8 text (headers are always text per RFC 2046)
        var contentType: DICOMMediaType = .octetStream
        var headers: [String: String] = [:]
        
        if let headerString = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .ascii) {
            let headerLines: [String]
            if headerString.contains("\r\n") {
                headerLines = headerString.components(separatedBy: "\r\n")
            } else {
                headerLines = headerString.components(separatedBy: "\n")
            }
            
            for line in headerLines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { continue }
                
                if let colonIndex = trimmedLine.firstIndex(of: ":") {
                    let name = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    
                    if name.lowercased() == "content-type" {
                        if let parsed = DICOMMediaType.parse(value) {
                            contentType = parsed
                        }
                    } else {
                        headers[name] = value
                    }
                }
            }
        }
        
        return Part(contentType: contentType, headers: headers, body: Data(bodyData))
    }
    
    /// Find the offset and length of the header/body separator (CRLFCRLF or LFLF)
    private static func findHeaderBodySeparator(in data: Data) -> (offset: Int, length: Int)? {
        let count = data.count
        let base = data.startIndex
        
        // Look for \r\n\r\n
        if count >= 4 {
            for i in 0 ..< count - 3 {
                if data[base.advanced(by: i)] == 0x0D,
                   data[base.advanced(by: i + 1)] == 0x0A,
                   data[base.advanced(by: i + 2)] == 0x0D,
                   data[base.advanced(by: i + 3)] == 0x0A {
                    return (i, 4)
                }
            }
        }
        
        // Fall back to \n\n
        if count >= 2 {
            for i in 0 ..< count - 1 {
                if data[base.advanced(by: i)] == 0x0A,
                   data[base.advanced(by: i + 1)] == 0x0A {
                    return (i, 2)
                }
            }
        }
        
        return nil
    }
}

// MARK: - Builder Pattern

extension MultipartMIME {
    /// Builder for creating multipart messages
    public struct Builder: Sendable {
        private var boundary: String?
        private var rootType: DICOMMediaType?
        private var parts: [Part] = []
        
        /// Creates a new builder
        public init() {}
        
        /// Sets the boundary string
        /// - Parameter boundary: The boundary string
        /// - Returns: The builder for chaining
        public func withBoundary(_ boundary: String) -> Builder {
            var copy = self
            copy.boundary = boundary
            return copy
        }
        
        /// Sets the root type
        /// - Parameter type: The root part type
        /// - Returns: The builder for chaining
        public func withRootType(_ type: DICOMMediaType) -> Builder {
            var copy = self
            copy.rootType = type
            return copy
        }
        
        /// Adds a part
        /// - Parameter part: The part to add
        /// - Returns: The builder for chaining
        public func addPart(_ part: Part) -> Builder {
            var copy = self
            copy.parts.append(part)
            return copy
        }
        
        /// Adds a DICOM part
        /// - Parameters:
        ///   - data: The DICOM Part 10 data
        ///   - transferSyntax: Optional transfer syntax
        /// - Returns: The builder for chaining
        public func addDICOM(_ data: Data, transferSyntax: String? = nil) -> Builder {
            return addPart(.dicom(data, transferSyntax: transferSyntax))
        }
        
        /// Adds a DICOM JSON part
        /// - Parameter data: The JSON data
        /// - Returns: The builder for chaining
        public func addDICOMJSON(_ data: Data) -> Builder {
            return addPart(.dicomJSON(data))
        }
        
        /// Adds a bulk data part
        /// - Parameters:
        ///   - data: The binary data
        ///   - contentID: Optional Content-ID
        /// - Returns: The builder for chaining
        public func addBulkData(_ data: Data, contentID: String? = nil) -> Builder {
            return addPart(.bulkData(data, contentID: contentID))
        }
        
        /// Builds the multipart message
        /// - Returns: The built MultipartMIME
        public func build() -> MultipartMIME {
            return MultipartMIME(boundary: boundary, rootType: rootType, parts: parts)
        }
    }
    
    /// Creates a builder for this multipart message
    public static func builder() -> Builder {
        return Builder()
    }
}
