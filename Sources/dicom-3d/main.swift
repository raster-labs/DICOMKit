// NEMA-verified: 2026a, checked 2026-10-01 — 54 options of 11 subcommands: plane names (axial/sagittal/coronal) per the LPS axes of PS3.3 2026a C.7.6.2.1.1; --window-center/--window-width are the C.11.2.1.2.1 LINEAR window (width >= 1, Table C.11-2b); --format dcm writes a derived series (C.7.6.1.1.2, CID 7203 113072); inspect labels are PS3.6 2026a Table 6-1 names (Patient's Name, Patient ID, Modality, Study Instance UID, Series Description, SOP Instance UID); the JP3D SOP Class 1.2.826.0.1.3680043.10.511.10 is private (not in PS3.6 Table A-1); encode-volume orders slices along the normal before encoding; mpr --oblique-normal/--oblique-point are LPS mm (C.7.6.2.1.1, P-3D-OBLIQUE); --interpolation cubic deprecated → linear, orthogonal planes voxel-aligned (P-3D-INTERPOLATION); volume hidden, exit 1 (P-3D-VOLUME)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOM3D: ParsableCommand {
    static let deferredMessage =
        "Error: dicom-3d is deferred in this release pending SwiftJ2K 12.2.0 (SwiftJ2K3D volumetric module qualification)."

    static let configuration = CommandConfiguration(
        commandName: "dicom-3d",
        abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] 3D reconstruction, MPR, and JP3D volumetric encoding from DICOM series",
        discussion: """
            DEFERRED: `dicom-3d` is deferred in this release pending `SwiftJ2K` 12.2.0
            (`SwiftJ2K3D` volumetric module qualification). All operational subcommands
            currently exit with status 1.

            Perform 3D volume reconstruction, MPR, projection techniques, and JP3D
            volumetric encode/decode from multi-slice DICOM series.

            Examples:
              # Generate axial, sagittal, coronal MPR
              dicom-3d mpr series/*.dcm --output mpr/ --planes axial,sagittal,coronal

              # Oblique plane through a point (LPS mm), as a derived DICOM image
              dicom-3d mpr series/*.dcm --output obl/ --planes oblique \\
                --oblique-normal 0,1,1 --oblique-point 0,-20,35 --format dcm

              # Maximum Intensity Projection
              dicom-3d mip series/*.dcm --output mip.png --thickness 20

              # 3D surface rendering
              dicom-3d surface series/*.dcm --threshold 200 --output surface.stl

              # Encode a slice series as a JP3D volume document
              dicom-3d encode-volume series/*.dcm --output volume.jp3d.dcm
              dicom-3d encode-volume ./series/ --output volume.jp3d.dcm --mode lossless-htj2k

              # Decode a JP3D document back to individual DICOM slices
              dicom-3d decode-volume volume.jp3d.dcm --output ./decoded/

              # Inspect JP3D document metadata (no decode)
              dicom-3d inspect volume.jp3d.dcm
              dicom-3d inspect volume.jp3d.dcm --json
            """,
        version: "1.5.0",
        subcommands: [
            MPRCommand.self,
            MIPCommand.self,
            MinIPCommand.self,
            AverageCommand.self,
            SurfaceCommand.self,
            VolumeCommand.self,
            ExportCommand.self,
            EncodeVolumeCommand.self,
            DecodeVolumeCommand.self,
            InspectCommand.self,
            BackendsCommand.self
        ]
    )
}

// MARK: - Shared option checks

/// PS3.3 2026a C.11.2.1.2.1: for the LINEAR function (used when VOI LUT Function is
/// absent) "Window Width (0028,1051) shall always be greater than or equal to 1".
func validateWindow(center: Double?, width: Double?) throws {
    if let width, !(width >= 1) {
        throw ValidationError("--window-width must be >= 1 (PS3.3 C.11.2.1.2.1); got \(width)")
    }
    if (center == nil) != (width == nil) {
        throw ValidationError("--window-center and --window-width must be given together")
    }
}

/// MONOCHROME1: "The minimum sample value is intended to be displayed as white"
/// (PS3.3 2026a C.7.6.3.1.2).
func isMonochrome1(_ volume: VolumeData) -> Bool {
    volume.photometricInterpretation.uppercased() == "MONOCHROME1"
}

/// Projection directions (a computed value: main.swift globals are not initialised under XCTest).
func projectionDirections() -> [String] { PatientPlane.allCases.map(\.rawValue) }

func projectionType(_ name: String) -> ProjectionType {
    switch name.lowercased() {
    case "sagittal": return .sagittal
    case "coronal": return .coronal
    default: return .axial
    }
}

func failDeferred3D(_ subcommand: String) throws -> Never {
    FileHandle.standardError.write(Data(("\(DICOM3D.deferredMessage) (subcommand: \(subcommand))\n").utf8))
    throw ExitCode.failure
}

// MARK: - MPR Command

struct MPRCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mpr",
        abstract: "Generate Multi-Planar Reformation (MPR) images"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output directory or file path")
    var output: String
    
    @Option(name: .long, help: "Planes to generate: axial, sagittal, coronal (patient planes, PS3.3 C.7.6.2.1.1), oblique (needs --oblique-normal)")
    var planes: String = "axial,sagittal,coronal"

    @Option(name: .long, help: ArgumentHelp(
        "Normal of the oblique plane as x,y,z in the patient (LPS) system: x to patient left, y to posterior, z to head (PS3.3 C.7.6.2.1.1); need not be unit length",
        valueName: "x,y,z"))
    var obliqueNormal: String?

    @Option(name: .long, help: ArgumentHelp(
        "A point on the oblique plane as x,y,z in mm (LPS); default: the centre of the volume",
        valueName: "x,y,z"))
    var obliquePoint: String?
    
    @Option(name: .long, help: "Output format: png, dcm (derived DICOM series, Image Type DERIVED\\SECONDARY)")
    var format: OutputFormat = .png
    
    @Option(name: .long, help: "Slice thickness in mm (planes averaged into slabs of this thickness)")
    var thickness: Double?
    
    @Option(name: .long, help: "Interpolation for oblique planes: nearest, linear (trilinear). cubic is deprecated and uses linear. Axial/sagittal/coronal planes are cut along the voxel grid and are not resampled")
    var interpolation: InterpolationMethod = .linear
    
    @Option(name: .long, help: "Window Center for display (Modality LUT output units, e.g. HU)")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window Width for display (>= 1, LINEAR function, PS3.3 C.11.2.1.2.1)")
    var windowWidth: Double?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
        let wantsOblique = planes.split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "oblique" }
        if wantsOblique {
            guard let normalText = obliqueNormal else {
                throw ValidationError("--planes oblique needs --oblique-normal x,y,z (LPS)")
            }
            guard let normal = Point3D.parse(normalText) else {
                throw ValidationError("--oblique-normal must be x,y,z (three numbers); got \(normalText)")
            }
            guard normal.length > 1e-9 else {
                throw ValidationError("--oblique-normal must not be the zero vector")
            }
            if let pointText = obliquePoint, Point3D.parse(pointText) == nil {
                throw ValidationError("--oblique-point must be x,y,z in mm (three numbers); got \(pointText)")
            }
        } else if obliqueNormal != nil || obliquePoint != nil {
            throw ValidationError("--oblique-normal / --oblique-point need --planes to include oblique")
        }
        
        for path in inputPaths {
            guard FileManager.default.fileExists(atPath: path) else {
                throw ValidationError("File not found: \(path)")
            }
        }
        
        let validPlanes = ["axial", "sagittal", "coronal", "oblique"]
        let requestedPlanes = planes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for plane in requestedPlanes {
            guard validPlanes.contains(plane) else {
                throw ValidationError("Invalid plane: \(plane). Must be one of: \(validPlanes.joined(separator: ", "))")
            }
        }
        if let thickness, !(thickness > 0) {
            throw ValidationError("--thickness must be > 0 mm")
        }
        try validateWindow(center: windowCenter, width: windowWidth)
    }
    
    mutating func run() throws {
        try failDeferred3D("mpr")
    }

    /// Centre of the volume in patient (LPS) coordinates: the default --oblique-point.
    static func centre(of volume: VolumeData) -> Point3D {
        volume.physicalCoordinates(x: Double(volume.dimensions.width - 1) / 2,
                                   y: Double(volume.dimensions.height - 1) / 2,
                                   z: Double(volume.dimensions.depth - 1) / 2)
    }
}

// MARK: - MIP Command

struct MIPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mip",
        abstract: "Generate Maximum Intensity Projection (MIP)"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .long, help: "Projection direction: axial, sagittal, coronal (patient planes, PS3.3 C.7.6.2.1.1)")
    var direction: String = "axial"
    
    @Option(name: .long, help: "Slab thickness in mm (0 = full volume)")
    var thickness: Double = 0
    
    @Option(name: .long, help: "Window Center for display (Modality LUT output units, e.g. HU)")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window Width for display (>= 1, LINEAR function, PS3.3 C.11.2.1.2.1)")
    var windowWidth: Double?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
        
        guard projectionDirections().contains(direction.lowercased()) else {
            throw ValidationError("Invalid direction: \(direction). Must be one of: \(projectionDirections().joined(separator: ", "))")
        }
        try validateWindow(center: windowCenter, width: windowWidth)
    }
    
    mutating func run() throws {
        try failDeferred3D("mip")
    }
}

// MARK: - MinIP Command

struct MinIPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "minip",
        abstract: "Generate Minimum Intensity Projection (MinIP)"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .long, help: "Projection direction: axial, sagittal, coronal (patient planes, PS3.3 C.7.6.2.1.1)")
    var direction: String = "axial"
    
    @Option(name: .long, help: "Slab thickness in mm (0 = full volume)")
    var thickness: Double = 0
    
    @Option(name: .long, help: "Window Center for display (Modality LUT output units, e.g. HU)")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window Width for display (>= 1, LINEAR function, PS3.3 C.11.2.1.2.1)")
    var windowWidth: Double?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
        guard projectionDirections().contains(direction.lowercased()) else {
            throw ValidationError("Invalid direction: \(direction). Must be one of: \(projectionDirections().joined(separator: ", "))")
        }
        try validateWindow(center: windowCenter, width: windowWidth)
    }
    
    mutating func run() throws {
        try failDeferred3D("minip")
    }
}

// MARK: - Average Command

struct AverageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "average",
        abstract: "Generate Average Intensity Projection"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .long, help: "Projection direction: axial, sagittal, coronal (patient planes, PS3.3 C.7.6.2.1.1)")
    var direction: String = "axial"
    
    @Option(name: .long, help: "Window Center for display (Modality LUT output units, e.g. HU)")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window Width for display (>= 1, LINEAR function, PS3.3 C.11.2.1.2.1)")
    var windowWidth: Double?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
        guard projectionDirections().contains(direction.lowercased()) else {
            throw ValidationError("Invalid direction: \(direction). Must be one of: \(projectionDirections().joined(separator: ", "))")
        }
        try validateWindow(center: windowCenter, width: windowWidth)
    }
    
    mutating func run() throws {
        try failDeferred3D("average")
    }
}

// MARK: - Surface Command

struct SurfaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "surface",
        abstract: "Extract 3D surface mesh using Marching Cubes"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output file path (.stl or .obj)")
    var output: String
    
    @Option(name: .long, help: "Threshold value for surface extraction")
    var threshold: Double
    
    @Option(name: .long, help: "Output format: stl, obj")
    var format: MeshFormat = .stl
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
    }
    
    mutating func run() throws {
        try failDeferred3D("surface")
    }
}

// MARK: - Volume Command

/// Not implemented: hidden from help (P-3D-VOLUME); running it prints so and exits 1.
struct VolumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "volume",
        abstract: "Volume rendering (not implemented)",
        shouldDisplay: false
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String] = []
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?
    
    @Option(name: .long, help: "Camera angle as azimuth,elevation (degrees)")
    var cameraAngle: String?
    
    @Option(name: .long, help: "Transfer function file (JSON)")
    var transferFunction: String?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    static let notImplementedMessage =
        "dicom-3d volume: volume rendering (ray casting) is not implemented; --camera-angle and --transfer-function have no effect. Use mip, minip, average or surface."

    mutating func run() throws {
        FileHandle.standardError.write(Data((Self.notImplementedMessage + "\n").utf8))
        throw ExitCode.failure
    }
}

// MARK: - Export Command

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export volume in various formats (NIfTI, MetaImage)"
    )
    
    @Argument(help: "Input DICOM files (multi-slice series)")
    var inputPaths: [String]
    
    @Option(name: .shortAndLong, help: "Output file prefix")
    var output: String
    
    @Option(name: .long, help: "Export formats: nifti, metaimage")
    var formats: String = "nifti"
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input file is required")
        }
    }
    
    mutating func run() throws {
        try failDeferred3D("export")
    }
}

// MARK: - Supporting Types

enum OutputFormat: String, ExpressibleByArgument {
    case png
    case dcm
}

enum InterpolationMethod: String, ExpressibleByArgument {
    case nearest
    case linear
    /// Deprecated: there is no cubic kernel; it samples as `linear` (P-3D-INTERPOLATION).
    case cubic

    /// The method actually used: `cubic` maps to `linear`.
    var effective: InterpolationMethod { self == .cubic ? .linear : self }

    /// Stderr note when the deprecated `cubic` is chosen.
    var deprecationNote: String? {
        self == .cubic ? "Note: --interpolation cubic is deprecated and uses linear (trilinear) interpolation" : nil
    }
}

enum MeshFormat: String, ExpressibleByArgument {
    case stl
    case obj
}

// MARK: - Backends Command

struct BackendsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backends",
        abstract: "List available hardware acceleration backends",
        discussion: """
            Displays the hardware acceleration backends available on this platform.
            
            Examples:
              dicom-3d backends
              dicom-3d backends --json
            """
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    mutating func run() throws {
        try failDeferred3D("backends")
    }
}

// MARK: - Encode Volume Command

struct EncodeVolumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encode-volume",
        abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Encode a DICOM slice series as a JP3D volumetric document",
        discussion: """
            DEFERRED: JP3D volumetric encoding is deferred pending `SwiftJ2K` 12.2.0
            (`SwiftJ2K3D` qualification).

            Reads a multi-slice DICOM series, validates uniform slice spacing, and
            encodes the volume as a single JP3D encapsulated DICOM document.

            The output file uses the private SOP class UID
            1.2.826.0.1.3680043.10.511.10 — not suitable for standard interchange.

            Compression modes:
              lossless         ISO/IEC 15444-1 lossless (default)
              lossless-htj2k   HTJ2K lossless (~5× faster decode than lossless)
              lossy            JPEG 2000 lossy at given --psnr
              lossy-htj2k      HTJ2K lossy at given --psnr

            Examples:
              dicom-3d encode-volume series/*.dcm --output vol.jp3d.dcm
              dicom-3d encode-volume ./series/ --output vol.jp3d.dcm --mode lossless-htj2k
              dicom-3d encode-volume series/*.dcm --output vol.jp3d.dcm --mode lossy --psnr 55
            """
    )

    @Argument(help: "Input DICOM files or a single directory containing the series")
    var inputPaths: [String]

    @Option(name: .shortAndLong, help: "Output JP3D DICOM document file path")
    var output: String

    @Option(name: .long, help: "Compression mode: lossless, lossless-htj2k, lossy, lossy-htj2k")
    var mode: String = "lossless"

    @Option(name: .long, help: "Target PSNR in dB for lossy modes (default: 40.0)")
    var psnr: Double = 40.0

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func validate() throws {
        guard !inputPaths.isEmpty else {
            throw ValidationError("At least one input path is required")
        }
        let validModes = ["lossless", "lossless-htj2k", "lossy", "lossy-htj2k"]
        guard validModes.contains(mode.lowercased()) else {
            throw ValidationError("Invalid --mode '\(mode)'. Must be one of: \(validModes.joined(separator: ", "))")
        }
        guard psnr > 0 else {
            throw ValidationError("--psnr must be positive")
        }
    }

    mutating func run() throws {
        try failDeferred3D("encode-volume")
    }
}

// MARK: - Decode Volume Command

struct DecodeVolumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decode-volume",
        abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Decode a JP3D volumetric document back to individual DICOM slices",
        discussion: """
            DEFERRED: JP3D volumetric decoding is deferred pending `SwiftJ2K` 12.2.0
            (`SwiftJ2K3D` qualification).

            Reads a JP3D DICOM document, decodes the JP3D codestream, and writes one
            DICOM file per slice into the output directory.

            Output files are named slice_0000.dcm, slice_0001.dcm, …

            Example:
              dicom-3d decode-volume volume.jp3d.dcm --output ./decoded/
            """
    )

    @Argument(help: "JP3D DICOM document file to decode")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Output directory for decoded DICOM slices")
    var output: String

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func validate() throws {
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw ValidationError("File not found: \(inputPath)")
        }
    }

    mutating func run() throws {
        try failDeferred3D("decode-volume")
    }
}

// MARK: - Inspect Command

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "[DEFERRED — pending SwiftJ2K 12.2.0] Display metadata from a JP3D volumetric document without decoding",
        discussion: """
            DEFERRED: `dicom-3d` is deferred pending `SwiftJ2K` 12.2.0 (`SwiftJ2K3D` qualification).

            Reads only the JSON sidecar embedded in a JP3D DICOM document, printing
            geometry, spacing, compression mode, and patient/study metadata.
            The JP3D codestream is not decoded, so this is near-instantaneous.

            Examples:
              dicom-3d inspect volume.jp3d.dcm
              dicom-3d inspect volume.jp3d.dcm --json
            """
    )

    @Argument(help: "JP3D DICOM document file to inspect")
    var inputPath: String

    @Flag(name: .long, help: "Output raw sidecar JSON instead of formatted text")
    var json: Bool = false

    mutating func validate() throws {
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw ValidationError("File not found: \(inputPath)")
        }
    }

    mutating func run() throws {
        try failDeferred3D("inspect")
    }
}

// MARK: - Main

DICOM3D.main()
