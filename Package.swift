// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DICOMKit",
    platforms: [
        // Platform baselines track the codec dependency deployment targets.
        // J2KSwift v11.x requires iOS 18 / macOS 15 / tvOS 18.
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        // visionOS 2 is the real floor: J2KSwift's codec kernels use `Mutex`,
        // which is visionOS 2+. J2KSwift still declares `.visionOS(.v1)` in its
        // own manifest, so it fails to compile for visionOS until that is raised
        // upstream — a visionOS build of DICOMKit is blocked on that, not on this
        // line. See Raster-Lab/J2KSwift.
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "DICOMKit",
            targets: ["DICOMKit"]
        ),
        .library(
            name: "DICOMCore",
            targets: ["DICOMCore"]
        ),
        .library(
            name: "DICOMDictionary",
            targets: ["DICOMDictionary"]
        ),
        .library(
            name: "DICOMNetwork",
            targets: ["DICOMNetwork"]
        ),
        .library(
            name: "DICOMWeb",
            targets: ["DICOMWeb"]
        ),
        .library(
            name: "DICOMToolbox",
            targets: ["DICOMToolbox"]
        ),
        .executable(
            name: "dicom-info",
            targets: ["dicom-info"]
        ),
        .executable(
            name: "dicom-convert",
            targets: ["dicom-convert"]
        ),
        .executable(
            name: "dicom-validate",
            targets: ["dicom-validate"]
        ),
        .executable(
            name: "dicom-anon",
            targets: ["dicom-anon"]
        ),
        .executable(
            name: "dicom-dump",
            targets: ["dicom-dump"]
        ),
        .executable(
            name: "dicom-query",
            targets: ["dicom-query"]
        ),
        .executable(
            name: "dicom-send",
            targets: ["dicom-send"]
        ),
        .executable(
            name: "dicom-diff",
            targets: ["dicom-diff"]
        ),
        .executable(
            name: "dicom-retrieve",
            targets: ["dicom-retrieve"]
        ),
        .executable(
            name: "dicom-split",
            targets: ["dicom-split"]
        ),
        .executable(
            name: "dicom-merge",
            targets: ["dicom-merge"]
        ),
        .executable(
            name: "dicom-json",
            targets: ["dicom-json"]
        ),
        .executable(
            name: "dicom-xml",
            targets: ["dicom-xml"]
        ),
        .executable(
            name: "dicom-pdf",
            targets: ["dicom-pdf"]
        ),
        .executable(
            name: "dicom-image",
            targets: ["dicom-image"]
        ),
        .executable(
            name: "dicom-video",
            targets: ["dicom-video"]
        ),
        .executable(
            name: "dicom-dcmdir",
            targets: ["dicom-dcmdir"]
        ),
        .executable(
            name: "dicom-archive",
            targets: ["dicom-archive"]
        ),
        .executable(
            name: "dicom-export",
            targets: ["dicom-export"]
        ),
        .executable(
            name: "dicom-qr",
            targets: ["dicom-qr"]
        ),
        .executable(
            name: "dicom-wado",
            targets: ["dicom-wado"]
        ),
        .executable(
            name: "dicom-echo",
            targets: ["dicom-echo"]
        ),
        // Re-enabled 2026-07-22 (owner approved) after the print enhancement plan
        // Milestones A–C/E brought the tool to production-grade; previously excluded
        // under Phase-1 (JPEG 2000 validation) scope.
        .executable(
            name: "dicom-print",
            targets: ["dicom-print"]
        ),
        // The receiving half of dicom-print: the printer emulator, headless.
        .executable(
            name: "dicom-printscp",
            targets: ["dicom-printscp"]
        ),
        .executable(
            name: "dicom-mwl",
            targets: ["dicom-mwl"]
        ),
        .executable(
            name: "dicom-mpps",
            targets: ["dicom-mpps"]
        ),
        .executable(
            name: "dicom-pixedit",
            targets: ["dicom-pixedit"]
        ),
        .executable(
            name: "dicom-tags",
            targets: ["dicom-tags"]
        ),
        .executable(
            name: "dicom-uid",
            targets: ["dicom-uid"]
        ),
        .executable(
            name: "dicom-compress",
            targets: ["dicom-compress"]
        ),
        .executable(
            name: "dicom-study",
            targets: ["dicom-study"]
        ),
        .executable(
            name: "dicom-script",
            targets: ["dicom-script"]
        ),
        .executable(
            name: "dicom-report",
            targets: ["dicom-report"]
        ),
        .executable(
            name: "dicom-measure",
            targets: ["dicom-measure"]
        ),
        .executable(
            name: "dicom-viewer",
            targets: ["dicom-viewer"]
        ),
        // Phase 1 scope: exclude dicom-cloud to avoid unrelated aws-sdk-swift dependency during J2K validation.
        // .executable(
        //     name: "dicom-cloud",
        //     targets: ["dicom-cloud"]
        // ),
        .executable(
            name: "dicom-3d",
            targets: ["dicom-3d"]
        ),
        .executable(
            name: "dicom-jpip",
            targets: ["dicom-jpip"]
        ),
        .executable(
            name: "dicom-j2k",
            targets: ["dicom-j2k"]
        ),
        .executable(
            name: "dicom-ai",
            targets: ["dicom-ai"]
        ),
        .executable(
            name: "dicom-gateway",
            targets: ["dicom-gateway"]
        ),
        .executable(
            name: "dicom-server",
            targets: ["dicom-server"]
        ),
        .library(
            name: "DICOMRenderKit",
            targets: ["DICOMRenderKit"]
        ),
        .library(
            name: "DICOMPrintKit",
            targets: ["DICOMPrintKit"]
        ),
        // macOS only: DICOMStudio is the desktop app's UI layer (AppKit split
        // views, panels, and pointer affordances). Everything a cross-platform
        // consumer needs is in the library products above, which build for
        // macOS, iOS and tvOS.
        .library(
            name: "DICOMStudio",
            targets: ["DICOMStudio"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        // Phase 1 scope: exclude aws-sdk-swift because it is unrelated to JPEG 2000 verification.
        // .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.6.0"),
        // J2KSwift — pure-Swift JPEG 2000 / HTJ2K / JP3D / JPIP codec.
        // URL-consumable as of v10.9.3 (Raster-Lab/J2KSwift#438): its manifest
        // always resolves CompressionFamily from its public Git URL.
        // v11.0.3 preserves tvOS power-state monitoring without using the
        // UIDevice battery APIs that are unavailable on Apple TV.
        .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "11.0.3"),
        // JLSwift — pure-Swift JPEG-LS (ITU-T T.87 / ISO-IEC 14495-1) codec.
        // Provides the `JPEGLS` product, which backs DICOMCore.JPEGLSCodec.
        .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.9.2"),
        // JLISwift — native-Swift JPEG codec (baseline/extended/progressive/
        // lossless SOF0–3, 8/12/16-bit, Accelerate-backed; jpegli-parity target).
        // Distinct from JLSwift (JPEG-LS). Products: `JLISwift` (core codec) and
        // `JLIDICOM` (DICOM bridge helpers). No external deps → URL-consumable.
        .package(url: "https://github.com/Raster-Lab/JLISwift.git", from: "0.5.0"),
        // JXLSwift — pure-Swift JPEG XL (ISO/IEC 18181) codec. URL-consumable as
        // of v1.0.1: the library target dropped its CompressionFamily dependency
        // (v1.0.0 referenced it via a local path, which SwiftPM rejected for a
        // stable-versioned consumer). Provides the `JXLSwift` product.
        // Floor 1.4.0: JXLCodec relies on the `PixelType.int16` signed-16-bit level
        // shift and `JXLDecoder.decode(_:signedOutput:)` added in that release.
        .package(url: "https://github.com/Raster-Lab/JXLSwift.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "DICOMCore",
            dependencies: [
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "J2KFileFormat", package: "J2KSwift"),
                .product(name: "J2K3D", package: "J2KSwift"),
                // Phase 5: hardware acceleration backend.
                // J2KAccelerate was removed in J2KSwift v11.0.0; the Accelerate
                // path is now guarded by #if canImport in CodecBackend.swift and
                // falls through to the scalar/Apple-Accelerate backend.
                .product(name: "J2KMetal", package: "J2KSwift"),
                // JPEG-LS — JLSwift backs DICOMCore's JPEGLSCodec.
                .product(name: "JPEGLS", package: "JLSwift"),
                // JPEG — JLISwift native-Swift JPEG codec + DICOM bridge helpers.
                .product(name: "JLISwift", package: "JLISwift"),
                .product(name: "JLIDICOM", package: "JLISwift"),
                // JPEG XL — JXLSwift pure-Swift JPEG XL codec.
                .product(name: "JXLSwift", package: "JXLSwift")
            ],
            exclude: ["CharacterSetHandler+README.md"]
        ),
        .target(
            name: "DICOMDictionary",
            dependencies: ["DICOMCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "DICOMNetwork",
            dependencies: ["DICOMCore", "DICOMDictionary"]
        ),
        .target(
            name: "DICOMWeb",
            // DICOMDictionary: keyword→tag resolution for the shared JSON/XML
            // conversion workflows' --filter-tag handling.
            dependencies: ["DICOMCore", "DICOMKit", "DICOMDictionary"]
        ),
        .target(
            name: "DICOMKit",
            dependencies: [
                "DICOMCore",
                "DICOMDictionary",
                // Level-5 validation (DICOMValidator) checks JPEG 2000 / HTJ2K
                // codestream conformance via J2KCore.
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2K3D", package: "J2KSwift"),
                // Phase 6: JPIP streaming
                .product(name: "JPIP", package: "J2KSwift")
            ],
            exclude: ["AI/SIMPLIFIED_README.md"]
        ),
        .target(
            name: "DICOMToolbox"
        ),
        // GPU frame rendering (GPU_RENDERING_PLAN.md). A separate target so the
        // headless dicom-* executables never link Metal and CI without a GPU is
        // unaffected — only DICOMStudio depends on it. Sits above DICOMKit
        // because the CPU fallback IS PixelDataRenderer.
        .target(
            name: "DICOMRenderKit",
            dependencies: ["DICOMCore", "DICOMKit"],
            // The shader ships as a resource and is compiled once per process,
            // NOT as a source file. This toolchain's SwiftPM silently ignores
            // `.metal` in a target's sources: it emits no `default.metallib` and
            // no resource bundle at all (verified with a minimal probe package).
            // Declaring it here is what creates `Bundle.module`, and it keeps one
            // source of truth for the kernels. See MetalRenderDevice.loadLibrary.
            //
            // The `.txt` suffix is load-bearing. Xcode's build system does NOT
            // share command-line SwiftPM's indifference to `.metal`: it applies
            // its CompileMetalFile rule on extension alone, even to a file
            // declared here as a resource, and then fails the build outright when
            // the separately-downloadable Metal Toolchain component is absent
            // ("cannot execute tool 'metal'"). Naming the file so no build rule
            // matches keeps `swift build`, `xcodebuild` and CI on the identical
            // runtime-compile path and leaves the toolchain download optional.
            resources: [.copy("Metal/FrameRender.metal.txt")]
        ),
        // Shared DICOM Print core: image preparation, job options, workflow
        // orchestration, and console formatting used by BOTH the dicom-print CLI
        // and DICOMStudio. It sits above DICOMKit (pixel decode/preprocess) and
        // DICOMNetwork (Print SCU DIMSE), which is why it is its own target —
        // DICOMKit itself must not gain a networking dependency.
        .target(
            name: "DICOMPrintKit",
            dependencies: [
                "DICOMCore",
                "DICOMDictionary",
                "DICOMKit",
                "DICOMNetwork"
            ]
        ),
        .testTarget(
            name: "DICOMCoreTests",
            dependencies: [
                "DICOMCore",
                "DICOMKit",
                .product(name: "J2KCodec", package: "J2KSwift")
            ]
        ),
        .testTarget(
            name: "DICOMDictionaryTests",
            dependencies: ["DICOMDictionary"]
        ),
        // Phase 1 scope: DICOMKitTests re-enabled for JP3D volume integration tests.
        // Only the JP3D-related test files are included to avoid pre-existing
        // concurrency errors in PerformanceTests/ImageCacheTests.swift.
        // dicom-ai: Segmentation output conformance (D44)
        .testTarget(
            name: "dicom-aiTests",
            dependencies: ["dicom-ai", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-aiTests"
        ),
        // dicom-video: --audio-channel-source maps PS3.16 CID 3000 into (003A,0300) (D56)
        .testTarget(
            name: "dicom-videoTests",
            dependencies: ["dicom-video", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-videoTests"
        ),
        // dicom-pdf: Encapsulated PDF round trip per PS3.3 2026a A.45.1 / Table C.24-2 (G3)
        .testTarget(
            name: "dicom-pdfTests",
            dependencies: ["dicom-pdf", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-pdfTests"
        ),
        // dicom-wado: WADO-URI / QIDO-RS / UPS-RS option values pinned to PS3.18 / PS3.3 2026a.
        .testTarget(
            name: "dicom-wadoTests",
            dependencies: [
                "dicom-wado", "DICOMWeb", "DICOMCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-wadoTests"
        ),
        // dicom-jpip: JPIP Referenced Transfer Syntaxes pinned to PS3.6 / PS3.5 2026a.
        .testTarget(
            name: "dicom-jpipTests",
            dependencies: ["dicom-jpip", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-jpipTests"
        ),
        // dicom-3d: volume geometry, plane names and derived MPR series pinned to PS3.3 /
        // PS3.16 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-3dTests",
            dependencies: ["dicom-3d", "DICOMKit", "DICOMCore",
                           .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Tests/dicom-3dTests"
        ),
        // dicom-viewer: VOI LUT function, MONOCHROME1, overlay planes and frame numbering
        // pinned to PS3.3 2026a.
        .testTarget(
            name: "dicom-viewerTests",
            dependencies: ["dicom-viewer", "DICOMKit", "DICOMCore",
                           .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Tests/dicom-viewerTests"
        ),
        // dicom-query / dicom-send: option values and C-STORE status handling
        // pinned to PS3.4 / PS3.7 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-queryTests",
            dependencies: ["dicom-query", "DICOMNetwork", "DICOMCore"],
            path: "Tests/dicom-queryTests"
        ),
        .testTarget(
            name: "dicom-sendTests",
            dependencies: ["dicom-send", "DICOMNetwork", "DICOMCore"],
            path: "Tests/dicom-sendTests"
        ),
        // dicom-retrieve / dicom-qr: --priority (PS3.7 Tables 9.3-9 / 9.3-6),
        // --relational-retrieve (PS3.4 C.5.2.1), --parallel (P-items 2026-10-01).
        .testTarget(
            name: "dicom-retrieveTests",
            dependencies: ["dicom-retrieve", "DICOMNetwork", "DICOMCore"],
            path: "Tests/dicom-retrieveTests"
        ),
        .testTarget(
            name: "dicom-qrTests",
            dependencies: ["dicom-qr", "DICOMNetwork", "DICOMCore"],
            path: "Tests/dicom-qrTests"
        ),
        // dicom-diff / dicom-split / dicom-merge: option vocabularies pinned to PS3.3 / PS3.5 /
        // PS3.6 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-diffTests",
            dependencies: ["dicom-diff", "DICOMCore"],
            path: "Tests/dicom-diffTests"
        ),
        .testTarget(
            name: "dicom-splitTests",
            dependencies: ["dicom-split", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-splitTests"
        ),
        // dicom-anon: --profile ps315 and the PS3.15 2026a Annex E Option flags, the
        // Table E.1-1a action labels and the recorded (0012,0062)/(0012,0064) attributes.
        .testTarget(
            name: "dicom-anonTests",
            dependencies: ["dicom-anon", "DICOMKit", "DICOMCore", "DICOMDictionary"],
            path: "Tests/dicom-anonTests"
        ),
        .testTarget(
            name: "dicom-mergeTests",
            dependencies: ["dicom-merge", "DICOMKit", "DICOMCore", "DICOMDictionary"],
            path: "Tests/dicom-mergeTests"
        ),
        // dicom-image / dicom-pixedit: Secondary Capture IOD (PS3.3 A.8.1) and Derived Image
        // (PS3.3 C.7.6.1.1.2, C.12.4) output pinned to 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-imageTests",
            dependencies: ["dicom-image", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-imageTests"
        ),
        .testTarget(
            name: "dicom-pixeditTests",
            dependencies: ["dicom-pixedit", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-pixeditTests"
        ),
        // dicom-gateway: the DICOM side of the HL7 v2 / FHIR mappings (PN, DA, TM, Patient's
        // Sex, UIDs) pinned to PS3.3 / PS3.5 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-gatewayTests",
            dependencies: ["dicom-gateway", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-gatewayTests"
        ),
        // dicom-dcmdir / dicom-uid / dicom-validate: File ID rules (PS3.10 8.x), UID roots and
        // UUID derived UIDs (PS3.5 9.1, B.2), --iod keywords (PS3.6 Table A-1), 2026a.
        .testTarget(
            name: "dicom-dcmdirTests",
            dependencies: ["dicom-dcmdir", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-dcmdirTests"
        ),
        .testTarget(
            name: "dicom-uidTests",
            dependencies: ["dicom-uid", "DICOMKit", "DICOMCore", "DICOMDictionary"],
            path: "Tests/dicom-uidTests"
        ),
        .testTarget(
            name: "dicom-validateTests",
            dependencies: ["dicom-validate", "DICOMKit", "DICOMCore", "DICOMDictionary"],
            path: "Tests/dicom-validateTests"
        ),
        // dicom-json / dicom-xml: option defaults pinned to PS3.18 2026a Annex F and PS3.19 2026a
        // Table A.1.5-2 (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-jsonTests",
            dependencies: ["dicom-json", "DICOMWeb", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-jsonTests"
        ),
        .testTarget(
            name: "dicom-xmlTests",
            dependencies: ["dicom-xml", "DICOMWeb", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-xmlTests"
        ),
        // dicom-study / dicom-archive / dicom-export (G2): attribute names, query-key notes, cine
        // frame rate, Burned In Annotation and the shared render path pinned to PS3.3 / PS3.4 /
        // PS3.6 2026a (DICOMCLI_STANDARD_IMPLEMENTATION.md).
        .testTarget(
            name: "dicom-studyTests",
            dependencies: ["dicom-study", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-studyTests"
        ),
        .testTarget(
            name: "dicom-archiveTests",
            dependencies: ["dicom-archive", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-archiveTests"
        ),
        .testTarget(
            name: "dicom-exportTests",
            dependencies: ["dicom-export", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-exportTests"
        ),
        // dicom-server: storage (PS3.10 7.1), C-FIND matching (PS3.4 C.2.2.2, C.6), retrieve
        // statuses (C.4-2/C.4-3), association rules (PS3.8 D.1, PS3.7 D.3.3.4), loopback SCU tests.
        .testTarget(
            name: "dicom-serverTests",
            dependencies: ["dicom-server", "DICOMNetwork", "DICOMKit", "DICOMCore", "DICOMDictionary"],
            path: "Tests/dicom-serverTests"
        ),
        .testTarget(
            name: "dicom-printTests",
            dependencies: [
                "dicom-print", "DICOMNetwork", "DICOMPrintKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-printTests"
        ),
        .testTarget(
            name: "dicom-printscpTests",
            dependencies: [
                "dicom-printscp", "DICOMNetwork", "DICOMPrintKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-printscpTests"
        ),
        // dicom-dump / dicom-info / dicom-tags: tag arguments (PS3.6 keywords), --set VR value
        // limits (PS3.5 Table 6.2-1) and group 0002 (PS3.10 7.1) pinned to 2026a.
        .testTarget(
            name: "dicom-dumpTests",
            dependencies: [
                "dicom-dump", "DICOMCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-dumpTests"
        ),
        .testTarget(
            name: "dicom-infoTests",
            dependencies: ["dicom-info", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-infoTests"
        ),
        .testTarget(
            name: "dicom-tagsTests",
            dependencies: [
                "dicom-tags", "DICOMKit", "DICOMCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-tagsTests"
        ),
        .testTarget(
            name: "DICOMKitTests",
            // DICOMDictionary: the presentation-state builders' VRs are asserted
            // against the standard dictionary rather than a hand-copied table.
            dependencies: ["DICOMKit", "DICOMCore", "DICOMDictionary"],
            exclude: [
                // RealWorldValue: the parser suite is in the sources allowlist below
                // (DICOM_TAG_AUDIT_FINDINGS.md); the remaining files are listed here
                // so they stay out of the build.
                "RealWorldValue/RealWorldValueLUTTests.swift",
                "RealWorldValue/RealWorldValueRendererTests.swift",
                "RealWorldValue/SUVCalculatorTests.swift",
                // "Video" is NOT excluded: its files are in the sources allowlist
                // below. An excluded directory wins over the allowlist, which is
                // how the Video suite silently never ran.
                "DICOMFileTests.swift",
                "DataSetTests.swift",
                "ImagePreparationTests.swift",
                "SequenceParsingTests.swift",
                // Not compiled into the test run (explicit sources: allowlist below);
                // declared here to resolve SwiftPM "unhandled file" warnings. These
                // perf tests carry pre-existing concurrency errors — see note above.
                "PerformanceTests/OptimizedParsingTests.swift",
                "PerformanceTests/DICOMBenchmarkTests.swift",
                "PerformanceTests/ParsingOptionsTests.swift",
                "PerformanceTests/ImageCacheTests.swift"
            ],
            sources: [
                "DeflatedDataSetTests.swift",
                "ExtendedOffsetTableParsingTests.swift",
                "JP3DVolumeDocumentTests.swift",
                // PS3.3 C.7.6.2.1.1, Table C.7-10 decode-volume slice geometry (D204, D205, 2026-10-01).
                "JP3DSliceGeometryTests.swift",
                "JPIPTests.swift",
                "DICOMConverterTests.swift",
                "ConversionDiagnosticsTests.swift",
                "PixelEditorTests.swift",
                // dicom-pixedit input checks lifted into DICOMKit (D270, 2026-10-06).
                "PixelEditInputChecksTests.swift",
                // dicom-anon option / report support lifted into DICOMKit (D275, 2026-10-06).
                "AnonCLISupportTests.swift",
                // dicom-image: colour sources must convert (24-bit RGB context bug).
                "ImageConverterColorTests.swift",
                "CompressionManagerImplicitVRTests.swift",
                "CompressionManagerMetricsTests.swift",
                "CompressionManagerJPEGEngineTests.swift",
                "CompressionManagerPhotometricInterpretationTests.swift",
                "DICOMFilePixelDataYBRDecodeTests.swift",
                "LossyImageCompressionAttributesTests.swift",
                "CompressedPreviewRenderParityTests.swift",
                "CompressionConsoleTests.swift",
                "ExportWindowParityTests.swift",
                // GPU_RENDERING_PLAN.md M1: the WindowLUT ⇄ scalar-chain equality
                // gate. (The benchmark harness lives in DICOMRenderKitTests, which
                // can reach both backends.)
                "WindowLUTParityTests.swift",
                "EncapsulatedPixelDataWriteTests.swift",
                // RESEARCH_ADOPTION_PLAN.md M0: parser resource limits + mutation fuzz.
                "ParserLimitTests.swift",
                // RESEARCH_ADOPTION_PLAN.md copy map: slice-independence guards at the
                // public Data boundary (parser); companion to DICOMCoreTests/CodecFuzzTests.
                "SliceIndependenceTests.swift",
                // PS3.3 C.11.1: Modality LUT Sequence precedence over slope/intercept.
                "ModalityLUTPrecedenceTests.swift",
                // PS3.15 Annex E Basic Application Level Confidentiality Profile engine.
                "ConfidentialityProfileTests.swift",
                // PS3.15 2026a E.2, E.3.5, E.3.6: Clean Descriptors, Modified Dates, (0028,0303);
                // legacy keyword parsing and --keep (D157, D158, D161, D163, D164).
                "ConfidentialityOptionsTests.swift",
                // dicom-dump / dicom-info / dicom-tags / dicom-diff engines (HexDumper,
                // MetadataPresenter, TagEditor, DICOMComparer) pinned to 2026a (D144-D153).
                "ToolEngineStandardTests.swift",
                // PS3.15 Annex E Clean Pixel Data Option (113101): region planning,
                // blanking mechanism, and earned attestation.
                "PixelRedactionTests.swift",
                // ECOSYSTEM_COMPARISON.md §5 cross-toolkit bug-scenario matrix.
                "CrossToolkitMatrixTests.swift",
                // RESEARCH_ADOPTION_PLAN.md M2: selected-frame access + frame index.
                "FrameAccessTests.swift",
                // RESEARCH_ADOPTION_PLAN.md M1: benchmark baseline runner
                // (skips unless DICOM_BENCHMARK_BASELINE=1).
                "BenchmarkBaselineTests.swift",
                "WaveformParseRegressionTests.swift",
                "OutputPathResolverTests.swift",
                // GSPS writer ⇄ parser round trip: a saved presentation state
                // the parser cannot read back is not worth storing.
                "GrayscalePresentationStateBuilderTests.swift",
                // PS3.3 Tables C.10-5, C.10-5a/5b/5c: compound graphics and styles (D39).
                "GraphicAnnotationStyleTests.swift",
                // The Pseudo-Color (A.33.3) and Color (A.33.2) Softcopy builders:
                // the same round-trip contract, each pinned to its Table A.33.x-1.
                "PseudoColorPresentationStateBuilderTests.swift",
                "ColorPresentationStateBuilderTests.swift",
                // D38: the pre-verification PresentationState suites, ported to the
                // current API and corrected to PS3.3 2026a (they had been dropped by
                // the sources allowlist since 2026-04-21 and never compiled).
                "PresentationStateTests/BlendingPresentationStateTests.swift",
                "PresentationStateTests/ColorMatrixTests.swift",
                "PresentationStateTests/ColorPresentationStateTests.swift",
                "PresentationStateTests/ColorTransformTests.swift",
                "PresentationStateTests/DisplayFeaturesTests.swift",
                "PresentationStateTests/DisplayShutterTests.swift",
                "PresentationStateTests/GraphicAnnotationTests.swift",
                "PresentationStateTests/ICCProfileAdvancedTests.swift",
                "PresentationStateTests/ICCProfileParserTests.swift",
                "PresentationStateTests/LUTColorTransformTests.swift",
                "PresentationStateTests/LUTTransformationTests.swift",
                "PresentationStateTests/PresentationStateTests.swift",
                "PresentationStateTests/PseudoColorPresentationStateTests.swift",
                "PresentationStateTests/SpatialTransformationTests.swift",
                // DICOM_TAG_AUDIT_FINDINGS.md: parsers rebuilt from numeric PS3.6
                // tags, so a wrong Tag constant cannot round-trip through itself.
                "TagAuditRegressionTests.swift",
                // End-user harness over the pydicom fixtures from Scripts/audit_fixtures
                // (skips unless AUDIT_FIXTURES is set).
                "AuditFixtureHarnessTests.swift",
                "HangingProtocol/HangingProtocolParserTests.swift",
                "HangingProtocol/HangingProtocolSerializerTests.swift",
                "HangingProtocol/HangingProtocolTests.swift",
                "HangingProtocol/SelectorAttributeValueTests.swift",
                "HangingProtocol/DisplaySetTests.swift",
                "HangingProtocol/HangingProtocolMatcherTests.swift",
                "HangingProtocol/ImageSetDefinitionTests.swift",
                "HangingProtocol/HangingProtocolNestingTests.swift",
                "RealWorldValue/RealWorldValueLUTParserTests.swift",
                // DICOM_VIDEO_CONVERSION_PLAN.md: the Video IOD suite. The
                // encapsulation tests write through DICOMWriter and re-parse
                // through DICOMParser, which is what an in-memory DataSet
                // round trip cannot check.
                "Video/VideoTests.swift",
                "Video/VideoEncapsulationTests.swift",
                "Video/VideoAttributeTests.swift",
                "Video/VideoTransferSyntaxTests.swift",
                "Video/BitstreamReaderTests.swift",
                "Video/H264ParserTests.swift",
                "Video/HEVCParserTests.swift",
                "Video/MPEG2ParserTests.swift",
                "Video/VideoConformanceValidatorTests.swift",
                "Video/MP4ContainerParserTests.swift",
                "Video/VideoProbeTests.swift",
                "Video/VideoExtractorTests.swift",
                // Builders (append / appendSequence) shared by the suites below.
                "TestHelpers/DataSet+TestHelpers.swift",
                // DICOM_TAG_AUDIT_FINDINGS.md #54: the ParametricMap, RadiationTherapy,
                // Segmentation, StructuredReporting and Waveform suites, previously
                // excluded and never run.
                "ParametricMap/ParametricMapAdditionalTests.swift",
                "ParametricMap/ParametricMapParserTests.swift",
                "ParametricMap/ParametricMapPixelDataExtractorTests.swift",
                "ParametricMap/ParametricMapRendererTests.swift",
                "ParametricMap/ParametricMapTests.swift",
                "RadiationTherapy/RTBeamTests.swift",
                "RadiationTherapy/RTDoseTests.swift",
                "RadiationTherapy/RTPlanTests.swift",
                "RadiationTherapy/RTStructureSetParserTests.swift",
                "RadiationTherapy/RTStructureSetTests.swift",
                "Segmentation/SegmentationBuilderTests.swift",
                "Segmentation/SegmentationParserTests.swift",
                "Segmentation/SegmentationPixelDataExtractorTests.swift",
                "Segmentation/SegmentationRendererTests.swift",
                "Segmentation/SegmentationTests.swift",
                // PS3.3 Tables C.8.20-2, A.51-1, C.7-22a, C.11.15-1 PALETTE COLOR LABELMAP (D37 b, 2026-09-30).
                "Segmentation/SegmentationPaletteColorTests.swift",
                // PS3.3 Table C.8.20-4 Segmented Property Category/Type Code Sequences Type 1 (D37 d, 2026-09-30).
                "Segmentation/SegmentedPropertyCodeTests.swift",
                // PS3.3 Table C.8.20-4 Tracking ID / Tracking UID each Type 1C on the other (D45, 2026-09-30).
                "Segmentation/SegmentTrackingTests.swift",
                // PS3.3 Table A.51-1 Patient / General Study Type 2 and Table C.7-8b Enhanced General Equipment (D71, 2026-10-01).
                "Segmentation/SegmentationIODModulesTests.swift",
                "StructuredReporting/BasicTextSRBuilderTests.swift",
                "StructuredReporting/CADFindingsExtractorTests.swift",
                "StructuredReporting/ChestCADSRBuilderTests.swift",
                "StructuredReporting/Comprehensive3DSRBuilderTests.swift",
                "StructuredReporting/ComprehensiveSRBuilderTests.swift",
                "StructuredReporting/ContentTreeNavigatorTests.swift",
                "StructuredReporting/EnhancedSRBuilderTests.swift",
                "StructuredReporting/KeyObjectExtractorTests.swift",
                "StructuredReporting/KeyObjectSelectionBuilderTests.swift",
                "StructuredReporting/MammographyCADSRBuilderTests.swift",
                "StructuredReporting/MeasurementExtractorTests.swift",
                "StructuredReporting/MeasurementGroupChildrenTests.swift",
                "StructuredReporting/MeasurementReportBuilderTests.swift",
                "StructuredReporting/MeasurementReportExtractorTests.swift",
                "StructuredReporting/SRDocumentBuilderTests.swift",
                "StructuredReporting/SRDocumentParserTests.swift",
                // PS3.3 Tables C.17-1, C.17-2, 8.8-1a and C.18.10-1 round trip (P-SRSER, 2026-09-29).
                "StructuredReporting/SRDocumentModuleRoundTripTests.swift",
                // PS3.3 Table C.17-2 Verifying Observer Sequence, PS3.5 7.4.2 (D37 a, 2026-09-29).
                "StructuredReporting/VerifyingObserverSequenceTests.swift",
                // PS3.3 C.18.10 TABLE content item round trip (P8, 2026-09-25).
                "StructuredReporting/TableContentItemRoundTripTests.swift",
                // PS3.3 Tables C.18.1-1, C.18.5-1, C.7-1, C.7-3, C.7-8, C.18.8-1; PS3.16 TID 1500/4019/1002 (D194-D196, D198, D199, 2026-10-01).
                "StructuredReporting/SRDeferredRowsTests.swift",
                "Waveform/WaveformTests.swift",
                "PerformanceTests/SIMDImageProcessorTests.swift",
                // PS3.3 C.11.2.1.2.1 LINEAR / C.11.2.1.3 SIGMOID: SIMD ⇄ scalar window parity (P-RENDER, 2026-09-29).
                "PerformanceTests/SIMDWindowParityTests.swift",
                // PS3.3 C.7.6.3.1.2 YBR_FULL / YBR_PARTIAL / ICT / RCT / packed 4:2:2 (P-RENDER, 2026-09-29).
                "PixelDataRendererYBRTests.swift",
                // PS3.3 Table C.7-10 / C.7.6.2.1.1 slice spacing and Table C.7-11c descriptor (P-VOL, 2026-09-29).
                "VolumeSpacingTests.swift",
                // PS3.3 Table C.7-13 Cine, C.7.6.1.1.5.1 terms, PS3.5 8.2.5/8.2.12 (P-VIDEO, 2026-09-29).
                "Video/VideoCineModuleTests.swift",
                // PS3.5 8.2.5/8.2.12 Table 8.2.12-1 audio check, PS3.3 Table C.7-13 (003A,0300) Items (D46, 2026-09-30).
                "Video/VideoAudioTests.swift",
                // PS3.5 2026a 8.2.6 MP@HL Rows/Columns and aspect_ratio_information; 8.2.5/8.2.6 MPEG-PS / PES (D226, D227, 2026-10-01).
                "Video/MPEG2HighLevelAndSystemsStreamTests.swift",
                // PS3.5 2026a Table 8-1 / 8-2 / 8-3 MPEG2 frame rates and Main Level maximum geometry (D238, 2026-10-01).
                "Video/MPEG2FrameRateTableTests.swift",
                // PS3.3 C.8.9.1.1.3/C.8.9.1.1.5, PS3.16 CID 85 and DCM 126410-126413 (P-SUV, 2026-09-29).
                // DICOM 2026a verification (DICOMKIT_STANDARD_IMPLEMENTATION.md): suites
                // that were never in this allowlist, plus the P-item suites of 2026-09-29.
                "DICOMWritingTests.swift",
                "FileMetaMediaStorageUIDTests.swift",
                "DICOMDIRReaderRecordTypeTests.swift",
                // PS3.3 2026a F.3.2.2 / Table F.3-3 navigation offsets, PRIVATE records kept (D240, 2026-10-01).
                "DICOMDIRReaderOffsetTests.swift",
                // PS3.11 profile tables, PS3.10 8.2/8.5 File IDs, one record per instance,
                // PS3.6 names in dump (D70, D128, D129, D131, 2026-10-01).
                "DICOMDIRConformanceTests.swift",
                // PS3.3 2026a F.5 record types and keys, F.3-3, F.4-1; PS3.11 image attribute values (D229-D233, 2026-10-01).
                "DICOMDIRRecordKeysTests.swift",
                // PS3.11 2026a Additional DICOMDIR Keys tables and Icon Images sections, PS3.3 F.7 (D239, 2026-10-01).
                "DICOMDIRProfileKeysTests.swift",
                // PS3.15 Table E.1-1 UID set incl. sequence items, PS3.5 9.1, PS3.6 Table A-1
                // wording (D133, D135, D136, D138, 2026-10-01).
                "UIDManagerStandardTests.swift",
                // CLI-local rules lifted into DICOMKit for the DICOMStudio Workshop (2026-10-06):
                // PS3.6 Table A-1 / PS3.3 Annex A IOD names (D248), PS3.4 C.2.2.2.5.1 Study Date
                // key warning (D249), PS3.5 9.1 UID root rule (D250), PS3.10 8.1/8.2/8.5/8.6
                // File-set rules (D253), PS3.5 A.1/A.2/A.3/A.5 native decompress targets (D267),
                // PS3.6 Table A-1 keywords of the convert catalog (D268).
                "Validation/IODNameTableTests.swift",
                "ArchiveStudyDateWarningTests.swift",
                "CompressionManagerXYBTests.swift",
                // Lossy output new SOP Instance UID, J2K/JPEG colour labels, File Meta UI padding,
                // Explicit VR Big Endian values, nested --strip-private, per-frame rescale
                // (D183-D186, D188, D190-D192, D197, D206, 2026-10-01).
                "DeferredRowsB6aCodecTests.swift",
                "StructuredReporting/SpatialCoordinatesClosedPolylineTests.swift",
                "StructuredReporting/CADSRBuilderValueTypeTests.swift",
                // PS3.3 Table C.17-6 Content Sequence under every SR value type (D31, 2026-09-29).
                "StructuredReporting/SRNestedContentItemTests.swift",
                // PS3.16 TID 4000 / TID 4100 in the template registry (D50, 2026-09-30).
                "StructuredReporting/CADTemplateValidationTests.swift",
                "AI/AIInferenceResultTests.swift",
                "EncapsulatedDocument/EncapsulatedDocumentTests.swift",
                "SecondaryCapture/SecondaryCaptureTests.swift",
                "Validation/IODRequirementValidatorTests.swift",
                "RealWorldValue/SUVStandardConformanceTests.swift",
                // D51: committed with the print work (ac61700, 3c904a3) but never
                // added to this allowlist, so they had never compiled.
                // PS3.3 C.11.1.1 / C.11.2.1.1 LUT Descriptor decoding (SRS FR-004).
                "GrayscaleLUTTests.swift",
                // Pseudo-colour palettes over RGB / YBR / PALETTE COLOR sources.
                "ColorSourcePaletteTests.swift",
                // PS3.5 2026d video conformance suite from origin/main (PR #217).
                "Video/VideoStandard2026dConformanceTests.swift",
                // dicom-video option conformance and CID 3000 option lifted into DICOMKit (D269, 2026-10-06).
                "Video/VideoOptionConformanceTests.swift",
            ]
        ),
        .testTarget(
            name: "DICOMNetworkTests",
            dependencies: ["DICOMNetwork", "DICOMCore", "DICOMKit"],
            // PACSIntegrationTests requires a live PACS and has drifted from the
            // current DICOMCore API (Tag(group:element:) labels, DataSet, audit
            // logger types). Quarantined from the unit-test target until ported.
            exclude: ["PACSIntegrationTests.swift"]
        ),
        // Security-critical, no-network regression coverage stays enabled even
        // while the broader legacy DICOMNetworkTests target remains out of scope.
        .testTarget(
            name: "DICOMNetworkSecurityTests",
            dependencies: ["DICOMNetwork"]
        ),
        .testTarget(
            name: "DICOMWebTests",
            dependencies: ["DICOMWeb", "DICOMKit"]
        ),
        // Film composition and output sinks (Print SCP Milestones C/D), plus
        // the emulator end-to-end: SCU → Print SCP → composer → sink.
        .testTarget(
            name: "DICOMPrintKitTests",
            // DICOMDictionary: published presentation states are checked
            // element-by-element against the standard data dictionary.
            dependencies: ["DICOMPrintKit", "DICOMNetwork", "DICOMCore",
                           "DICOMKit", "DICOMDictionary"]
        ),
        .testTarget(
            name: "DICOMToolboxTests",
            dependencies: ["DICOMToolbox"]
        ),
        // Phase 1 scope: exclude DICOMToolsTests because they depend on server and AI targets outside JPEG 2000 validation.
        // .testTarget(
        //     name: "DICOMToolsTests",
        //     dependencies: ["DICOMKit", "DICOMCore", "DICOMDictionary", "DICOMNetwork", "DICOMWeb", "dicom-server", "dicom-gateway", "dicom-ai", "dicom-echo", "dicom-query"]
        // ),
        .testTarget(
            name: "DICOMViewerTests",
            dependencies: ["DICOMKit", "DICOMCore"],
            path: "Tests/DICOMToolsTests",
            exclude: [
                "DICOMAITests.swift",
                "DICOMAnonTests.swift",
                "DICOMArchiveTests.swift",
                "DICOMCloudTests.swift",
                "DICOMCompressTests.swift",
                "DICOMConvertTests.swift",
                "DICOMDcmdirTests.swift",
                "DICOMDiffTests.swift",
                "DICOMDumpTests.swift",
                "DICOMEchoTests.swift",
                "DICOMExportTests.swift",
                "DICOMGatewayTests.swift",
                "DICOMImageTests.swift",
                "DICOMInfoTests.swift",
                "DICOMJsonTests.swift",
                "DICOMMeasureTests.swift",
                "DICOMMergeTests.swift",
                "DICOMPdfTests.swift",
                "DICOMPixeditTests.swift",
                "DICOMQRTests.swift",
                "DICOMQueryTests.swift",
                "DICOMReportTests.swift",
                "DICOMRetrieveTests.swift",
                "DICOMScriptTests.swift",
                "DICOMSendTests.swift",
                "DICOMSplitTests.swift",
                "DICOMStudyTests.swift",
                "DICOMTagsTests.swift",
                "DICOMUIDTests.swift",
                "DICOMValidateTests.swift",
                "DICOMXmlTests.swift"
            ],
            sources: ["DICOMViewerTests.swift"]
        ),
        .executableTarget(
            name: "dicom-info",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-info",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-convert",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-convert",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-validate",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-validate",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-anon",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-anon",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-dump",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-dump",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-query",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                // --format dicom-json: PS3.18 F.2 encoder (P-QUERY-JSON)
                "DICOMWeb",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-query",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-send",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-send",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-diff",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-diff",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-retrieve",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-retrieve",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-split",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-split",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-merge",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-merge",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-json",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMWeb",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-json",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-xml",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMWeb",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-xml",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-pdf",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-pdf",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-image",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-image",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-video",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-video",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-dcmdir",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-dcmdir",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-archive",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-archive",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-export",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-export",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-qr",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-qr",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-wado",
            dependencies: [
                "DICOMCore",
                "DICOMWeb",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-wado",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-echo",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-echo",
            exclude: ["README.md"]
        ),
        // Re-enabled 2026-07-22 (owner approved) — see the matching product entry above.
        .executableTarget(
            name: "dicom-print",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMNetwork",
                "DICOMPrintKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-print",
            exclude: ["README.md"]
        ),
        // Milestone F of DICOM_PRINT_SCP_PLAN.md — a thin shell over the same
        // DICOMPrintKit types DICOM Studio's Print SCP screen runs.
        .executableTarget(
            name: "dicom-printscp",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMNetwork",
                "DICOMPrintKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-printscp",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-mwl",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-mwl",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-mpps",
            dependencies: [
                "DICOMCore",
                "DICOMNetwork",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-mpps",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-pixedit",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-pixedit",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-tags",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-tags",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-uid",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-uid",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-compress",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-compress",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-study",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-study",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-script",
            dependencies: [
                "DICOMKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-script",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-report",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-report",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-measure",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-measure",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-viewer",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-viewer",
            exclude: ["README.md"]
        ),
        // Phase 1 scope: exclude dicom-cloud to avoid unrelated aws-sdk-swift dependency during J2K validation.
        // .executableTarget(
        //     name: "dicom-cloud",
        //     dependencies: [
        //         "DICOMKit",
        //         "DICOMCore",
        //         .product(name: "ArgumentParser", package: "swift-argument-parser"),
        //         .product(name: "AWSS3", package: "aws-sdk-swift")
        //     ],
        //     path: "Sources/dicom-cloud",
        //     exclude: ["README.md"]
        // ),
        .executableTarget(
            name: "dicom-3d",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-3d",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-jpip",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "JPIP", package: "J2KSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-jpip"
        ),
        .executableTarget(
            name: "dicom-j2k",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "J2KFileFormat", package: "J2KSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-j2k",
            exclude: ["README.md"]
        ),
        // Re-enabled 2026-10-01 for the D44 Segmentation fix (dicom-ai verification).
        .executableTarget(
            name: "dicom-ai",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-ai",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-gateway",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-gateway",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "dicom-server",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMNetwork",
                "DICOMDictionary",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/dicom-server",
            exclude: ["README.md", "DATABASE_SCHEMA.md", "DEPLOYMENT_GUIDE.md"]
        ),
        .target(
            name: "DICOMStudio",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                "DICOMNetwork",
                "DICOMPrintKit",
                // GPU frame rendering, with the CPU renderer as the fallback.
                "DICOMRenderKit",
                "DICOMWeb"
            ],
            path: "Sources/DICOMStudio",
            exclude: ["ARCHITECTURE.md"]
        ),
        .testTarget(
            name: "DICOMRenderKitTests",
            dependencies: ["DICOMRenderKit", "DICOMCore", "DICOMKit"]
        ),
        .testTarget(
            name: "DICOMStudioTests",
            // DICOMPrintKit: the viewer-presentation geometry and film-pixel
            // transform the print path bakes into marks.
            dependencies: ["DICOMStudio", "DICOMWeb", "DICOMPrintKit", "DICOMNetwork"],
            resources: [
                // Small synthetic DICOM the print tests render (see
                // StudioTestFixtures). PHI-free — generated, not patient data.
                .copy("Fixtures")
            ]
        ),
        // dicom-convert: --transfer-syntax Table A-1 keywords, --window-width per PS3.3 C.11.2.1.2.1.
        .testTarget(
            name: "dicom-convertTests",
            dependencies: [
                "dicom-convert", "DICOMKit", "DICOMCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/dicom-convertTests"
        ),
        // dicom-measure: spacing source (PS3.3 10.7.1, C.7.6.16.2.1, C.8.5.5, Tables C.8-71 / C.8-25),
        // C.18.6-1 coordinates, C.11.1.1.2 output units, PS3.16 UCUM codes.
        .testTarget(
            name: "dicom-measureTests",
            dependencies: ["dicom-measure", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-measureTests"
        ),
        // dicom-compress: codec / syntax help rows pinned to PS3.6 2026a Table A-1 (D9).
        .testTarget(
            name: "dicom-compressTests",
            dependencies: ["dicom-compress", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-compressTests"
        ),
        // dicom-report: SR rendering pinned to PS3.3 2026a Tables C.17.3-7, C.17.3-8, C.17-2,
        // C.18.1-1, C.18.8-1, 8.8-1a and PS3.16 2026a 6.1.
        .testTarget(
            name: "dicom-reportTests",
            dependencies: ["dicom-report", "DICOMKit", "DICOMCore"],
            path: "Tests/dicom-reportTests"
        ),
        // dicom-j2k: frame/fragment mapping, Photometric Interpretation, lossy provenance and
        // derived-image attributes after a re-encode, pinned to PS3.5 / PS3.3 2026a.
        .testTarget(
            name: "dicom-j2kTests",
            dependencies: [
                "dicom-j2k",
                "DICOMCore",
                "DICOMKit",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Oracle-based round-trip tests for the local (non-network) dicom-* tools.
        // Calls the DICOMKit library directly (not the CLI binaries). See
        // ROUND_TRIP_TESTS_PLAN.md.
        // Path is singular "DICOMRoundTripTest" (where the anonymized corpus lives);
        // the corpus is resolved at runtime via #filePath (skip-if-absent), so it is
        // excluded from compiled sources rather than bundled.
        .testTarget(
            name: "DICOMRoundTripTests",
            dependencies: [
                "DICOMKit",
                "DICOMCore",
                "DICOMDictionary",
                "DICOMWeb",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift")
            ],
            path: "Tests/DICOMRoundTripTest",
            exclude: ["Corpus"]
        )
    ]
)
