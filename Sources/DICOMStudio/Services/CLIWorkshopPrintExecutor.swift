import DICOMPrintCommandSupport

/// Executes an immutable, parser-validated argument snapshot using the exact
/// command implementation used by dicom-print. Security scope and task ownership
/// belong to the caller and remain active for the whole awaited operation.
public enum CLIWorkshopPrintExecutor {
    public static func validate(arguments: [String]) throws {
        try PrintSCUCommand.validate(arguments: arguments)
    }

    public static func execute(arguments: [String], context: PrintCommandContext) async throws {
        try await PrintSCUCommand.execute(arguments: arguments, context: context)
    }
}
