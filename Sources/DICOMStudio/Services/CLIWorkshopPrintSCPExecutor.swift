import Foundation
import DICOMPrintCommandSupport

/// In-process Workshop route; the same parser and implementation as the CLI.
public enum CLIWorkshopPrintSCPExecutor {
    public static func validate(arguments: [String]) throws {
        try PrintSCPCommand.validate(arguments: arguments)
    }

    public static func execute(arguments: [String], context: PrintCommandContext) async throws {
        // A caller must never install process SIGINT handling in the app.
        let appContext = PrintCommandContext(
            printersURL: context.printersURL, defaultSCPConfigURL: context.defaultSCPConfigURL,
            output: context.output, diagnostic: context.diagnostic,
            openFile: context.openFile, handlesProcessSignals: false,
            listenerState: context.listenerState)
        try await PrintSCPCommand.execute(arguments: arguments, context: appContext)
    }
}
