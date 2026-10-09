// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data of its own. Since P10 it
// reads template rows as PS3.16 2026a §6.1 defines them: nesting by NL, INCLUDE expanded with the
// §6.2 parameter bindings, M rows required, VM counted, extra content allowed only where a template
// is Type Extensible, Code Meaning not significant when comparing codes.
// NEMA-verified: 2026a, checked 2026-09-29 — nested rows are matched against the Content Sequence of
// any value type, not only CONTAINER, per PS3.3 2026a Table C.17-6 (D31).
// NEMA-verified: 2026a, checked 2026-09-30 — when an item matches several rows equally well (e.g.
// TID 1500 rows 7, 8 and 9, which INCLUDE TID 1410, 1411 and 1501, all rooted in the same
// (125007, DCM) CONTAINER), it is checked against each and assigned to the row whose pattern of
// target content items describes it: PS3.16 2026a §6.2.2 (each pattern of targets of the same
// source item begins its own row), §6.2.3 (the included rows replace the INCLUDE row) and §6.2.5
// (content a template does not describe is an extension). Fewest items left to extension wins,
// then fewest errors, then fewest warnings, then table order (D52).

/// DICOM SR Template Validation
///
/// Provides validation of SR content against template definitions.
///
/// Reference: PS3.16 Section 5 - Template Specifications

import Foundation

// MARK: - Template Violation

/// Represents a violation of template constraints
public struct TemplateViolation: Sendable, Equatable {
    /// Severity of the violation
    public enum Severity: String, Sendable, Equatable, CaseIterable {
        /// Error - document is non-compliant
        case error
        /// Warning - potential issue but may be acceptable
        case warning
        /// Info - informational message
        case info
    }
    
    /// The severity of this violation
    public let severity: Severity
    
    /// The template row that was violated (if applicable)
    public let templateRowID: String?
    
    /// Path to the content item that caused the violation
    public let contentPath: String?
    
    /// Human-readable description of the violation
    public let message: String
    
    /// Additional details about the violation
    public let details: String?
    
    /// Creates a template violation
    public init(
        severity: Severity,
        templateRowID: String? = nil,
        contentPath: String? = nil,
        message: String,
        details: String? = nil
    ) {
        self.severity = severity
        self.templateRowID = templateRowID
        self.contentPath = contentPath
        self.message = message
        self.details = details
    }
    
    // MARK: - Factory Methods
    
    /// Creates a missing required content violation
    public static func missingRequired(
        rowID: String?,
        conceptName: CodedConcept?,
        path: String?
    ) -> TemplateViolation {
        let conceptDesc = conceptName?.codeMeaning ?? "content item"
        return TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Missing required \(conceptDesc)",
            details: conceptName.map { "Expected: \($0.codeValue) - \($0.codeMeaning)" }
        )
    }
    
    /// Creates a cardinality violation
    public static func cardinalityViolation(
        rowID: String?,
        expected: Cardinality,
        actual: Int,
        conceptName: CodedConcept?,
        path: String?
    ) -> TemplateViolation {
        let conceptDesc = conceptName?.codeMeaning ?? "content item"
        return TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Cardinality violation for \(conceptDesc): expected \(expected), found \(actual)",
            details: nil
        )
    }
    
    /// Creates a value type mismatch violation
    public static func valueTypeMismatch(
        rowID: String?,
        expected: ContentItemValueType,
        actual: ContentItemValueType,
        path: String?
    ) -> TemplateViolation {
        TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Value type mismatch: expected \(expected.rawValue), found \(actual.rawValue)",
            details: nil
        )
    }
    
    /// Creates a relationship type mismatch violation
    public static func relationshipMismatch(
        rowID: String?,
        expected: RelationshipType,
        actual: RelationshipType?,
        path: String?
    ) -> TemplateViolation {
        TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Relationship type mismatch: expected \(expected.rawValue), found \(actual?.rawValue ?? "none")",
            details: nil
        )
    }
    
    /// Creates an invalid concept violation
    public static func invalidConcept(
        rowID: String?,
        expected: ConceptNameConstraint,
        actual: CodedConcept?,
        path: String?
    ) -> TemplateViolation {
        let actualDesc = actual?.codeMeaning ?? "none"
        return TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Invalid concept name: found '\(actualDesc)'",
            details: "Expected: \(expected)"
        )
    }
    
    /// Creates an invalid value violation
    public static func invalidValue(
        rowID: String?,
        constraint: ValueConstraint,
        path: String?
    ) -> TemplateViolation {
        TemplateViolation(
            severity: .error,
            templateRowID: rowID,
            contentPath: path,
            message: "Value does not satisfy constraint",
            details: "Constraint: \(constraint)"
        )
    }
    
    /// Creates a warning for unexpected content
    public static func unexpectedContent(
        path: String?,
        message: String
    ) -> TemplateViolation {
        TemplateViolation(
            severity: .warning,
            templateRowID: nil,
            contentPath: path,
            message: message,
            details: nil
        )
    }
}

extension TemplateViolation: CustomStringConvertible {
    public var description: String {
        var result = "[\(severity.rawValue.uppercased())]"
        if let path = contentPath {
            result += " at \(path)"
        }
        if let rowID = templateRowID {
            result += " (row \(rowID))"
        }
        result += ": \(message)"
        if let details = details {
            result += " - \(details)"
        }
        return result
    }
}

// MARK: - Template Validation Result

/// Result of validating content against a template
public struct TemplateValidationResult: Sendable {
    /// The template that was validated against
    public let templateIdentifier: TemplateIdentifier
    
    /// All violations found during validation
    public let violations: [TemplateViolation]
    
    /// Whether the content is compliant (no errors)
    public var isCompliant: Bool {
        !violations.contains { $0.severity == .error }
    }
    
    /// Whether the content is fully compliant (no errors or warnings)
    public var isFullyCompliant: Bool {
        violations.isEmpty
    }
    
    /// All errors
    public var errors: [TemplateViolation] {
        violations.filter { $0.severity == .error }
    }
    
    /// All warnings
    public var warnings: [TemplateViolation] {
        violations.filter { $0.severity == .warning }
    }
    
    /// Number of errors
    public var errorCount: Int {
        errors.count
    }
    
    /// Number of warnings
    public var warningCount: Int {
        warnings.count
    }
    
    /// Creates a validation result
    public init(templateIdentifier: TemplateIdentifier, violations: [TemplateViolation]) {
        self.templateIdentifier = templateIdentifier
        self.violations = violations
    }
    
    /// Creates a successful validation result
    public static func success(for template: TemplateIdentifier) -> TemplateValidationResult {
        TemplateValidationResult(templateIdentifier: template, violations: [])
    }
}

// MARK: - Validation Mode

/// Mode for template validation
public enum TemplateValidationMode: Sendable, Equatable {
    /// Strict validation - all constraints must be satisfied
    case strict
    
    /// Lenient validation - only mandatory items are required
    case lenient
    
    /// Check only - report all issues but don't fail on warnings
    case checkOnly
}

// MARK: - Template Validator

/// Validates SR content against template definitions
///
/// Example:
/// ```swift
/// let validator = TemplateValidator()
/// let result = try validator.validate(document, against: .measurementReport)
/// if result.isCompliant {
///     print("Document is compliant with TID 1500")
/// } else {
///     for error in result.errors {
///         print(error)
///     }
/// }
/// ```
public struct TemplateValidator: Sendable {
    /// The validation mode
    public let mode: TemplateValidationMode
    
    /// Maximum depth to validate
    public let maxDepth: Int
    
    /// Creates a template validator
    /// - Parameters:
    ///   - mode: The validation mode (default: strict)
    ///   - maxDepth: Maximum nesting depth to validate (default: 50)
    public init(mode: TemplateValidationMode = .strict, maxDepth: Int = 50) {
        self.mode = mode
        self.maxDepth = maxDepth
    }
    
    /// Validates content items against a template
    /// - Parameters:
    ///   - contentItems: The content items to validate
    ///   - templateIdentifier: The template to validate against
    /// - Returns: The validation result
    public func validate(
        _ contentItems: [AnyContentItem],
        against templateIdentifier: TemplateIdentifier
    ) -> TemplateValidationResult {
        guard let templateType = TemplateRegistry.shared.template(for: templateIdentifier) else {
            return TemplateValidationResult(
                templateIdentifier: templateIdentifier,
                violations: [
                    TemplateViolation(
                        severity: .error,
                        message: "Unknown template: \(templateIdentifier)",
                        details: nil
                    )
                ]
            )
        }
        
        var violations: [TemplateViolation] = []
        validateAgainstTemplate(
            contentItems: contentItems,
            template: templateType,
            path: "/",
            depth: 0,
            violations: &violations
        )
        
        return TemplateValidationResult(
            templateIdentifier: templateIdentifier,
            violations: violations
        )
    }
    
    /// Validates a single content item against a template
    /// - Parameters:
    ///   - contentItem: The content item to validate
    ///   - templateIdentifier: The template to validate against
    /// - Returns: The validation result
    public func validate(
        _ contentItem: AnyContentItem,
        against templateIdentifier: TemplateIdentifier
    ) -> TemplateValidationResult {
        validate([contentItem], against: templateIdentifier)
    }
    
    // MARK: - Private Validation Methods

    private func validateAgainstTemplate(
        contentItems: [AnyContentItem],
        template: any SRTemplate.Type,
        path: String,
        depth: Int,
        violations: inout [TemplateViolation]
    ) {
        let level = TemplateMatcher.expand(
            TemplateMatcher.tree(template.rows),
            template: template,
            parameters: [:],
            relationship: nil,
            groups: [],
            repeatable: false,
            visited: [template.identifier.templateID]
        )
        var unaccounted = 0
        validateLevel(contentItems: contentItems, level: level, path: path, depth: depth,
                      violations: &violations, unaccounted: &unaccounted)
    }

    /// Validates the content items of one nesting level against the rows that apply there.
    ///
    /// `unaccounted` is increased by the number of content items (with their descendants) that
    /// no row describes, at this level and below: content an Extensible template allows as an
    /// extension (PS3.16 §6.2.5), and the measure of how well a row's pattern fits an item.
    private func validateLevel(
        contentItems: [AnyContentItem],
        level: TemplateMatcher.Level,
        path: String,
        depth: Int,
        violations: inout [TemplateViolation],
        unaccounted: inout Int
    ) {
        guard depth <= maxDepth else {
            violations.append(TemplateViolation(
                severity: .warning,
                contentPath: path,
                message: "Maximum validation depth exceeded",
                details: nil
            ))
            return
        }

        let slots = level.slots
        var assigned = Array(repeating: [AnyContentItem](), count: slots.count)
        // Violations of an item already checked while its row was chosen, parallel to `assigned`
        var checked = Array(repeating: [[TemplateViolation]?](), count: slots.count)
        var unmatched: [AnyContentItem] = []
        for item in contentItems {
            let candidates = TemplateMatcher.bestSlots(for: item, in: slots)
            guard let first = candidates.first else {
                unmatched.append(item)
                continue
            }
            guard candidates.count > 1 else {
                assigned[first].append(item)
                checked[first].append(nil)
                continue
            }
            // Several rows match the item equally well (e.g. TID 1500 rows 7-9: the root rows of
            // TID 1410, 1411 and 1501 are the same Measurement Group CONTAINER). Each describes a
            // different pattern of target content items (PS3.16 §6.2.2); the item belongs to the
            // one whose pattern describes it: fewest items left to extension (§6.2.5), then
            // fewest errors, then fewest warnings, then the first in table order.
            var best: (index: Int, fit: (Int, Int, Int), violations: [TemplateViolation], unaccounted: Int)?
            for index in candidates {
                var trial: [TemplateViolation] = []
                var trialUnaccounted = 0
                validateItem(
                    item,
                    slot: slots[index],
                    path: itemPath(path, item, index: assigned[index].count),
                    depth: depth,
                    violations: &trial,
                    unaccounted: &trialUnaccounted
                )
                let errors = trial.filter { $0.severity == .error }.count
                let fit = (trialUnaccounted, errors, trial.count - errors)
                if best == nil || fit < best!.fit {
                    best = (index, fit, trial, trialUnaccounted)
                }
            }
            let chosen = best!
            assigned[chosen.index].append(item)
            checked[chosen.index].append(chosen.violations)
            unaccounted += chosen.unaccounted
        }

        // An optional INCLUDE is present when any of its rows has content; its M rows then apply.
        var presentGroups = Set<Int>()
        for (index, slot) in slots.enumerated() where !assigned[index].isEmpty {
            presentGroups.formUnion(slot.groups)
        }

        for (index, slot) in slots.enumerated() {
            let row = slot.row
            let items = assigned[index]
            let conceptName = TemplateMatcher.expectedConcept(row.conceptName, parameters: slot.parameters)

            if items.isEmpty {
                // Only M rows are checked for absence: MC and UC conditions are free text.
                if row.requirementLevel == .mandatory && presentGroups.isSuperset(of: slot.groups) {
                    violations.append(.missingRequired(rowID: row.rowID, conceptName: conceptName, path: path))
                }
            } else {
                let vm = row.valueMultiplicity
                let tooMany = !slot.repeatable && vm.maximum.map { items.count > $0 } == true
                if items.count < vm.minimum || tooMany {
                    violations.append(.cardinalityViolation(
                        rowID: row.rowID,
                        expected: slot.repeatable ? Cardinality(minimum: vm.minimum) : vm,
                        actual: items.count,
                        conceptName: conceptName,
                        path: path
                    ))
                }
            }

            for (itemIndex, item) in items.enumerated() {
                if let found = checked[index][itemIndex] {
                    violations += found
                } else {
                    validateItem(
                        item,
                        slot: slot,
                        path: itemPath(path, item, index: itemIndex),
                        depth: depth,
                        violations: &violations,
                        unaccounted: &unaccounted
                    )
                }
            }
        }

        for item in unmatched {
            unaccounted += Self.size(of: item)
        }

        // Extensible templates allow additional content at any level (PS3.16 §6.1);
        // a level that includes an unregistered template cannot be judged either.
        if mode != .lenient && !level.isExtensible && !level.isOpen {
            for item in unmatched {
                violations.append(.unexpectedContent(
                    path: path,
                    message: "Unexpected content item: \(item.conceptName?.codeMeaning ?? item.valueType.rawValue)"
                ))
            }
        }
    }

    /// Checks one item against the row it is assigned to: its value, then the rows nested
    /// under that row against the item's Content Sequence.
    private func validateItem(
        _ item: AnyContentItem,
        slot: TemplateMatcher.Slot,
        path: String,
        depth: Int,
        violations: inout [TemplateViolation],
        unaccounted: inout Int
    ) {
        let row = slot.row
        if !TemplateMatcher.valueSatisfies(item, row.valueConstraint, parameters: slot.parameters) {
            violations.append(.invalidValue(rowID: row.rowID, constraint: row.valueConstraint, path: path))
        }
        let childLevel = TemplateMatcher.expand(
            slot.node.children,
            template: slot.template,
            parameters: slot.parameters,
            relationship: nil,
            groups: [],
            repeatable: false,
            visited: slot.visited
        )
        // The rows nested under this one (NL ">") are checked against the item's
        // Content Sequence, which any value type may carry (PS3.3 Table C.17-6), so
        // e.g. TID 1204 row 2 is found under the row 1 CODE.
        validateLevel(
            contentItems: item.contentItems,
            level: childLevel,
            path: path,
            depth: depth + 1,
            violations: &violations,
            unaccounted: &unaccounted
        )
    }

    private func itemPath(_ path: String, _ item: AnyContentItem, index: Int) -> String {
        "\(path)/\(item.conceptName?.codeMeaning ?? item.valueType.rawValue)[\(index)]"
    }

    /// The item and all its descendants
    private static func size(of item: AnyContentItem) -> Int {
        item.contentItems.reduce(1) { $0 + size(of: $1) }
    }
}

// MARK: - Template Matching

/// Walks template rows the way PS3.16 §6.1 reads them: nesting by NL, INCLUDE rows
/// replaced by the included template's rows with the parameter bindings in force.
enum TemplateMatcher {
    /// A row together with the rows nested under it
    struct Node {
        let row: TemplateRow
        let children: [Node]
    }

    /// A content-item row as it applies at one level after INCLUDE expansion
    struct Slot {
        let node: Node
        let template: any SRTemplate.Type
        let relationship: RelationshipType?
        let parameters: [String: TemplateParameterValue]
        /// The INCLUDE rows that are not M (MC, U, UC) this row was included through, one id
        /// per INCLUDE; its M rows are required only when each of them has content
        let groups: [Int]
        /// Included through an INCLUDE row with VM 1-n, so its rows may repeat
        let repeatable: Bool
        let visited: Set<String>

        var row: TemplateRow { node.row }
    }

    /// The rows that apply at one level
    struct Level {
        var slots: [Slot] = []
        var isExtensible = false
        /// Includes a template that is not registered, so its rows are unknown
        var isOpen = false
    }

    /// Nests rows by nesting level. Rows deeper than the level following their parent are
    /// attached to the nearest shallower row.
    static func tree(_ rows: [TemplateRow]) -> [Node] {
        var index = 0
        return build(rows, &index, level: rows.first?.nestingLevel ?? 0)
    }

    private static func build(_ rows: [TemplateRow], _ index: inout Int, level: Int) -> [Node] {
        var nodes: [Node] = []
        while index < rows.count && rows[index].nestingLevel >= level {
            let row = rows[index]
            index += 1
            let children = build(rows, &index, level: row.nestingLevel + 1)
            nodes.append(Node(row: row, children: children))
        }
        return nodes
    }

    static func expand(
        _ nodes: [Node],
        template: any SRTemplate.Type,
        parameters: [String: TemplateParameterValue],
        relationship: RelationshipType?,
        groups: [Int],
        repeatable: Bool,
        visited: Set<String>
    ) -> Level {
        var nextGroup = 0
        return expand(nodes, template: template, parameters: parameters, relationship: relationship,
                      groups: groups, repeatable: repeatable, visited: visited, nextGroup: &nextGroup)
    }

    private static func expand(
        _ nodes: [Node],
        template: any SRTemplate.Type,
        parameters: [String: TemplateParameterValue],
        relationship: RelationshipType?,
        groups: [Int],
        repeatable: Bool,
        visited: Set<String>,
        nextGroup: inout Int
    ) -> Level {
        var level = Level(isExtensible: template.isExtensible)
        for node in nodes {
            let row = node.row
            guard let included = row.includedTemplate else {
                level.slots.append(Slot(
                    node: node,
                    template: template,
                    relationship: row.relationshipType ?? relationship,
                    parameters: parameters,
                    groups: groups,
                    repeatable: repeatable,
                    visited: visited
                ))
                continue
            }
            guard !visited.contains(included.templateID),
                  let includedType = TemplateRegistry.shared.template(for: included) else {
                level.isOpen = true
                continue
            }
            var bound: [String: TemplateParameterValue] = [:]
            for binding in row.includeParameters {
                if case .parameter(let name) = binding.value {
                    if let value = parameters[name] { bound[binding.name] = value }
                } else {
                    bound[binding.name] = binding.value
                }
            }
            var subGroups = groups
            if row.requirementLevel != .mandatory {
                subGroups.append(nextGroup)
                nextGroup += 1
            }
            let sub = expand(
                tree(includedType.rows),
                template: includedType,
                parameters: bound,
                relationship: row.relationshipType ?? relationship,
                groups: subGroups,
                repeatable: repeatable || row.valueMultiplicity.maximum != 1,
                visited: visited.union([included.templateID]),
                nextGroup: &nextGroup
            )
            level.slots += sub.slots
            level.isExtensible = level.isExtensible || sub.isExtensible
            level.isOpen = level.isOpen || sub.isOpen
        }
        return level
    }

    /// The slot an item belongs to: the most specific concept match among the slots whose
    /// value type and relationship match, first in table order on a tie.
    static func bestSlot(for item: AnyContentItem, in slots: [Slot]) -> Int? {
        bestSlots(for: item, in: slots).first
    }

    /// Every slot with the most specific concept match among the slots whose value type and
    /// relationship match, in table order. The validator chooses among several by checking
    /// the item against each (D52).
    static func bestSlots(for item: AnyContentItem, in slots: [Slot]) -> [Int] {
        var best: [Int] = []
        var bestScore = 0
        for (index, slot) in slots.enumerated() where slot.row.valueType == item.valueType {
            if let expected = slot.relationship, let actual = item.relationshipType, expected != actual {
                continue
            }
            let score = conceptScore(item.conceptName, slot.row.conceptName, parameters: slot.parameters)
            if score > bestScore {
                best = [index]
                bestScore = score
            } else if score > 0 && score == bestScore {
                best.append(index)
            }
        }
        return best
    }

    /// 0 = no match, 1 = unconstrained, 2 = context-group member, 3 = the exact code.
    static func conceptScore(
        _ concept: CodedConcept?,
        _ constraint: ConceptNameConstraint,
        parameters: [String: TemplateParameterValue]
    ) -> Int {
        switch constraint {
        case .any, .baselineCID, .fromBaselineContextGroup:
            return 1
        case .exact(let code), .definedTerm(let code):
            return sameCode(concept, code) ? 3 : 0
        case .oneOf(let codes):
            return codes.contains { sameCode(concept, $0) } ? 3 : 0
        case .fromContextGroup(let cid):
            return groupScore(concept, cid: cid)
        case .parameter(let name):
            switch parameters[name] {
            case .code(let code)?, .definedTerm(let code)?:
                return sameCode(concept, code) ? 3 : 0
            case .contextGroup(let cid)?:
                return groupScore(concept, cid: cid)
            case .baselineContextGroup?, .parameter?, .text?, nil:
                return 1
            }
        }
    }

    private static func groupScore(_ concept: CodedConcept?, cid: Int) -> Int {
        guard let group = ContextGroupRegistry.shared.group(forCID: cid) else { return 1 }
        if group.members.contains(where: { sameCode(concept, $0) }) { return 2 }
        return group.isExtensible ? 1 : 0
    }

    /// Codes are the same concept when value and scheme match; Code Meaning is not significant.
    static func sameCode(_ lhs: CodedConcept?, _ rhs: CodedConcept) -> Bool {
        guard let lhs else { return false }
        return lhs.codeValue == rhs.codeValue && lhs.codingSchemeDesignator == rhs.codingSchemeDesignator
    }

    static func expectedConcept(
        _ constraint: ConceptNameConstraint,
        parameters: [String: TemplateParameterValue]
    ) -> CodedConcept? {
        switch constraint {
        case .exact(let code), .definedTerm(let code):
            return code
        case .oneOf(let codes):
            return codes.first
        case .baselineCID(_, let baseline):
            return baseline
        case .parameter(let name):
            switch parameters[name] {
            case .code(let code)?, .definedTerm(let code)?:
                return code
            default:
                return nil
            }
        case .any, .fromContextGroup, .fromBaselineContextGroup:
            return nil
        }
    }

    /// Whether a CODE item's value, or a NUM item's units, satisfy a value constraint.
    /// Constraints that cannot be checked mechanically (free text, baseline groups,
    /// unregistered or extensible groups, unbound parameters) are satisfied.
    static func valueSatisfies(
        _ item: AnyContentItem,
        _ constraint: ValueConstraint,
        parameters: [String: TemplateParameterValue]
    ) -> Bool {
        switch constraint {
        case .units(let inner):
            guard let numeric = item.asNumeric, let units = numeric.measurementUnits else { return true }
            return codeSatisfies(units, inner, parameters: parameters)
        case .numericUnits(let unitCode):
            guard let numeric = item.asNumeric, let units = numeric.measurementUnits else { return true }
            return sameCode(units, unitCode)
        default:
            guard let code = item.asCode?.conceptCode else { return true }
            return codeSatisfies(code, constraint, parameters: parameters)
        }
    }

    private static func codeSatisfies(
        _ code: CodedConcept,
        _ constraint: ValueConstraint,
        parameters: [String: TemplateParameterValue]
    ) -> Bool {
        switch constraint {
        case .exactCode(let expected):
            return sameCode(code, expected)
        case .oneOfCodes(let expected):
            return expected.contains { sameCode(code, $0) }
        case .fromContextGroup(let cid):
            return groupScore(code, cid: cid) > 0
        case .parameter(let name):
            switch parameters[name] {
            case .code(let expected)?:
                return sameCode(code, expected)
            case .contextGroup(let cid)?:
                return groupScore(code, cid: cid) > 0
            default:
                return true
            }
        case .units(let inner):
            return codeSatisfies(code, inner, parameters: parameters)
        case .numericUnits(let expected):
            return sameCode(code, expected)
        case .any, .definedTermCode, .fromBaselineContextGroup, .textPattern, .custom:
            return true
        }
    }
}

// MARK: - Template Detection

/// Detects which template(s) might apply to a set of content items
public struct TemplateDetector: Sendable {
    /// Creates a template detector
    public init() {}
    
    /// Detects potential templates that match the given content
    /// - Parameter contentItems: The content items to analyze
    /// - Returns: Array of potential template identifiers with confidence scores
    public func detectTemplates(_ contentItems: [AnyContentItem]) -> [(template: TemplateIdentifier, confidence: Double)] {
        var results: [(template: TemplateIdentifier, confidence: Double)] = []
        
        for templateType in TemplateRegistry.shared.registeredTemplates {
            if let template = TemplateRegistry.shared.template(for: templateType) {
                let confidence = calculateConfidence(contentItems: contentItems, template: template)
                if confidence > 0.3 { // Threshold for reporting
                    results.append((templateType, confidence))
                }
            }
        }
        
        // Sort by confidence, descending
        return results.sorted { $0.confidence > $1.confidence }
    }
    
    /// Detects the most likely template for the given content
    /// - Parameter contentItems: The content items to analyze
    /// - Returns: The most likely template identifier, or nil if none match
    public func detectTemplate(_ contentItems: [AnyContentItem]) -> TemplateIdentifier? {
        let results = detectTemplates(contentItems)
        return results.first?.template
    }
    
    /// Scores the template's top-level rows (after INCLUDE expansion) against the items.
    private func calculateConfidence(contentItems: [AnyContentItem], template: any SRTemplate.Type) -> Double {
        let level = TemplateMatcher.expand(
            TemplateMatcher.tree(template.rows),
            template: template,
            parameters: [:],
            relationship: nil,
            groups: [],
            repeatable: false,
            visited: [template.identifier.templateID]
        )

        var mandatoryMatched = 0
        var mandatoryTotal = 0
        var optionalMatched = 0
        var optionalTotal = 0

        for (index, slot) in level.slots.enumerated() {
            let hasMatch = contentItems.contains { TemplateMatcher.bestSlot(for: $0, in: level.slots) == index }
            if slot.row.requirementLevel == .mandatory && slot.groups.isEmpty {
                mandatoryTotal += 1
                if hasMatch { mandatoryMatched += 1 }
            } else {
                optionalTotal += 1
                if hasMatch { optionalMatched += 1 }
            }
        }

        // Calculate confidence score
        var confidence = 0.0
        if mandatoryTotal > 0 {
            confidence = Double(mandatoryMatched) / Double(mandatoryTotal) * 0.7
        } else {
            confidence = 0.5 // No mandatory fields means moderate base confidence
        }
        
        if optionalTotal > 0 {
            confidence += Double(optionalMatched) / Double(optionalTotal) * 0.3
        }
        
        return confidence
    }
}
