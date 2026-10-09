// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (HL7 v2 ER7 parsing and generation; HL7 is not a NEMA standard)
import Foundation

// MARK: - HL7 v2 Message Types

enum HL7MessageType: String {
    case ADT = "ADT"  // Admission, Discharge, Transfer
    case ORM = "ORM"  // Order Message
    case ORU = "ORU"  // Observation Result
    case unknown = "UNKNOWN"
}

// MARK: - HL7 Segment

struct HL7Segment {
    let id: String
    let fields: [String]
    
    init(id: String, fields: [String]) {
        self.id = id
        self.fields = fields
    }
    
    subscript(index: Int) -> String? {
        guard index < fields.count else { return nil }
        return fields[index]
    }
    
    func field(at index: Int) -> String? {
        self[index]
    }
    
    func component(field: Int, component: Int, separator: Character = "^") -> String? {
        guard let fieldValue = self[field] else { return nil }
        let components = fieldValue.split(separator: separator, omittingEmptySubsequences: false)
        guard component < components.count else { return nil }
        return String(components[component])
    }
}

// MARK: - HL7 Message

struct HL7Message {
    let messageType: HL7MessageType
    let segments: [HL7Segment]
    let raw: String
    
    var messageControlId: String {
        // Extract from MSH-10 field
        if let msh = segment("MSH"), msh.fields.count > 9 {
            return msh.fields[9]
        }
        return ""
    }
    
    init(messageType: HL7MessageType, segments: [HL7Segment], raw: String) {
        self.messageType = messageType
        self.segments = segments
        self.raw = raw
    }
    
    func segment(_ id: String) -> HL7Segment? {
        segments.first { $0.id == id }
    }
    
    func segments(_ id: String) -> [HL7Segment] {
        segments.filter { $0.id == id }
    }
}

// MARK: - HL7 Parser

class HL7Parser {
    private let fieldSeparator: Character = "|"
    private let componentSeparator: Character = "^"
    private let repetitionSeparator: Character = "~"
    private let escapeSeparator: Character = "\\"
    private let subcomponentSeparator: Character = "&"
    
    func parse(_ message: String) throws -> HL7Message {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GatewayError.parsingFailed("Empty HL7 message")
        }
        
        // Split by segment terminator (usually \r or \n)
        let segmentLines = trimmed.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !segmentLines.isEmpty else {
            throw GatewayError.parsingFailed("No valid segments found")
        }
        
        var segments: [HL7Segment] = []
        var messageType: HL7MessageType = .unknown
        
        for line in segmentLines {
            let segment = try parseSegment(line)
            segments.append(segment)
            
            // Extract message type from MSH segment
            if segment.id == "MSH" {
                if let msgTypeField = segment[8] {
                    let typeComponents = msgTypeField.split(separator: componentSeparator)
                    if let firstComponent = typeComponents.first {
                        messageType = HL7MessageType(rawValue: String(firstComponent)) ?? .unknown
                    }
                }
            }
        }
        
        guard !segments.isEmpty else {
            throw GatewayError.parsingFailed("No segments parsed")
        }
        
        return HL7Message(messageType: messageType, segments: segments, raw: message)
    }
    
    private func parseSegment(_ line: String) throws -> HL7Segment {
        guard line.count >= 3 else {
            throw GatewayError.parsingFailed("Segment too short: \(line)")
        }
        
        let segmentId = String(line.prefix(3))
        
        // Special handling for MSH segment (field separator is part of the segment)
        if segmentId == "MSH" {
            let remainder = String(line.dropFirst(3))
            let fields = remainder.split(separator: fieldSeparator, omittingEmptySubsequences: false)
                .map { String($0) }
            return HL7Segment(id: segmentId, fields: fields)
        }
        
        // Standard segment parsing
        let remainder = String(line.dropFirst(3))
        guard remainder.first == fieldSeparator else {
            throw GatewayError.parsingFailed("Invalid segment format: \(line)")
        }
        
        let fieldString = String(remainder.dropFirst())
        let fields = fieldString.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            .map { String($0) }
        
        return HL7Segment(id: segmentId, fields: fields)
    }
    
    func generate(message: HL7Message) -> String {
        var result = ""
        for segment in message.segments {
            result += generateSegment(segment)
            result += "\r"
        }
        return result
    }
    
    private func generateSegment(_ segment: HL7Segment) -> String {
        var result = segment.id
        
        if segment.id == "MSH" {
            // MSH segment includes field separator
            result += String(fieldSeparator)
            result += segment.fields.joined(separator: String(fieldSeparator))
        } else {
            if !segment.fields.isEmpty {
                result += String(fieldSeparator)
                result += segment.fields.joined(separator: String(fieldSeparator))
            }
        }
        
        return result
    }
}

// MARK: - HL7 Builder

class HL7MessageBuilder {
    private var segments: [HL7Segment] = []
    
    func addSegment(id: String, fields: [String]) -> HL7MessageBuilder {
        segments.append(HL7Segment(id: id, fields: fields))
        return self
    }
    
    func addMSH(
        sendingApplication: String,
        sendingFacility: String,
        receivingApplication: String,
        receivingFacility: String,
        messageType: String,
        messageControlId: String
    ) -> HL7MessageBuilder {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "T", with: "")
        
        let fields = [
            "^~\\&",
            sendingApplication,
            sendingFacility,
            receivingApplication,
            receivingFacility,
            timestamp,
            "",
            messageType,
            messageControlId,
            "P",
            "2.5"
        ]
        
        return addSegment(id: "MSH", fields: fields)
    }
    
    func build(messageType: HL7MessageType) throws -> HL7Message {
        guard !segments.isEmpty else {
            throw GatewayError.conversionFailed("No segments added to message")
        }
        
        let parser = HL7Parser()
        let raw = parser.generate(message: HL7Message(messageType: messageType, segments: segments, raw: ""))
        
        return HL7Message(messageType: messageType, segments: segments, raw: raw)
    }
}
