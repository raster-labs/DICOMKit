import Foundation

/// Window settings for grayscale visualization
///
/// Defines the Window Center (Level) and Window Width parameters used to
/// map pixel values to display values.
/// Reference: DICOM PS3.3 C.11.2.1.2 - Window Center and Window Width
public struct WindowSettings: Sendable, Equatable, Codable {
    /// The center of the window (also called Level)
    ///
    /// This is the pixel value that maps to the middle of the output range.
    /// Reference: PS3.3 C.11.2.1.2.1 - Window Center
    public let center: Double
    
    /// The width of the window
    ///
    /// Determines the range of pixel values that are mapped to the output range.
    /// Reference: PS3.3 C.11.2.1.2.1 - Window Width
    public let width: Double
    
    /// Optional explanation of what this window represents
    /// e.g., "BONE", "SOFT TISSUE", "LUNG"
    /// Reference: PS3.3 C.11.2.1.2 - Window Center & Width Explanation
    public let explanation: String?
    
    /// The VOI LUT function to use
    /// Reference: PS3.3 C.11.2.1.3 - VOI LUT Function
    public let function: VOILUTFunction
    
    /// Creates a new window settings instance
    /// - Parameters:
    ///   - center: Window center value
    ///   - width: Window width value
    ///   - explanation: Optional explanation
    ///   - function: VOI LUT function (default is linear)
    public init(
        center: Double,
        width: Double,
        explanation: String? = nil,
        function: VOILUTFunction = .linear
    ) {
        self.center = center
        self.width = Self.admissibleWidth(width, for: function)
        self.explanation = explanation
        self.function = function
    }

    /// The width a window of this function is applied with.
    ///
    /// PS3.3 C.11.2.1.2.1: for LINEAR, "Window Width (0028,1051) shall always be
    /// greater than or equal to 1", so smaller widths are raised to 1. C.11.2.1.3.1
    /// (SIGMOID) and C.11.2.1.3.2 (LINEAR_EXACT) only require "greater than 0", so a
    /// width such as 0.25 is kept (D64). A width the standard forbids for every
    /// function (zero, negative, NaN) is applied as 1.
    ///
    /// NEMA-verified: 2026a, checked 2026-09-30 — the three width rules match PS3.3 2026a
    /// C.11.2.1.2.1, C.11.2.1.3.1 and C.11.2.1.3.2 (Scripts/diff_renderkit.py, D64).
    public static func admissibleWidth(_ width: Double, for function: VOILUTFunction) -> Double {
        switch function {
        case .linear:
            return width >= 1.0 ? width : 1.0
        case .linearExact, .sigmoid:
            return width > 0 && width.isFinite ? width : 1.0
        }
    }
    
    /// The minimum input value that maps to minimum output
    public var minValue: Double {
        center - width / 2.0
    }
    
    /// The maximum input value that maps to maximum output
    public var maxValue: Double {
        center + width / 2.0
    }
    
    /// Applies the window transform to a pixel value
    ///
    /// Implements the VOI LUT transformation as defined in PS3.3 C.11.2.1.2.
    /// - Parameter pixelValue: The input pixel value
    /// - Returns: Normalized value in range [0.0, 1.0]
    public func apply(to pixelValue: Double) -> Double {
        switch function {
        case .linear:
            return applyLinear(to: pixelValue)
        case .linearExact:
            return applyLinearExact(to: pixelValue)
        case .sigmoid:
            return applySigmoid(to: pixelValue)
        }
    }
    
    /// Applies linear window transform
    /// Reference: PS3.3 C.11.2.1.2.1
    private func applyLinear(to pixelValue: Double) -> Double {
        if pixelValue <= center - 0.5 - (width - 1.0) / 2.0 {
            return 0.0
        } else if pixelValue > center - 0.5 + (width - 1.0) / 2.0 {
            return 1.0
        } else {
            return ((pixelValue - (center - 0.5)) / (width - 1.0)) + 0.5
        }
    }
    
    /// Applies linear exact window transform
    /// Reference: PS3.3 C.11.2.1.2.1
    private func applyLinearExact(to pixelValue: Double) -> Double {
        if pixelValue <= center - width / 2.0 {
            return 0.0
        } else if pixelValue > center + width / 2.0 {
            return 1.0
        } else {
            return (pixelValue - center) / width + 0.5
        }
    }
    
    /// Applies sigmoid window transform
    /// Reference: PS3.3 C.11.2.1.3
    private func applySigmoid(to pixelValue: Double) -> Double {
        let exponent = -4.0 * (pixelValue - center) / width
        return 1.0 / (1.0 + exp(exponent))
    }
}

/// VOI LUT Function types
///
/// Reference: DICOM PS3.3 C.11.2.1.3 - VOI LUT Function
///
/// NEMA-verified: 2026a, checked 2026-09-24 — text-diffed: LINEAR, LINEAR_EXACT, SIGMOID match the
/// (0028,1056) Defined Terms in PS3.3 2026a Tables C.11-2b and C.7.6.16-11 exactly.
public enum VOILUTFunction: String, Sendable, Equatable, Codable {
    /// Linear transformation (default)
    /// Reference: PS3.3 C.11.2.1.2.1
    case linear = "LINEAR"
    
    /// Linear exact transformation
    /// Reference: PS3.3 C.11.2.1.2.1
    case linearExact = "LINEAR_EXACT"
    
    /// Sigmoid transformation
    /// Reference: PS3.3 C.11.2.1.3
    case sigmoid = "SIGMOID"
    
    /// Creates a VOILUTFunction from a DICOM string value
    /// - Parameter string: The DICOM VOI LUT Function string
    /// - Returns: VOILUTFunction if valid, defaults to linear
    public static func parse(_ string: String?) -> VOILUTFunction {
        guard let string = string else { return .linear }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return VOILUTFunction(rawValue: trimmed) ?? .linear
    }
}
