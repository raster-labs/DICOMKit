/// UCUMUnit - Unified Code for Units of Measure support
///
/// Provides specialized types and common units for UCUM (Unified Code for Units of Measure),
/// the standard for units used in DICOM measurements.
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: UCUM.org - https://ucum.org/
///
/// NEMA-verified: 2026a, checked 2026-09-25 — UCUM is outside NEMA's scope; the check was against every UCUM code used in PS3.16 2026a. Of 50 constants, 31 appear in PS3.16 (24 with the same meaning, 7 where PS3.16 uses the symbol itself as the meaning); 19 do not appear and were not verified. `beatsPerMinute` and `breathsPerMinute` both carry the bare code "/min"; the annotated forms {beats}/min and {breaths}/min would distinguish them.

import Foundation

/// A UCUM unit with associated metadata
///
/// UCUM units provide a standardized way to express measurement units in DICOM.
/// This type provides type-safe access to units with conversion support.
///
/// Example:
/// ```swift
/// let mm = UCUMUnit.millimeter
/// print(mm.concept.description) // "(mm, UCUM, "millimeter")"
///
/// // Convert 25.4 mm to cm
/// if let cm = UCUMUnit.millimeter.convert(25.4, to: .centimeter) {
///     print(cm) // 2.54
/// }
/// ```
public struct UCUMUnit: Sendable, Equatable, Hashable {
    /// The coded concept representation
    public let concept: CodedConcept
    
    /// The unit dimension for conversion purposes
    public let dimension: Dimension
    
    /// Base unit multiplier for conversions (relative to SI base)
    public let baseMultiplier: Double
    
    /// The UCUM code
    public var code: String { concept.codeValue }
    
    /// The print symbol (human-readable form)
    public var symbol: String { concept.codeMeaning }
    
    /// Dimension categories for unit conversion
    public enum Dimension: String, Sendable, Equatable, Hashable {
        /// Length (m)
        case length
        /// Area (m^2)
        case area
        /// Volume (m^3, L)
        case volume
        /// Mass (kg, g)
        case mass
        /// Time (s)
        case time
        /// Temperature (K, Cel)
        case temperature
        /// Angle (rad, deg)
        case angle
        /// Density/concentration
        case density
        /// Ratio/count (dimensionless)
        case ratio
        /// Unknown/other
        case other
    }
    
    /// Creates a UCUM unit from a code and symbol
    /// - Parameters:
    ///   - code: The UCUM code (e.g., "mm", "cm3")
    ///   - symbol: The human-readable symbol/name
    ///   - dimension: The dimension category
    ///   - baseMultiplier: Multiplier relative to SI base unit (default: 1.0)
    public init(code: String, symbol: String, dimension: Dimension = .other, baseMultiplier: Double = 1.0) {
        self.concept = CodedConcept(
            codeValue: code,
            scheme: .UCUM,
            codeMeaning: symbol
        )
        self.dimension = dimension
        self.baseMultiplier = baseMultiplier
    }
    
    /// Creates a UCUM unit from an existing CodedConcept
    /// - Parameter concept: A coded concept using UCUM designator
    /// - Returns: nil if the concept is not a UCUM code
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == CodingSchemeDesignator.UCUM.rawValue else {
            return nil
        }
        self.concept = concept
        self.dimension = .other
        self.baseMultiplier = 1.0
    }
}

// MARK: - CustomStringConvertible

extension UCUMUnit: CustomStringConvertible {
    public var description: String {
        concept.description
    }
}

// MARK: - Unit Conversion

extension UCUMUnit {
    /// Check if this unit is convertible to another unit
    /// - Parameter other: The target unit
    /// - Returns: true if units are in the same dimension
    public func isConvertibleTo(_ other: UCUMUnit) -> Bool {
        dimension == other.dimension && dimension != .other
    }
    
    /// Convert a value from this unit to another unit
    /// - Parameters:
    ///   - value: The value in this unit
    ///   - targetUnit: The target unit
    /// - Returns: The converted value, or nil if conversion is not possible
    public func convert(_ value: Double, to targetUnit: UCUMUnit) -> Double? {
        guard isConvertibleTo(targetUnit) else { return nil }
        
        // Handle temperature specially
        if dimension == .temperature {
            return convertTemperature(value, to: targetUnit)
        }
        
        // Standard conversion: value * (this.multiplier / target.multiplier)
        return value * (baseMultiplier / targetUnit.baseMultiplier)
    }
    
    /// Convert temperature values between Celsius and Kelvin
    private func convertTemperature(_ value: Double, to targetUnit: UCUMUnit) -> Double? {
        let toKelvin: Double
        
        // Convert to Kelvin first
        switch code {
        case "Cel":
            toKelvin = value + 273.15
        case "K":
            toKelvin = value
        case "[degF]":
            toKelvin = (value - 32) * 5/9 + 273.15
        default:
            return nil
        }
        
        // Convert from Kelvin to target
        switch targetUnit.code {
        case "Cel":
            return toKelvin - 273.15
        case "K":
            return toKelvin
        case "[degF]":
            return (toKelvin - 273.15) * 9/5 + 32
        default:
            return nil
        }
    }
}

// MARK: - Length Units

extension UCUMUnit {
    /// Meter (m) - SI base unit of length
    public static let meter = UCUMUnit(code: "m", symbol: "meter", dimension: .length, baseMultiplier: 1.0)
    
    /// Centimeter (cm)
    public static let centimeter = UCUMUnit(code: "cm", symbol: "centimeter", dimension: .length, baseMultiplier: 0.01)
    
    /// Millimeter (mm)
    public static let millimeter = UCUMUnit(code: "mm", symbol: "millimeter", dimension: .length, baseMultiplier: 0.001)
    
    /// Micrometer (um)
    public static let micrometer = UCUMUnit(code: "um", symbol: "micrometer", dimension: .length, baseMultiplier: 0.000001)
    
    /// Nanometer (nm)
    public static let nanometer = UCUMUnit(code: "nm", symbol: "nanometer", dimension: .length, baseMultiplier: 0.000000001)
    
    /// Inch ([in_i])
    public static let inch = UCUMUnit(code: "[in_i]", symbol: "inch", dimension: .length, baseMultiplier: 0.0254)
    
    /// Foot ([ft_i])
    public static let foot = UCUMUnit(code: "[ft_i]", symbol: "foot", dimension: .length, baseMultiplier: 0.3048)
}

// MARK: - Area Units

extension UCUMUnit {
    /// Square meter (m2)
    public static let squareMeter = UCUMUnit(code: "m2", symbol: "square meter", dimension: .area, baseMultiplier: 1.0)
    
    /// Square centimeter (cm2)
    public static let squareCentimeter = UCUMUnit(code: "cm2", symbol: "square centimeter", dimension: .area, baseMultiplier: 0.0001)
    
    /// Square millimeter (mm2)
    public static let squareMillimeter = UCUMUnit(code: "mm2", symbol: "square millimeter", dimension: .area, baseMultiplier: 0.000001)
}

// MARK: - Volume Units

extension UCUMUnit {
    /// Cubic meter (m3)
    public static let cubicMeter = UCUMUnit(code: "m3", symbol: "cubic meter", dimension: .volume, baseMultiplier: 1.0)
    
    /// Cubic centimeter / milliliter (cm3)
    public static let cubicCentimeter = UCUMUnit(code: "cm3", symbol: "cubic centimeter", dimension: .volume, baseMultiplier: 0.000001)
    
    /// Cubic millimeter (mm3)
    public static let cubicMillimeter = UCUMUnit(code: "mm3", symbol: "cubic millimeter", dimension: .volume, baseMultiplier: 0.000000001)
    
    /// Liter (L)
    public static let liter = UCUMUnit(code: "L", symbol: "liter", dimension: .volume, baseMultiplier: 0.001)
    
    /// Milliliter (mL)
    public static let milliliter = UCUMUnit(code: "mL", symbol: "milliliter", dimension: .volume, baseMultiplier: 0.000001)
    
    /// Microliter (uL)
    public static let microliter = UCUMUnit(code: "uL", symbol: "microliter", dimension: .volume, baseMultiplier: 0.000000001)
}

// MARK: - Mass Units

extension UCUMUnit {
    /// Kilogram (kg) - SI base unit of mass
    public static let kilogram = UCUMUnit(code: "kg", symbol: "kilogram", dimension: .mass, baseMultiplier: 1.0)
    
    /// Gram (g)
    public static let gram = UCUMUnit(code: "g", symbol: "gram", dimension: .mass, baseMultiplier: 0.001)
    
    /// Milligram (mg)
    public static let milligram = UCUMUnit(code: "mg", symbol: "milligram", dimension: .mass, baseMultiplier: 0.000001)
    
    /// Microgram (ug)
    public static let microgram = UCUMUnit(code: "ug", symbol: "microgram", dimension: .mass, baseMultiplier: 0.000000001)
    
    /// Pound ([lb_av])
    public static let pound = UCUMUnit(code: "[lb_av]", symbol: "pound", dimension: .mass, baseMultiplier: 0.45359237)
}

// MARK: - Time Units

extension UCUMUnit {
    /// Second (s) - SI base unit of time
    public static let second = UCUMUnit(code: "s", symbol: "second", dimension: .time, baseMultiplier: 1.0)
    
    /// Millisecond (ms)
    public static let millisecond = UCUMUnit(code: "ms", symbol: "millisecond", dimension: .time, baseMultiplier: 0.001)
    
    /// Minute (min)
    public static let minute = UCUMUnit(code: "min", symbol: "minute", dimension: .time, baseMultiplier: 60.0)
    
    /// Hour (h)
    public static let hour = UCUMUnit(code: "h", symbol: "hour", dimension: .time, baseMultiplier: 3600.0)
    
    /// Day (d)
    public static let day = UCUMUnit(code: "d", symbol: "day", dimension: .time, baseMultiplier: 86400.0)
    
    /// Week (wk)
    public static let week = UCUMUnit(code: "wk", symbol: "week", dimension: .time, baseMultiplier: 604800.0)
    
    /// Month (mo)
    public static let month = UCUMUnit(code: "mo", symbol: "month", dimension: .time, baseMultiplier: 2629746.0) // Average month
    
    /// Year (a)
    public static let year = UCUMUnit(code: "a", symbol: "year", dimension: .time, baseMultiplier: 31556952.0) // Average year
}

// MARK: - Temperature Units

extension UCUMUnit {
    /// Kelvin (K) - SI base unit of temperature
    public static let kelvin = UCUMUnit(code: "K", symbol: "Kelvin", dimension: .temperature, baseMultiplier: 1.0)
    
    /// Degree Celsius (Cel)
    public static let celsius = UCUMUnit(code: "Cel", symbol: "degree Celsius", dimension: .temperature, baseMultiplier: 1.0)
    
    /// Degree Fahrenheit ([degF])
    public static let fahrenheit = UCUMUnit(code: "[degF]", symbol: "degree Fahrenheit", dimension: .temperature, baseMultiplier: 1.0)
}

// MARK: - Angle Units

extension UCUMUnit {
    /// Radian (rad) - SI unit of angle
    public static let radian = UCUMUnit(code: "rad", symbol: "radian", dimension: .angle, baseMultiplier: 1.0)
    
    /// Degree (deg)
    public static let degree = UCUMUnit(code: "deg", symbol: "degree", dimension: .angle, baseMultiplier: Double.pi / 180.0)
}

// MARK: - Ratio/Count Units

extension UCUMUnit {
    /// No units / unity (1)
    public static let unity = UCUMUnit(code: "1", symbol: "no units", dimension: .ratio, baseMultiplier: 1.0)
    
    /// Percent (%)
    public static let percent = UCUMUnit(code: "%", symbol: "percent", dimension: .ratio, baseMultiplier: 0.01)
    
    /// Per thousand ([ppth])
    public static let perThousand = UCUMUnit(code: "[ppth]", symbol: "per thousand", dimension: .ratio, baseMultiplier: 0.001)
    
    /// Parts per million ([ppm])
    public static let partsPerMillion = UCUMUnit(code: "[ppm]", symbol: "parts per million", dimension: .ratio, baseMultiplier: 0.000001)
}

// MARK: - Medical/Imaging Specific Units

extension UCUMUnit {
    /// Hounsfield unit ([hnsf'U])
    public static let hounsfieldUnit = UCUMUnit(code: "[hnsf'U]", symbol: "Hounsfield unit", dimension: .density, baseMultiplier: 1.0)
    
    /// Standardized Uptake Value (SUV) (1)
    public static let suvUnit = UCUMUnit(code: "{SUVbw}", symbol: "SUV body weight", dimension: .ratio, baseMultiplier: 1.0)
    
    /// Becquerel (Bq)
    public static let becquerel = UCUMUnit(code: "Bq", symbol: "Becquerel", dimension: .other, baseMultiplier: 1.0)
    
    /// Millicurie (mCi)
    public static let millicurie = UCUMUnit(code: "mCi", symbol: "millicurie", dimension: .other, baseMultiplier: 3.7e7)
    
    /// Gray (Gy) - radiation absorbed dose
    public static let gray = UCUMUnit(code: "Gy", symbol: "Gray", dimension: .other, baseMultiplier: 1.0)
    
    /// Sievert (Sv) - radiation equivalent dose
    public static let sievert = UCUMUnit(code: "Sv", symbol: "Sievert", dimension: .other, baseMultiplier: 1.0)
    
    /// Counts per second (counts/s)
    public static let countsPerSecond = UCUMUnit(code: "{counts}/s", symbol: "counts per second", dimension: .other, baseMultiplier: 1.0)
    
    /// Beats per minute (/min)
    public static let beatsPerMinute = UCUMUnit(code: "/min", symbol: "beats per minute", dimension: .other, baseMultiplier: 1.0)
    
    /// Breaths per minute (/min)
    public static let breathsPerMinute = UCUMUnit(code: "/min", symbol: "breaths per minute", dimension: .other, baseMultiplier: 1.0)
}

// MARK: - Pressure Units

extension UCUMUnit {
    /// Pascal (Pa)
    public static let pascal = UCUMUnit(code: "Pa", symbol: "Pascal", dimension: .other, baseMultiplier: 1.0)
    
    /// Millimeter of mercury (mm[Hg])
    public static let mmHg = UCUMUnit(code: "mm[Hg]", symbol: "millimeter of mercury", dimension: .other, baseMultiplier: 133.322)
    
    /// Kilopascal (kPa)
    public static let kilopascal = UCUMUnit(code: "kPa", symbol: "kilopascal", dimension: .other, baseMultiplier: 1000.0)
}

// MARK: - Well-Known Units Registry

extension UCUMUnit {
    /// Get a well-known unit by its UCUM code
    /// - Parameter code: The UCUM code (e.g., "mm", "cm3")
    /// - Returns: The UCUMUnit if known, nil otherwise
    public static func wellKnown(code: String) -> UCUMUnit? {
        wellKnownUnits[code]
    }
    
    /// Registry of well-known units by code
    private static let wellKnownUnits: [String: UCUMUnit] = {
        var registry: [String: UCUMUnit] = [:]
        let allUnits: [UCUMUnit] = [
            // Length
            .meter, .centimeter, .millimeter, .micrometer, .nanometer, .inch, .foot,
            // Area
            .squareMeter, .squareCentimeter, .squareMillimeter,
            // Volume
            .cubicMeter, .cubicCentimeter, .cubicMillimeter, .liter, .milliliter, .microliter,
            // Mass
            .kilogram, .gram, .milligram, .microgram, .pound,
            // Time
            .second, .millisecond, .minute, .hour, .day, .week, .month, .year,
            // Temperature
            .kelvin, .celsius, .fahrenheit,
            // Angle
            .radian, .degree,
            // Ratio
            .unity, .percent, .perThousand, .partsPerMillion,
            // Medical
            .hounsfieldUnit, .suvUnit, .becquerel, .gray, .sievert,
            .countsPerSecond, .beatsPerMinute,
            // Pressure
            .pascal, .mmHg, .kilopascal
        ]
        
        for unit in allUnits {
            registry[unit.code] = unit
        }
        
        return registry
    }()
}

// MARK: - CodedConcept Convenience

extension CodedConcept {
    /// Create a CodedConcept from a UCUMUnit
    /// - Parameter unit: The UCUM unit
    /// - Returns: A coded concept with UCUM designator
    public init(unit: UCUMUnit) {
        self = unit.concept
    }
    
    /// Attempt to convert this coded concept to a UCUMUnit
    /// - Returns: A UCUMUnit if this is a UCUM concept, nil otherwise
    public var asUCUM: UCUMUnit? {
        UCUMUnit(concept: self)
    }
    
    /// Returns whether this concept uses UCUM coding scheme
    public var isUCUM: Bool {
        codingSchemeDesignator == CodingSchemeDesignator.UCUM.rawValue
    }
}
