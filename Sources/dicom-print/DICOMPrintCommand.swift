import ArgumentParser
import DICOMPrintCommandSupport

/// The executable and Workshop share one parser and command implementation.
@main
struct DICOMPrint: AsyncParsableCommand {
    static let configuration = PrintSCUCommand.configuration
}
