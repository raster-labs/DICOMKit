import ArgumentParser
import DICOMPrintCommandSupport

/// The executable and Workshop share one parser and command implementation.
@main
struct DICOMPrintSCP: AsyncParsableCommand {
    static let configuration = PrintSCPCommand.configuration
}
