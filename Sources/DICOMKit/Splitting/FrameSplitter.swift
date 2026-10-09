// NEMA-verified: 2026a, checked 2026-09-29 — concatenation and Number of Frames rules per PS3.3 2026a C.7.6.16 and C.7.6.6
import Foundation
import DICOMCore
import DICOMDictionary

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Output format for extracted frames.
public enum SplitOutputFormat: String, Sendable {
    case dicom
    case png
    case jpeg
    case tiff
}

/// Which SOP Class the extracted frames carry.
public enum SplitTargetPolicy: String, Sendable, CaseIterable {
    /// Convert to the classic single-frame class when one exists
    /// (Enhanced CT → CT Image …), otherwise keep the class with one frame.
    case auto
    /// Always keep the source SOP Class (one-frame Enhanced instances).
    case same
    /// Require a classic counterpart; sources without one are skipped.
    case classic
}

/// How Instance Number is assigned to the extracted frames.
public enum SplitInstanceNumbering: String, Sendable, CaseIterable {
    /// 1-based frame number in storage order.
    case frame
    /// In-Stack Position Number from Frame Content (falls back to `frame`).
    case instack
    /// Leave the source Instance Number untouched.
    case original
}

/// Whether frames are spread over several output series.
public enum SplitSeriesGrouping: String, Sendable, CaseIterable {
    case none
    /// One series per Stack ID.
    case stack
    /// One series per Temporal Position Index.
    case temporal
}

/// Enhanced-multiframe options for a split (defaults reproduce the plain
/// "one file per frame" behaviour plus SOP-class conversion).
public struct SplitOptions: Sendable {
    public var target: SplitTargetPolicy = .auto
    public var privateGroups: PrivateFunctionalGroupPolicy = .flatten
    public var pixelHandling: MultiframePixelHandling = .preserve
    public var instanceNumbering: SplitInstanceNumbering = .frame
    public var seriesGrouping: SplitSeriesGrouping = .none
    /// Mint a new Series Instance UID for the extracted frames.
    public var newSeries: Bool = false
    /// Write concatenation parts of this many frames instead of single-frame
    /// instances (PS3.3 C.7.6.16.2.2.4). The SOP class is always kept.
    public var framesPerInstance: Int? = nil
    /// Derive SOP / Series Instance UIDs from the source UIDs (same input → same
    /// output, and references between multi-frame objects can be rewritten).
    public var deterministicUIDs: Bool = true

    public init() {}

    var isConcatenation: Bool { (framesPerInstance ?? 0) > 0 }
}

/// Aggregated outcome of a split run (per-frame stats + written file paths) so
/// adapters can render their own summary.
public struct SplitResult: Sendable {
    public var processedFiles = 0
    public var skippedFiles = 0
    /// Output instances written: one per frame, or one per concatenation part.
    public var extracted = 0
    public var failed = 0
    public var writtenPaths: [String] = []

    public init() {}
}

/// Splits multi-frame DICOM files into individual frames (as DICOM or image files).
///
/// Lives in the DICOMKit library so the `dicom-split` CLI and DICOMStudio run the
/// exact same extraction code. Verbose progress flows through the injected `log`
/// closure; per-frame results accumulate into a returned ``SplitResult`` so each
/// adapter formats its own summary.
///
/// DICOM output is a real Enhanced → classic conversion: the SOP Class comes from
/// ``MultiframeSOPClassMap``, the functional groups are demultiplexed by
/// ``FunctionalGroupFlattener``, legacy cine/NM vectors by ``LegacyVectorResolver``
/// and the pixel bytes by ``MultiframePixelAssembler`` (compressed sources keep
/// their transfer syntax frame by frame).
public struct FrameSplitter {
    public let outputPath: String
    public let format: SplitOutputFormat
    public let applyWindow: Bool
    public let windowCenter: Double?
    public let windowWidth: Double?
    public let namingPattern: String?
    public let verbose: Bool
    public let options: SplitOptions

    private let log: (String) -> Void
    private let fileManager = FileManager.default

    public init(
        outputPath: String,
        format: SplitOutputFormat,
        applyWindow: Bool,
        windowCenter: Double?,
        windowWidth: Double?,
        namingPattern: String?,
        verbose: Bool,
        options: SplitOptions = SplitOptions(),
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.outputPath = outputPath
        self.format = format
        self.applyWindow = applyWindow
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.namingPattern = namingPattern
        self.verbose = verbose
        self.options = options
        self.log = log
    }

    // MARK: - Per-file plan

    /// Everything decided once per source file before its frames are written.
    struct SplitPlan {
        enum Conversion {
            case convert(toSOPClassUID: String)
            case sameClass
        }
        let sourceSOPClassUID: String?
        let entry: MultiframeSOPClassMap.Entry?
        let conversion: Conversion
        let frameInfos: [FunctionalGroupFlattener.FrameInfo]
        /// Series Instance UID per frame (grouping / new-series applied).
        let seriesUIDs: [String]
        /// Series Number per frame when grouping splits the series, else nil.
        let seriesNumbers: [String?]
        let instanceNumbers: [String?]

        var convertsToClassic: Bool {
            if case .convert = conversion { return true }
            return false
        }
        var targetSOPClassUID: String? {
            if case .convert(let uid) = conversion { return uid }
            return sourceSOPClassUID
        }
    }

    /// Processes a single DICOM file, accumulating into `result`.
    public func processFile(_ path: String, frameIndices: Set<Int>?, into result: inout SplitResult) async {
        if verbose {
            log("Processing: \(path)")
        }

        // Read DICOM file
        guard let dicomFile = try? DICOMFile.read(from: URL(fileURLWithPath: path)) else {
            log("Warning: Skipping non-DICOM file: \(path)")
            result.skippedFiles += 1
            return
        }

        // Check if multi-frame
        let numberOfFrames = dicomFile.numberOfFrames ?? 1

        if numberOfFrames <= 1 {
            if verbose {
                log("  Single-frame file, skipping")
            }
            result.skippedFiles += 1
            return
        }

        if verbose {
            log("  Found \(numberOfFrames) frames")
        }

        // Decide the SOP class conversion once per file.
        let plan: SplitPlan
        do {
            plan = try makePlan(for: dicomFile, numberOfFrames: numberOfFrames)
        } catch let error as SplitError {
            log(SplitConsole.skippedLine(path: path, reason: error.description))
            result.skippedFiles += 1
            return
        } catch {
            log(SplitConsole.skippedLine(path: path, reason: "\(error)"))
            result.skippedFiles += 1
            return
        }

        if verbose, format == .dicom {
            for line in SplitConsole.planLines(
                sourceName: plan.entry?.name ?? plan.sourceSOPClassUID ?? "unknown SOP class",
                targetSOPClassUID: plan.convertsToClassic ? plan.targetSOPClassUID : nil,
                functionalGroups: plan.entry?.hasFunctionalGroups ?? false,
                seriesCount: Set(plan.seriesUIDs).count
            ) {
                log(line)
            }
        }

        // Concatenation: N frames per part, SOP class kept, bookkeeping added.
        if format == .dicom, let framesPer = options.framesPerInstance, framesPer > 0 {
            if frameIndices != nil {
                log(SplitConsole.frameSelectionIgnoredForConcatenationLine)
            }
            result.processedFiles += 1
            extractConcatenation(from: dicomFile, framesPerInstance: framesPer, numberOfFrames: numberOfFrames,
                                 originalPath: path, plan: plan, into: &result)
            return
        }

        // Determine which frames to extract
        let framesToExtract: [Int]
        if let indices = frameIndices {
            framesToExtract = indices.filter { $0 >= 0 && $0 < numberOfFrames }.sorted()
        } else {
            framesToExtract = Array(0..<numberOfFrames)
        }

        if verbose {
            log("  Extracting \(framesToExtract.count) frames")
        }

        result.processedFiles += 1

        // Extract each frame
        var successCount = 0
        var failureCount = 0

        for frameIndex in framesToExtract {
            do {
                let written = try extractFrame(
                    from: dicomFile,
                    frameIndex: frameIndex,
                    totalFrames: numberOfFrames,
                    originalPath: path,
                    plan: plan
                )
                successCount += 1
                result.extracted += 1
                result.writtenPaths.append(written)
            } catch {
                failureCount += 1
                result.failed += 1
                if verbose {
                    log("  Failed to extract Frame number \(frameIndex + 1): \(error)")
                }
            }
        }

        if verbose {
            log("  Completed: \(successCount) succeeded, \(failureCount) failed")
        }
    }

    /// Processes a directory of DICOM files, returning the aggregated result.
    public func processDirectory(_ path: String, recursive: Bool, frameIndices: Set<Int>?) async throws -> SplitResult {
        let files = try gatherFiles(from: path, recursive: recursive)

        if verbose {
            log("Found \(files.count) files to process")
            log("")
        }

        var result = SplitResult()
        for file in files {
            await processFile(file, frameIndices: frameIndices, into: &result)
        }
        return result
    }

    // MARK: - Planning

    func makePlan(for dicomFile: DICOMFile, numberOfFrames: Int) throws -> SplitPlan {
        let ds = dicomFile.dataSet
        let sourceSOPClass = ds.string(for: .sopClassUID).map(MultiframeSOPClassMap.normalize)
        let entry = MultiframeSOPClassMap.entry(for: sourceSOPClass)

        let conversion: SplitPlan.Conversion
        if options.isConcatenation {
            // Concatenations keep the SOP class and are the one legal way to split
            // Segmentation / Parametric Map; the OPT IOD forbids them.
            if let uid = sourceSOPClass, MultiframeConcatenation.refusedSOPClasses.contains(uid) {
                throw SplitError.unsupportedSOPClass(name: entry?.name ?? uid,
                                                     reason: "the IOD does not permit concatenations")
            }
            conversion = .sameClass
        } else {
            switch (entry?.splitTarget, options.target) {
            case (.refuse(let reason)?, _):
                throw SplitError.unsupportedSOPClass(name: entry?.name ?? sourceSOPClass ?? "unknown", reason: reason)
            case (.convert(let uid)?, .auto), (.convert(let uid)?, .classic):
                conversion = .convert(toSOPClassUID: uid)
            case (.convert?, .same):
                conversion = .sameClass
            case (.sameClass?, .classic):
                throw SplitError.noClassicCounterpart(name: entry?.name ?? sourceSOPClass ?? "unknown")
            case (.sameClass?, _), (nil, _):
                conversion = .sameClass
            }
        }

        let hasFG = entry?.hasFunctionalGroups ?? (ds[.perFrameFunctionalGroupsSequence] != nil)
        let infos: [FunctionalGroupFlattener.FrameInfo] = (0..<numberOfFrames).map {
            hasFG ? FunctionalGroupFlattener.frameInfo(in: ds, frameIndex: $0) : FunctionalGroupFlattener.FrameInfo()
        }

        // Series assignment.
        let sourceSeries = ds.string(for: .seriesInstanceUID).map(MultiframeSOPClassMap.normalize)
        let sourceInstance = ds.string(for: .sopInstanceUID).map(MultiframeSOPClassMap.normalize) ?? ""
        func mintSeries(_ group: String) -> String {
            options.deterministicUIDs
                ? MultiframeInstanceUIDs.derivedSeries(from: sourceSeries ?? sourceInstance, group: group)
                : UIDGenerator.generateSeriesInstanceUID().value
        }
        let baseSeries = options.newSeries ? mintSeries("new") : (sourceSeries ?? mintSeries("base"))
        // Series Number is study-scoped: without a source number, bare ordinals
        // (1, 2, 3...) would collide with the study's existing series, so mint
        // from a deliberately high base instead.
        let baseSeriesNumber = ds.string(for: .seriesNumber).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 99

        var seriesUIDs = Array(repeating: baseSeries, count: numberOfFrames)
        var seriesNumbers = Array(repeating: String?.none, count: numberOfFrames)
        let groupKeys: [String?]
        switch options.seriesGrouping {
        case .none: groupKeys = Array(repeating: nil, count: numberOfFrames)
        case .stack: groupKeys = infos.map { $0.stackID }
        case .temporal: groupKeys = infos.map { $0.temporalPositionIndex.map(String.init) }
        }
        if options.seriesGrouping != .none {
            var uidForKey: [String: (String, Int)] = [:]
            for (i, key) in groupKeys.enumerated() {
                guard let key else { continue }
                if uidForKey[key] == nil {
                    let ordinal = uidForKey.count + 1
                    let uid = ordinal == 1 && !options.newSeries ? baseSeries : mintSeries("\(options.seriesGrouping.rawValue):\(key)")
                    uidForKey[key] = (uid, ordinal)
                }
                let (uid, ordinal) = uidForKey[key]!
                seriesUIDs[i] = uid
                seriesNumbers[i] = String(baseSeriesNumber * 100 + ordinal)
            }
        }

        // Instance numbers.
        let instanceNumbers: [String?] = (0..<numberOfFrames).map { i in
            switch options.instanceNumbering {
            case .frame: return String(i + 1)
            case .instack: return String(infos[i].inStackPositionNumber.map(Int.init) ?? (i + 1))
            case .original: return nil
            }
        }

        return SplitPlan(sourceSOPClassUID: sourceSOPClass, entry: entry, conversion: conversion,
                         frameInfos: infos, seriesUIDs: seriesUIDs, seriesNumbers: seriesNumbers,
                         instanceNumbers: instanceNumbers)
    }

    // MARK: - Extraction

    /// Extracts a single frame from a multi-frame DICOM file, returning the
    /// output file path.
    @discardableResult
    private func extractFrame(
        from dicomFile: DICOMFile,
        frameIndex: Int,
        totalFrames: Int,
        originalPath: String,
        plan: SplitPlan
    ) throws -> String {
        let filename = generateFilename(
            frameIndex: frameIndex,
            totalFrames: totalFrames,
            originalPath: originalPath,
            dicomFile: dicomFile,
            plan: plan
        )
        let outputFilePath = (outputPath as NSString).appendingPathComponent(filename)

        switch format {
        case .dicom:
            try extractFrameAsDICOM(
                from: dicomFile,
                frameIndex: frameIndex,
                outputPath: outputFilePath,
                plan: plan
            )

        case .png, .jpeg, .tiff:
            try extractFrameAsImage(
                from: dicomFile,
                frameIndex: frameIndex,
                outputPath: outputFilePath
            )
        }

        if verbose {
            log("  Extracted Frame number \(frameIndex + 1) -> \(filename)")
        }

        return outputFilePath
    }

    /// Builds the single-frame data set for `frameIndex` (no pixel data yet).
    /// Exposed for the viewer's per-frame model and the tests.
    public func singleFrameDataSet(from dicomFile: DICOMFile, frameIndex: Int) throws -> DataSet {
        let numberOfFrames = dicomFile.numberOfFrames ?? 1
        let plan = try makePlan(for: dicomFile, numberOfFrames: numberOfFrames)
        return frameDataSet(from: dicomFile.dataSet, frameIndex: frameIndex, plan: plan)
    }

    func frameDataSet(from source: DataSet, frameIndex: Int, plan: SplitPlan) -> DataSet {
        let hasFG = plan.entry?.hasFunctionalGroups ?? (source[.perFrameFunctionalGroupsSequence] != nil)
        let vectorKind = plan.entry?.legacyVectors ?? (source[.frameIncrementPointer] != nil ? .cine : .none)

        var ds: DataSet
        if hasFG {
            if plan.convertsToClassic {
                ds = FunctionalGroupFlattener.flatten(source, frameIndex: frameIndex, toClassic: true,
                                                      privatePolicy: options.privateGroups)
                if options.deterministicUIDs {
                    ProvenanceRewriter.expandFrameReferences(in: &ds)
                }
            } else {
                ds = FunctionalGroupFlattener.reduceToSingleFrame(source, frameIndex: frameIndex)
            }
        } else {
            ds = DataSet()
            for element in source.allElements
            where element.tag != .pixelData && element.tag != .extendedOffsetTable
                && element.tag != .extendedOffsetTableLengths {
                ds[element.tag] = element
            }
        }

        LegacyVectorResolver.resolve(&ds, frameIndex: frameIndex, kind: vectorKind,
                                     mode: plan.convertsToClassic ? .classic : .sameClass)

        // NumberOfFrames: absent in the classic single-frame IODs, "1" otherwise.
        if plan.convertsToClassic {
            ds[.numberOfFrames] = nil
        } else {
            ds.setString("1", for: .numberOfFrames, vr: .IS)
        }

        if case .convert(let uid) = plan.conversion {
            ds.setString(uid, for: .sopClassUID, vr: .UI)
        }

        ds.setString(plan.seriesUIDs[frameIndex], for: .seriesInstanceUID, vr: .UI)
        if let number = plan.seriesNumbers[frameIndex] {
            ds.setString(number, for: .seriesNumber, vr: .IS)
        }
        if let instance = plan.instanceNumbers[frameIndex] {
            ds.setString(instance, for: .instanceNumber, vr: .IS)
        }
        return ds
    }

    /// Extracts a frame as a new DICOM file.
    private func extractFrameAsDICOM(
        from dicomFile: DICOMFile,
        frameIndex: Int,
        outputPath: String,
        plan: SplitPlan
    ) throws {
        guard dicomFile.dataSet[.pixelData] != nil else {
            throw SplitError.missingPixelData
        }

        let payload: FramePixelPayload
        do {
            payload = try MultiframePixelAssembler.extractFrame(from: dicomFile, frame: frameIndex,
                                                                handling: options.pixelHandling)
        } catch {
            throw SplitError.frameExtractionFailed(frameIndex: frameIndex)
        }

        var newDataSet = frameDataSet(from: dicomFile.dataSet, frameIndex: frameIndex, plan: plan)
        var fileMeta = dicomFile.fileMetaInformation

        // Update SOP Instance UID to make it unique
        let newSOPInstanceUID = sopInstanceUID(for: dicomFile.dataSet, frame: frameIndex)
        newDataSet.setString(newSOPInstanceUID, for: .sopInstanceUID, vr: .UI)
        fileMeta.setString(newSOPInstanceUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
        if let target = plan.targetSOPClassUID {
            fileMeta.setString(target, for: .mediaStorageSOPClassUID, vr: .UI)
        }

        // Pixel data for this frame only, with the transfer syntax the bytes are valid in.
        newDataSet[.pixelData] = MultiframePixelAssembler.pixelDataElement(for: payload)
        MultiframePixelAssembler.applyPixelDescription(payload, to: &newDataSet, fileMeta: &fileMeta)

        let newFile = DICOMFile(fileMetaInformation: fileMeta, dataSet: newDataSet)
        let dicomData = try newFile.write()
        try dicomData.write(to: URL(fileURLWithPath: outputPath))
    }

    /// SOP Instance UID for an extracted frame: derived from the source when
    /// `deterministicUIDs` is on (dcm4che `<mapped>.N` parity), else fresh.
    private func sopInstanceUID(for source: DataSet, frame: Int, salt: String = "") -> String {
        if options.deterministicUIDs,
           let sourceUID = source.string(for: .sopInstanceUID).map(MultiframeSOPClassMap.normalize), !sourceUID.isEmpty {
            return MultiframeInstanceUIDs.derived(from: sourceUID, frame: frame, salt: salt)
        }
        return UIDGenerator.generateSOPInstanceUID().value
    }

    // MARK: - Concatenations

    /// Writes the source as `ceil(frames / framesPerInstance)` concatenation parts.
    private func extractConcatenation(
        from dicomFile: DICOMFile,
        framesPerInstance: Int,
        numberOfFrames: Int,
        originalPath: String,
        plan: SplitPlan,
        into result: inout SplitResult
    ) {
        let source = dicomFile.dataSet
        let parts = MultiframeConcatenation.parts(frameCount: numberOfFrames, framesPerInstance: framesPerInstance)
        let concatenationUID = options.deterministicUIDs
            ? sopInstanceUID(for: source, frame: 0, salt: "#concatenation")
            : UIDGenerator.generateUID().value
        let vectorKind = plan.entry?.legacyVectors ?? (source[.frameIncrementPointer] != nil ? .cine : .none)

        if verbose {
            log(SplitConsole.concatenationPlanLine(parts: parts.count, framesPerInstance: framesPerInstance))
        }

        for part in parts {
            do {
                var ds = MultiframeConcatenation.partDataSet(source: source, part: part,
                                                             concatenationUID: concatenationUID, vectorKind: vectorKind)
                var fileMeta = dicomFile.fileMetaInformation

                let payloads = try part.frames.map {
                    try MultiframePixelAssembler.extractFrame(from: dicomFile, frame: $0, handling: options.pixelHandling)
                }
                let assembled = try MultiframePixelAssembler.assemble(payloads)
                ds[.pixelData] = assembled.element
                MultiframePixelAssembler.applyPixelDescription(payloads[0], to: &ds, fileMeta: &fileMeta)

                let sopUID = sopInstanceUID(for: source, frame: part.index, salt: "#part")
                ds.setString(sopUID, for: .sopInstanceUID, vr: .UI)
                fileMeta.setString(sopUID, for: .mediaStorageSOPInstanceUID, vr: .UI)
                ds.setString(String(part.index + 1), for: .instanceNumber, vr: .IS)

                let baseName = (originalPath as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "part"
                let filename: String
                if let pattern = namingPattern {
                    filename = Self.expandPattern(pattern, frameIndex: part.index, instance: String(part.index + 1), stack: "1",
                                                  modality: source.string(for: .modality) ?? Modality.ot.rawValue,
                                                  series: source.string(for: .seriesNumber) ?? "0")
                } else {
                    filename = "\(baseName)_part_\(String(format: "%04d", part.index + 1)).dcm"
                }
                let outputFilePath = (outputPath as NSString).appendingPathComponent(filename)
                try DICOMFile(fileMetaInformation: fileMeta, dataSet: ds).write().write(to: URL(fileURLWithPath: outputFilePath))

                result.extracted += 1
                result.writtenPaths.append(outputFilePath)
                if verbose {
                    log("  Extracted part \(part.index + 1)/\(part.total) (frames \(part.frames.lowerBound)-\(part.frames.upperBound - 1)) -> \(filename)")
                }
            } catch {
                result.failed += 1
                if verbose {
                    log("  Failed to write part \(part.index + 1): \(error)")
                }
            }
        }
    }

    /// Extracts a frame as an image file (PNG, JPEG, TIFF).
    private func extractFrameAsImage(
        from dicomFile: DICOMFile,
        frameIndex: Int,
        outputPath: String
    ) throws {
        #if canImport(CoreGraphics)
        // Decode only this frame (not the whole multi-frame buffer per output).
        guard let pixelData = try? dicomFile.pixelData(frame: frameIndex) else {
            throw SplitError.renderingFailed(frameIndex: frameIndex)
        }
        let renderer = PixelDataRenderer(pixelData: pixelData, paletteColorLUT: dicomFile.dataSet.paletteColorLUT())
        let image: CGImage?

        if applyWindow, let center = windowCenter, let width = windowWidth {
            image = render(renderer, pixelData: pixelData, window: WindowSettings(center: center, width: width))
        } else if applyWindow {
            // Stored window: the frame's own VOI (functional groups) beats the top level.
            let frameDS = FunctionalGroupFlattener.flatten(dicomFile.dataSet, frameIndex: frameIndex, toClassic: false)
            if let window = frameDS.windowSettings() {
                image = render(renderer, pixelData: pixelData, window: window)
            } else {
                image = renderer.renderFrame(0)
            }
        } else {
            image = renderer.renderFrame(0)
        }

        guard let cgImage = image else {
            throw SplitError.renderingFailed(frameIndex: frameIndex)
        }

        try writeImage(cgImage, to: outputPath, format: format)
        #else
        throw SplitError.imageWriteFailed(path: "Image export not supported on this platform")
        #endif
    }

    #if canImport(CoreGraphics)
    private func render(_ renderer: PixelDataRenderer, pixelData: PixelData, window: WindowSettings) -> CGImage? {
        if pixelData.descriptor.photometricInterpretation.isMonochrome {
            return renderer.renderMonochromeFrame(0, window: window)
        } else if pixelData.descriptor.photometricInterpretation.isPaletteColor {
            return renderer.renderPaletteColorFrame(0)
        } else {
            return renderer.renderColorFrame(0)
        }
    }
    #endif

    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    /// Writes a CGImage to disk in the specified format.
    private func writeImage(_ image: CGImage, to path: String, format: SplitOutputFormat) throws {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw SplitError.imageWriteFailed(path: path)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw SplitError.imageWriteFailed(path: path)
        }
    }
    #endif

    // MARK: - Naming

    /// Generates output filename based on pattern or defaults.
    ///
    /// Pattern variables: `{number}` / `{number:04d}` (0-based frame index),
    /// `{instance}` (assigned Instance Number), `{stack}`, `{modality}`, `{series}`.
    private func generateFilename(
        frameIndex: Int,
        totalFrames: Int,
        originalPath: String,
        dicomFile: DICOMFile,
        plan: SplitPlan
    ) -> String {
        let baseName = (originalPath as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "frame"
        // "XX" is not a DICOM code; OT (Other) is the standard unknown.
        let modality = dicomFile.dataSet.string(for: .modality) ?? Modality.ot.rawValue
        let seriesNumber = dicomFile.dataSet.string(for: .seriesNumber) ?? "0"

        if let pattern = namingPattern {
            let instance = plan.instanceNumbers[frameIndex]
                ?? dicomFile.dataSet.string(for: .instanceNumber)?.trimmingCharacters(in: .whitespaces) ?? "0"
            let stack = plan.frameInfos[frameIndex].stackID ?? "1"
            return Self.expandPattern(pattern, frameIndex: frameIndex, instance: instance,
                                      stack: stack, modality: modality, series: seriesNumber)
        } else {
            let ext = format.fileExtension
            return "\(baseName)_frame_\(String(format: "%04d", frameIndex)).\(ext)"
        }
    }

    /// Substitutes the naming-pattern variables, including the `{number:0Nd}`
    /// width spec the help text has always advertised.
    public static func expandPattern(
        _ pattern: String,
        frameIndex: Int,
        instance: String,
        stack: String,
        modality: String,
        series: String
    ) -> String {
        var filename = pattern
        if let regex = try? NSRegularExpression(pattern: #"\{number(?::0?(\d+)d)?\}"#) {
            let ns = filename as NSString
            var out = ""
            var last = 0
            for match in regex.matches(in: filename, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                var width = 4
                if match.range(at: 1).location != NSNotFound,
                   let w = Int(ns.substring(with: match.range(at: 1))) {
                    width = w
                }
                out += String(format: "%0\(width)d", frameIndex)
                last = match.range.location + match.range.length
            }
            out += ns.substring(from: last)
            filename = out
        }
        filename = filename.replacingOccurrences(of: "{instance}", with: instance)
        filename = filename.replacingOccurrences(of: "{stack}", with: stack)
        filename = filename.replacingOccurrences(of: "{modality}", with: modality.trimmingCharacters(in: .whitespaces))
        filename = filename.replacingOccurrences(of: "{series}", with: series.trimmingCharacters(in: .whitespaces))
        return filename
    }

    // MARK: - Input gathering

    /// Gathers DICOM files from a directory.
    private func gatherFiles(from path: String, recursive: Bool) throws -> [String] {
        var files: [String] = []

        if recursive {
            // Recursive directory scan
            guard let enumerator = fileManager.enumerator(atPath: path) else {
                throw SplitError.directoryAccessFailed(path: path)
            }

            for case let item as String in enumerator {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   !isDirectory.boolValue,
                   isDICOMFile(fullPath) {
                    files.append(fullPath)
                }
            }
        } else {
            // Only direct children
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   !isDirectory.boolValue,
                   isDICOMFile(fullPath) {
                    files.append(fullPath)
                }
            }
        }

        return files.sorted()
    }

    /// Checks if a file is a DICOM file.
    private func isDICOMFile(_ path: String) -> Bool {
        // Check file extension
        let ext = (path as NSString).pathExtension.lowercased()
        if ["dcm", "dicom", "dic"].contains(ext) {
            return true
        }

        // Check for DICM magic bytes
        guard let fileHandle = FileHandle(forReadingAtPath: path),
              let data = try? fileHandle.read(upToCount: 132) else {
            return false
        }

        // DICOM files have "DICM" at byte 128
        if data.count >= 132 {
            let magic = data[128..<132]
            return magic == Data([0x44, 0x49, 0x43, 0x4D]) // "DICM"
        }

        return false
    }
}

// MARK: - Errors

public enum SplitError: Error, CustomStringConvertible {
    case missingPixelData
    case frameExtractionFailed(frameIndex: Int)
    case renderingFailed(frameIndex: Int)
    case imageWriteFailed(path: String)
    case directoryAccessFailed(path: String)
    case unsupportedSOPClass(name: String, reason: String)
    case noClassicCounterpart(name: String)

    public var description: String {
        switch self {
        case .missingPixelData:
            return "Missing pixel data in DICOM file"
        case .frameExtractionFailed(let frameIndex):
            return "Failed to extract Frame number \(frameIndex + 1)"
        case .renderingFailed(let frameIndex):
            return "Failed to render Frame number \(frameIndex + 1) as image"
        case .imageWriteFailed(let path):
            return "Failed to write image to \(path)"
        case .directoryAccessFailed(let path):
            return "Failed to access directory: \(path)"
        case .unsupportedSOPClass(let name, let reason):
            return "Cannot split \(name): \(reason)"
        case .noClassicCounterpart(let name):
            return "\(name) has no classic single-frame SOP Class (use --target auto or same)"
        }
    }
}

// MARK: - Output Format Extensions

extension SplitOutputFormat {
    var fileExtension: String {
        switch self {
        case .dicom:
            return "dcm"
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }

    #if canImport(UniformTypeIdentifiers)
    var utType: UTType {
        switch self {
        case .dicom:
            return .data
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        case .tiff:
            return .tiff
        }
    }
    #endif
}
