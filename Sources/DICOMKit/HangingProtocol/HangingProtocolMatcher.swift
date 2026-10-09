// NEMA-verified: 2026a, checked 2026-09-29 — Filter-by Operator semantics (RANGE_INCL, RANGE_EXCL, GREATER/LESS_(OR_EQUAL|THAN), MEMBER_OF, NOT_MEMBER_OF), Filter-by Attribute Presence, Image Set Selector Usage Flag and IMAGE_PLANE classification per PS3.3 2026a Tables C.23.1-1, C.23.3-1 and C.23.3.1.1; level order over Table C.23.1-1 Hanging Protocol Level; Filter Operations Sequence (0072,0400) items applied per display set in item order (C.23.3.1.1), absent usage flag = MATCH per Table C.23.3-1
//
// HangingProtocolMatcher.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Matcher for finding appropriate hanging protocols for studies
///
/// Evaluates study characteristics against hanging protocol environments
/// and selection criteria to determine which protocols are applicable.
public actor HangingProtocolMatcher {
    /// Available hanging protocols
    private var protocols: [HangingProtocol]
    
    public init(protocols: [HangingProtocol] = []) {
        self.protocols = protocols
    }
    
    // MARK: - Protocol Management
    
    /// Add a protocol to the available protocols
    public func add(protocol: HangingProtocol) {
        protocols.append(`protocol`)
    }
    
    /// Remove a protocol by name
    public func remove(protocolNamed name: String) {
        protocols.removeAll { $0.name == name }
    }
    
    /// Get all available protocols
    public func allProtocols() -> [HangingProtocol] {
        return protocols
    }
    
    // MARK: - Protocol Matching
    
    /// Find the best matching protocol for a study
    ///
    /// - Parameters:
    ///   - studyInfo: Study information for matching
    ///   - userGroup: Optional user group for user-specific protocols
    /// - Returns: Best matching protocol, or nil if no match found
    public func matchProtocol(
        for studyInfo: StudyInfo,
        userGroup: String? = nil
    ) -> HangingProtocol? {
        // Find all protocols that match the study
        let matches = matchingProtocols(for: studyInfo, userGroup: userGroup)
        
        // Return the highest priority match
        return matches.first
    }
    
    /// Find all matching protocols for a study, sorted by priority
    ///
    /// - Parameters:
    ///   - studyInfo: Study information for matching
    ///   - userGroup: Optional user group for user-specific protocols
    /// - Returns: Array of matching protocols, sorted by priority (user > group > site)
    public func matchingProtocols(
        for studyInfo: StudyInfo,
        userGroup: String? = nil
    ) -> [HangingProtocol] {
        var matches: [HangingProtocol] = []
        
        for `protocol` in protocols {
            // Check user group match
            if let userGroup = userGroup, !`protocol`.userGroups.isEmpty {
                guard `protocol`.userGroups.contains(userGroup) else {
                    continue
                }
            }
            
            // Check environment match
            if !`protocol`.environments.isEmpty {
                let environmentMatches = `protocol`.environments.contains { env in
                    matchesEnvironment(env, studyInfo: studyInfo)
                }
                
                guard environmentMatches else {
                    continue
                }
            }
            
            matches.append(`protocol`)
        }
        
        // Sort by priority: SINGLE_USER > USER_GROUP > SITE > MANUFACTURER
        matches.sort { lhs, rhs in
            priorityValue(for: lhs.level) > priorityValue(for: rhs.level)
        }
        
        return matches
    }
    
    // MARK: - Private Helpers
    
    private func matchesEnvironment(
        _ environment: HangingProtocolEnvironment,
        studyInfo: StudyInfo
    ) -> Bool {
        // Check modality match
        if let envModality = environment.modality {
            guard studyInfo.modalities.contains(envModality) else {
                return false
            }
        }
        
        // Check laterality match
        if let envLaterality = environment.laterality {
            guard studyInfo.laterality == envLaterality else {
                return false
            }
        }
        
        return true
    }
    
    private func priorityValue(for level: HangingProtocolLevel) -> Int {
        switch level {
        case .user: return 4
        case .group: return 3
        case .site: return 2
        case .manufacturer: return 1
        }
    }
}

// MARK: - Study Info

/// Information about a study for protocol matching
public struct StudyInfo: Sendable {
    /// Study Instance UID
    public let studyInstanceUID: String
    
    /// Modalities present in the study
    public let modalities: Set<String>
    
    /// Anatomic laterality
    public let laterality: String?
    
    /// Study description
    public let studyDescription: String?
    
    /// Body part examined
    public let bodyPartExamined: String?
    
    /// Additional DICOM attributes for matching
    public let attributes: [Tag: String]
    
    public init(
        studyInstanceUID: String,
        modalities: Set<String> = [],
        laterality: String? = nil,
        studyDescription: String? = nil,
        bodyPartExamined: String? = nil,
        attributes: [Tag: String] = [:]
    ) {
        self.studyInstanceUID = studyInstanceUID
        self.modalities = modalities
        self.laterality = laterality
        self.studyDescription = studyDescription
        self.bodyPartExamined = bodyPartExamined
        self.attributes = attributes
    }
    
    /// Create StudyInfo from a DICOM DataSet
    public init?(from dataSet: DataSet) {
        guard let studyUID = dataSet.string(for: .studyInstanceUID) else {
            return nil
        }
        
        self.studyInstanceUID = studyUID
        
        // Extract modality (may be from series)
        if let modality = dataSet.string(for: .modality) {
            self.modalities = [modality]
        } else {
            self.modalities = []
        }
        
        self.laterality = dataSet.string(for: .laterality)
        self.studyDescription = dataSet.string(for: .studyDescription)
        self.bodyPartExamined = dataSet.string(for: .bodyPartExamined)
        self.attributes = [:]
    }
}

// MARK: - Image Set Matcher

/// Matcher for selecting images based on image set selectors
public struct ImageSetMatcher {
    private let imageSet: ImageSetDefinition
    
    public init(imageSet: ImageSetDefinition) {
        self.imageSet = imageSet
    }
    
    /// Check if an instance matches the image set selectors
    ///
    /// Every selector must match. A selector matches when the image's
    /// attribute equals any one of its values (PS3.3 C.23.1.1.2); a selector
    /// that carries a deprecated filter attribute is evaluated as that filter.
    ///
    /// - Parameter instance: Instance information to match
    /// - Returns: true if the instance matches all selectors
    public func matches(instance: InstanceInfo) -> Bool {
        imageSet.selectors.allSatisfy { Self.evaluate($0, instance: instance) }
    }

    /// Check if an instance belongs to the image set and passes the Filter
    /// Operations Sequence (0072,0400) of a display set that shows it.
    /// Filters apply in item order, each on the output of the previous one
    /// (an AND, PS3.3 C.23.3.1.1).
    public func matches(instance: InstanceInfo, filteredBy displaySet: DisplaySet) -> Bool {
        matches(instance: instance)
            && displaySet.filterOperations.allSatisfy { Self.evaluate($0, instance: instance) }
    }

    /// Evaluates one selector against an instance (see `evaluate(_:)` on
    /// `Criterion`).
    static func evaluate(_ selector: ImageSetSelector, instance: InstanceInfo) -> Bool {
        Criterion(
            attribute: selector.attribute,
            valueNumber: selector.valueNumber,
            filterByCategory: selector.legacyFilterByCategory,
            presence: selector.legacyAttributePresence ?? selector.legacyOperator?.presenceTerm,
            operator: selector.legacyOperator,
            values: selector.values,
            usageFlag: selector.usageFlag
        ).evaluate(instance)
    }

    /// Evaluates one Filter Operations Sequence item against an instance.
    /// An absent Image Set Selector Usage Flag means MATCH (PS3.3 Table
    /// C.23.3-1).
    static func evaluate(_ filter: FilterOperation, instance: InstanceInfo) -> Bool {
        Criterion(
            attribute: filter.attribute,
            valueNumber: filter.valueNumber,
            filterByCategory: filter.filterByCategory,
            presence: filter.attributePresence ?? filter.operator?.presenceTerm,
            operator: filter.operator,
            values: filter.values,
            usageFlag: filter.usageFlag ?? .match
        ).evaluate(instance)
    }

    /// The comparison shared by selectors and filter operations.
    ///
    /// - Filter-by Attribute Presence (0072,0404) decides on presence alone.
    /// - Filter-by Category IMAGE_PLANE compares the plane computed from
    ///   Image Orientation (Patient) with the `ImagePlane` terms
    ///   (PS3.3 C.23.3.1.1).
    /// - When the attribute is not available in the instance, the Image Set
    ///   Selector Usage Flag (0072,0024) decides: MATCH "consider the image to
    ///   be a match anyway", NO_MATCH "do not consider the image to be a
    ///   match" (PS3.3 Table C.23.1-1).
    /// - Otherwise the Filter-by Operator (0072,0406) of Table C.23.3-1 is
    ///   applied; no operator means MEMBER_OF (equal to one of the values).
    private struct Criterion {
        let attribute: Tag?
        let valueNumber: Int?
        let filterByCategory: FilterByCategory?
        let presence: FilterByAttributePresence?
        let `operator`: FilterOperator?
        let values: [String]
        let usageFlag: SelectorUsageFlag

        func evaluate(_ instance: InstanceInfo) -> Bool {
            let imageValues = self.imageValues(instance)

            if let presence {
                switch presence {
                case .present: return imageValues != nil
                case .notPresent: return imageValues == nil
                }
            }

            guard let imageValues, !imageValues.isEmpty else {
                return usageFlag == .match
            }

            let selectorValues = values.map { $0.trimmingCharacters(in: .whitespaces) }
            let op = `operator`?.standardTerm ?? .memberOf

            switch op {
            case .memberOf:
                guard !selectorValues.isEmpty else { return true }
                return imageValues.contains { matchesText($0, selectorValues: selectorValues) }
            case .notMemberOf:
                return !imageValues.contains { matchesText($0, selectorValues: selectorValues) }
            case .rangeInclusive, .rangeExclusive:
                // Two selector values, the first less than or equal to the second
                guard selectorValues.count >= 2,
                      let low = Double(selectorValues[0]), let high = Double(selectorValues[1]),
                      low <= high else { return false }
                let numbers = imageValues.compactMap(Double.init)
                guard numbers.count == imageValues.count else { return false }
                if op == .rangeInclusive {
                    return numbers.allSatisfy { $0 >= low && $0 <= high }
                }
                return numbers.allSatisfy { $0 < low || $0 > high }
            case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
                guard let bound = selectorValues.first.flatMap(Double.init) else { return false }
                let numbers = imageValues.compactMap(Double.init)
                guard numbers.count == imageValues.count else { return false }
                switch op {
                case .greaterThan: return numbers.allSatisfy { $0 > bound }
                case .greaterThanOrEqual: return numbers.allSatisfy { $0 >= bound }
                case .lessThan: return numbers.allSatisfy { $0 < bound }
                default: return numbers.allSatisfy { $0 <= bound }
                }
            default:
                return false
            }
        }

        /// The instance values compared: the image plane for the IMAGE_PLANE
        /// category, otherwise the attribute's values, restricted to Selector
        /// Value Number (0072,0028) when that is greater than zero. nil when
        /// the attribute (or the selected value) is not available.
        private func imageValues(_ instance: InstanceInfo) -> [String]? {
            if filterByCategory == .imagePlane {
                guard let orientation = instance.attributes[.imageOrientationPatient] else { return nil }
                let cosines = orientation.split(separator: "\\").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                return ImagePlane(imageOrientationPatient: cosines).map { [$0.rawValue] }
            }
            guard let attribute, let raw = instance.attributes[attribute] else { return nil }
            let values = raw.split(separator: "\\", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let number = valueNumber, number > 0 {
                guard number <= values.count else { return nil }
                return [values[number - 1]]
            }
            return values
        }

        /// Exact match, with the deprecated CONTAINS operator keeping its
        /// substring behaviour (PS3.3 C.23.1.1.3 leaves partial matching of
        /// text implementation dependent).
        private func matchesText(_ value: String, selectorValues: [String]) -> Bool {
            if `operator`?.rawValue == "CONTAINS" {
                return selectorValues.contains { value.contains($0) }
            }
            return selectorValues.contains(value)
        }
    }
}

// MARK: - Instance Info

/// Information about an instance for image set matching
public struct InstanceInfo: Sendable {
    /// SOP Instance UID
    public let sopInstanceUID: String
    
    /// Series Instance UID
    public let seriesInstanceUID: String
    
    /// DICOM attributes
    public let attributes: [Tag: String]
    
    public init(
        sopInstanceUID: String,
        seriesInstanceUID: String,
        attributes: [Tag: String] = [:]
    ) {
        self.sopInstanceUID = sopInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.attributes = attributes
    }
    
    /// Create InstanceInfo from a DICOM DataSet
    public init?(from dataSet: DataSet) {
        guard let sopUID = dataSet.string(for: .sopInstanceUID),
              let seriesUID = dataSet.string(for: .seriesInstanceUID) else {
            return nil
        }
        
        self.sopInstanceUID = sopUID
        self.seriesInstanceUID = seriesUID
        
        // Extract commonly used attributes
        var attrs: [Tag: String] = [:]
        if let instanceNumber = dataSet.string(for: .instanceNumber) {
            attrs[.instanceNumber] = instanceNumber
        }
        if let sliceLocation = dataSet.string(for: .sliceLocation) {
            attrs[.sliceLocation] = sliceLocation
        }
        if let modality = dataSet.string(for: .modality) {
            attrs[.modality] = modality
        }
        // Image Orientation (Patient) feeds the IMAGE_PLANE filter category
        if let orientation = dataSet[.imageOrientationPatient]?.stringValues, !orientation.isEmpty {
            attrs[.imageOrientationPatient] = orientation.joined(separator: "\\")
        }

        self.attributes = attrs
    }
}
