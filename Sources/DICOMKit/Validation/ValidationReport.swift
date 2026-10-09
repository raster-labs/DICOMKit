// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (report formatting)
import Foundation

/// Output format for a ``ValidationReport``.
///
/// Lives in the library (not the CLI) so DICOMStudio and the `dicom-validate`
/// tool render reports from the same type. The CLI adds the
/// `ExpressibleByArgument` conformance in its own module.
public enum ValidationOutputFormat: String, Sendable {
    case text
    case json
}

/// Validation report generator
public struct ValidationReport {
    let results: [ValidationResult]
    let detailed: Bool
    let strict: Bool
    
    public init(results: [ValidationResult], detailed: Bool, strict: Bool) {
        self.results = results
        self.detailed = detailed
        self.strict = strict
    }
    
    public func render(format: ValidationOutputFormat) throws -> String {
        switch format {
        case .text:
            return renderText()
        case .json:
            return try renderJSON()
        }
    }
    
    public func exitCode() -> Int32 {
        let hasErrors = results.contains { !$0.errors.isEmpty }
        let hasWarnings = results.contains { !$0.warnings.isEmpty }
        
        if hasErrors {
            return 1
        }
        
        if strict && hasWarnings {
            return 2
        }
        
        return 0
    }
    
    private func renderText() -> String {
        var output = ""
        
        if results.count == 1 {
            // Single file report
            let result = results[0]
            output += "DICOM Validation Report\n"
            output += "=======================\n\n"
            output += "File: \(result.filePath)\n"
            output += "Status: \(result.isValid ? "✓ VALID" : "✗ INVALID")\n\n"
            
            if !result.errors.isEmpty {
                output += "Errors (\(result.errors.count)):\n"
                output += renderIssues(result.errors)
                output += "\n"
            }
            
            if !result.warnings.isEmpty {
                output += "Warnings (\(result.warnings.count)):\n"
                output += renderIssues(result.warnings)
                output += "\n"
            }
            
            if result.errors.isEmpty && result.warnings.isEmpty {
                output += "No issues found.\n"
            }
        } else {
            // Multiple files summary
            let totalFiles = results.count
            let validFiles = results.filter { $0.isValid }.count
            let invalidFiles = totalFiles - validFiles
            let totalErrors = results.reduce(0) { $0 + $1.errors.count }
            let totalWarnings = results.reduce(0) { $0 + $1.warnings.count }
            
            output += "DICOM Validation Summary\n"
            output += "========================\n\n"
            output += "Total files: \(totalFiles)\n"
            output += "Valid: \(validFiles)\n"
            output += "Invalid: \(invalidFiles)\n"
            output += "Total errors: \(totalErrors)\n"
            output += "Total warnings: \(totalWarnings)\n\n"
            
            if detailed {
                output += "Detailed Results:\n"
                output += "-----------------\n\n"
                
                for result in results {
                    let status = result.isValid ? "✓" : "✗"
                    output += "\(status) \(result.filePath)\n"
                    
                    if !result.errors.isEmpty {
                        output += "  Errors (\(result.errors.count)):\n"
                        for error in result.errors {
                            output += "    • \(error.message)"
                            if let tag = error.tagString {
                                output += " [\(tag)]"
                            }
                            output += "\n"
                        }
                    }
                    
                    if !result.warnings.isEmpty {
                        output += "  Warnings (\(result.warnings.count)):\n"
                        for warning in result.warnings {
                            output += "    • \(warning.message)"
                            if let tag = warning.tagString {
                                output += " [\(tag)]"
                            }
                            output += "\n"
                        }
                    }
                    
                    output += "\n"
                }
            } else {
                // Show only invalid files
                let invalidResults = results.filter { !$0.isValid }
                if !invalidResults.isEmpty {
                    output += "Invalid Files:\n"
                    output += "--------------\n"
                    for result in invalidResults {
                        output += "✗ \(result.filePath) (\(result.errors.count) errors, \(result.warnings.count) warnings)\n"
                    }
                }
            }
        }
        
        return output
    }
    
    private func renderIssues(_ issues: [ValidationIssue]) -> String {
        var output = ""
        for issue in issues {
            output += "  • \(issue.message)"
            if let tag = issue.tagString {
                output += " [\(tag)]"
            }
            output += "\n"
        }
        return output
    }
    
    private func renderJSON() throws -> String {
        let jsonReport = JSONReport(
            totalFiles: results.count,
            validFiles: results.filter { $0.isValid }.count,
            invalidFiles: results.filter { !$0.isValid }.count,
            totalErrors: results.reduce(0) { $0 + $1.errors.count },
            totalWarnings: results.reduce(0) { $0 + $1.warnings.count },
            files: results.map { result in
                JSONFileResult(
                    filePath: result.filePath,
                    isValid: result.isValid,
                    errorCount: result.errors.count,
                    warningCount: result.warnings.count,
                    errors: result.errors.map { JSONIssue(from: $0) },
                    warnings: result.warnings.map { JSONIssue(from: $0) }
                )
            }
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonReport)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct JSONReport: Codable {
    let totalFiles: Int
    let validFiles: Int
    let invalidFiles: Int
    let totalErrors: Int
    let totalWarnings: Int
    let files: [JSONFileResult]
}

struct JSONFileResult: Codable {
    let filePath: String
    let isValid: Bool
    let errorCount: Int
    let warningCount: Int
    let errors: [JSONIssue]
    let warnings: [JSONIssue]
}

struct JSONIssue: Codable {
    let message: String
    let tag: String?
    
    init(from issue: ValidationIssue) {
        self.message = issue.message
        self.tag = issue.tagString
    }
}
