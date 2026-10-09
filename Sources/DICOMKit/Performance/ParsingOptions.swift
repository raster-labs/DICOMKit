// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (parser limits)
import Foundation

/// Options for controlling DICOM file parsing behavior
public struct ParsingOptions: Sendable {
    /// Parsing mode that determines which elements are parsed
    public enum Mode: Sendable {
        /// Parse all elements including pixel data (default)
        case full
        
        /// Parse metadata only, skip pixel data entirely
        /// Significantly faster for queries and metadata extraction
        case metadataOnly
        
        /// Parse tags up to pixel data, but don't load pixel data value.
        ///
        /// **Warning:** this mode *discards* the pixel bytes — it retains no
        /// offset handle, so pixels cannot be materialised from the parsed
        /// file later. For selective access, parse fully and use
        /// `DICOMFile.pixelData(frame:)`, which decodes exactly one frame.
        case lazyPixelData
    }
    
    /// The parsing mode to use
    public let mode: Mode
    
    /// Stop parsing after encountering the specified tag
    /// Useful for partial file parsing when only specific attributes are needed
    public let stopAfterTag: Tag?
    
    /// Maximum number of elements to parse
    /// Useful for limiting memory usage on very large files
    public let maxElements: Int?
    
    /// Whether to use memory-mapped file access (`.mappedIfSafe`) in
    /// `DICOMFile.read(from url:)`. Pages fault in on demand rather than being
    /// read eagerly. Choose per workload and measure — there is no universal
    /// file-size threshold at which mapping wins.
    public let useMemoryMapping: Bool

    /// Maximum sequence/item nesting depth (default 64)
    ///
    /// Sequence parsing is recursive; without a bound, a crafted file with
    /// deeply nested (undefined-length) sequences causes an uncatchable stack
    /// overflow. Exceeding this depth throws `DICOMError.limitExceeded`.
    /// The DICOM standard has no practical use for nesting anywhere near 64.
    public let maxSequenceDepth: Int

    /// Maximum declared value length in bytes for a single element (optional)
    ///
    /// When set, any element whose defined length exceeds this throws
    /// `DICOMError.limitExceeded` before the value is materialised. Guards
    /// against allocation abuse in constrained environments. `nil` (default)
    /// bounds lengths only by the input size.
    public let maxElementLength: Int?

    /// Maximum total number of elements parsed, including elements nested
    /// inside sequence items (optional)
    ///
    /// Unlike `maxElements` (which bounds only the top-level loop and stops
    /// parsing quietly), exceeding this limit throws
    /// `DICOMError.limitExceeded`. Guards against element-storm inputs.
    public let maxTotalElements: Int?

    /// Maximum number of encapsulated pixel-data fragments (optional)
    ///
    /// Exceeding this throws `DICOMError.limitExceeded`.
    public let maxFragmentCount: Int?

    /// Hard limit on the inflated size of a Deflated Explicit VR Little Endian Data
    /// Set (PS3.5 A.5). Inflation stops and the read fails once the limit would be
    /// exceeded, so a small compressed file cannot expand without bound.
    public let maximumInflatedByteCount: Int

    /// Default inflation limit: 1 GiB.
    public static let defaultMaximumInflatedByteCount = 1 << 30
    
    /// Default parsing options (full parsing)
    public static let `default` = ParsingOptions()
    
    /// Metadata-only parsing options
    public static let metadataOnly = ParsingOptions(mode: .metadataOnly)
    
    /// Lazy pixel data parsing options
    @available(*, deprecated, message: "Discards pixels rather than deferring them; use .metadataOnly, or full parse + DICOMFile.pixelData(frame:) for selective access")
    public static let lazyPixelData = ParsingOptions(mode: .lazyPixelData)

    /// Memory-mapped parsing options for large files (.mappedIfSafe: pages
    /// fault in on demand; do not modify the file while parsed data is alive)
    public static let memoryMapped = ParsingOptions(useMemoryMapping: true)
    
    public init(
        mode: Mode = .full,
        stopAfterTag: Tag? = nil,
        maxElements: Int? = nil,
        useMemoryMapping: Bool = false,
        maxSequenceDepth: Int = 64,
        maxElementLength: Int? = nil,
        maxTotalElements: Int? = nil,
        maxFragmentCount: Int? = nil,
        maximumInflatedByteCount: Int = ParsingOptions.defaultMaximumInflatedByteCount
    ) {
        self.mode = mode
        self.stopAfterTag = stopAfterTag
        self.maxElements = maxElements
        self.useMemoryMapping = useMemoryMapping
        self.maxSequenceDepth = maxSequenceDepth
        self.maxElementLength = maxElementLength
        self.maxTotalElements = maxTotalElements
        self.maxFragmentCount = maxFragmentCount
        self.maximumInflatedByteCount = maximumInflatedByteCount
    }
}
