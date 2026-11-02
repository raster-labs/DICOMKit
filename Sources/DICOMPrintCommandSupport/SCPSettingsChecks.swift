import Foundation
import ArgumentParser
import DICOMNetwork
import DICOMPrintKit

/// Validate before converting numeric options to wire integers or timer values.
/// These are command/resource constraints; the shared print core owns rendering
/// and DICOM request validation.
enum SCPSettingsChecks {
    static func validSleepInterval(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value < Double(UInt64.max) / 1_000_000_000
    }

    static func validate(_ settings: PrintSCPSettings, transport: Bool) throws {
        if transport {
            guard (0...65535).contains(settings.port) else { throw ValidationError("--port must be between 0 and 65535") }
            guard settings.maxConcurrentAssociations > 0 else { throw ValidationError("--max-associations must be 1 or greater") }
            guard settings.associationIdleTimeoutSeconds == 0 || validSleepInterval(settings.associationIdleTimeoutSeconds) else {
                throw ValidationError("--idle-timeout must be zero or a finite positive interval")
            }
            guard settings.maxPDUSize >= 0, UInt64(settings.maxPDUSize) <= UInt64(UInt32.max) else {
                throw ValidationError("--max-pdu must be between 0 and 4294967295")
            }
            guard (0...65535).contains(settings.annotationBoxesPerFilm) else {
                throw ValidationError("--annotation-boxes-per-film must be between 0 and 65535")
            }
            guard settings.maxImageBoxesPerFilm > 0 else { throw ValidationError("--max-image-boxes must be 1 or greater") }
            guard (1...65535).contains(settings.maxImageBoxPixelDimension) else {
                throw ValidationError("--max-image-dimension must be between 1 and 65535")
            }
            _ = try AETitle(settings.aeTitle)
        }
        guard settings.dpi.isFinite, settings.dpi > 0 else { throw ValidationError("--dpi must be finite and greater than zero") }
        guard settings.marginMillimeters.isFinite, settings.marginMillimeters >= 0 else {
            throw ValidationError("--margin-mm must be finite and zero or greater")
        }
        guard settings.cellSpacingMillimeters.isFinite, settings.cellSpacingMillimeters >= 0 else {
            throw ValidationError("--cell-spacing-mm must be finite and zero or greater")
        }
        guard settings.maximumPixelDimension > 0 else { throw ValidationError("--max-pixels must be 1 or greater") }
    }
}
