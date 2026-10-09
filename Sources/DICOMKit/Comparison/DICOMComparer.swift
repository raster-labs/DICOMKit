// NEMA-verified: 2026a, checked 2026-10-01 — Pixel Data compared per Pixel Sample Value (Bits Allocated / Bits Stored / High Bit / Pixel Representation, PS3.5 2026a 8.1.1; Planar Configuration, PS3.3 C.7.6.3.1.3; encapsulated data decoded, PS3.5 8.2) (D153); --ignore-private applies inside Sequence Items (PS3.5 7.8, D152)
import Foundation
import DICOMCore
import DICOMDictionary

/// Compares two DICOM files and reports metadata (and optionally pixel-data)
/// differences.
///
/// Lives in the DICOMKit library so the `dicom-diff` CLI and DICOMStudio run the
/// exact same comparison code and cannot drift. Rendering is handled separately
/// by ``ComparisonReport``.
public struct DICOMComparer {
    public let file1: DICOMFile
    public let file2: DICOMFile
    public let tagsToIgnore: Set<Tag>
    public let ignorePrivate: Bool
    public let comparePixels: Bool
    public let pixelTolerance: Double
    public let showIdentical: Bool

    public init(
        file1: DICOMFile,
        file2: DICOMFile,
        tagsToIgnore: Set<Tag>,
        ignorePrivate: Bool,
        comparePixels: Bool,
        pixelTolerance: Double,
        showIdentical: Bool
    ) {
        self.file1 = file1
        self.file2 = file2
        self.tagsToIgnore = tagsToIgnore
        self.ignorePrivate = ignorePrivate
        self.comparePixels = comparePixels
        self.pixelTolerance = pixelTolerance
        self.showIdentical = showIdentical
    }

    public func compare() throws -> ComparisonResult {
        var result = ComparisonResult()

        let dataSet1 = file1.dataSet
        let dataSet2 = file2.dataSet

        // Build element dictionaries for result
        for tag in dataSet1.tags {
            if let element = dataSet1[tag] {
                result.file1Data[tag] = element
            }
        }
        for tag in dataSet2.tags {
            if let element = dataSet2[tag] {
                result.file2Data[tag] = element
            }
        }

        let allTags = Set(dataSet1.tags).union(Set(dataSet2.tags))

        for tag in allTags {
            // Skip ignored tags
            if tagsToIgnore.contains(tag) {
                continue
            }

            // Skip private tags if requested
            if ignorePrivate && tag.isPrivate {
                continue
            }

            // Skip pixel data tag (handled separately)
            if comparePixels && tag == Tag.pixelData {
                continue
            }

            result.totalTags += 1

            let elem1 = dataSet1[tag]
            let elem2 = dataSet2[tag]

            switch (elem1, elem2) {
            case (nil, let elem2?):
                result.onlyInFile2[tag] = elem2
                result.differenceCount += 1

            case (let elem1?, nil):
                result.onlyInFile1[tag] = elem1
                result.differenceCount += 1

            case (let elem1?, let elem2?):
                if !areElementsEqual(elem1, elem2) {
                    result.modified.append(TagModification(tag: tag, value1: elem1, value2: elem2))
                    result.differenceCount += 1
                } else {
                    result.identical.insert(tag)
                }

            case (nil, nil):
                break
            }
        }

        // Compare pixel data if requested
        if comparePixels {
            result.pixelsCompared = true
            if let pixelDiff = try comparePixelData(dataSet1, dataSet2) {
                result.pixelsDifferent = pixelDiff.maxDifference > pixelTolerance
                result.pixelDifference = pixelDiff
            }
        }

        return result
    }

    private func areElementsEqual(_ elem1: DataElement, _ elem2: DataElement) -> Bool {
        // VR must match
        if elem1.vr != elem2.vr {
            return false
        }

        // For sequences, compare recursively
        if elem1.vr == .SQ {
            guard let seq1 = elem1.sequenceItems,
                  let seq2 = elem2.sequenceItems,
                  seq1.count == seq2.count else {
                return false
            }

            for (item1, item2) in zip(seq1, seq2) {
                if !areSequenceItemsEqual(item1, item2) {
                    return false
                }
            }

            return true
        }

        // Compare data
        return elem1.valueData == elem2.valueData
    }

    private func areSequenceItemsEqual(_ item1: SequenceItem, _ item2: SequenceItem) -> Bool {
        // --ignore-private applies at every nesting level: Private Data Elements (and
        // their Private Creators) inside Items are skipped too (PS3.5 7.8, D152).
        let tags1 = Set(item1.elements.keys.filter { !(ignorePrivate && $0.isPrivate) })
        let tags2 = Set(item2.elements.keys.filter { !(ignorePrivate && $0.isPrivate) })

        guard tags1 == tags2 else {
            return false
        }

        for tag in tags1 {
            guard let elem1 = item1.elements[tag],
                  let elem2 = item2.elements[tag],
                  areElementsEqual(elem1, elem2) else {
                return false
            }
        }

        return true
    }

    /// Compares Pixel Data sample by sample (D153).
    ///
    /// Both files are decoded (`DICOMFile.pixelData()`, which decompresses encapsulated
    /// Pixel Data, PS3.5 8.2 / A.4) and each Pixel Sample Value is read from its Pixel
    /// Cell per Bits Allocated, Bits Stored, High Bit and Pixel Representation (PS3.5
    /// 2026a 8.1.1), in frame / pixel / sample order whatever the Planar Configuration
    /// (PS3.3 C.7.6.3.1.3). `--tolerance`, the maximum and the mean are in sample values;
    /// "Different pixels" counts the pixels with at least one differing sample. When
    /// either file cannot be decoded the raw Pixel Data bytes are compared as before.
    private func comparePixelData(_ ds1: DataSet, _ ds2: DataSet) throws -> PixelDifference? {
        guard let pixelElem1 = ds1[Tag.pixelData],
              let pixelElem2 = ds2[Tag.pixelData] else {
            return nil
        }
        if let pixels1 = file1.pixelData(), let pixels2 = file2.pixelData(),
           let samples1 = SampleReader(pixels1), let samples2 = SampleReader(pixels2) {
            return Self.compareSamples(samples1, samples2)
        }
        return Self.compareBytes(pixelElem1.valueData, pixelElem2.valueData)
    }

    /// Per-sample statistics over two decoded images.
    static func compareSamples(_ a: SampleReader, _ b: SampleReader) -> PixelDifference {
        let common = min(a.pixelCount, b.pixelCount)
        let commonSpp = min(a.samplesPerPixel, b.samplesPerPixel)
        var maxDiff: Double = 0
        var totalDiff: Double = 0
        var diffSamples = 0
        var diffPixels = 0
        for pixel in 0..<common {
            var pixelDiffers = a.samplesPerPixel != b.samplesPerPixel
            for sample in 0..<commonSpp {
                let diff = abs(Double(a.value(pixel: pixel, sample: sample)) - Double(b.value(pixel: pixel, sample: sample)))
                if diff > 0 {
                    maxDiff = max(maxDiff, diff)
                    totalDiff += diff
                    diffSamples += 1
                    pixelDiffers = true
                }
            }
            if pixelDiffers { diffPixels += 1 }
        }
        // Pixels present in one image only are different.
        let total = max(a.pixelCount, b.pixelCount)
        diffPixels += total - common
        return PixelDifference(
            maxDifference: maxDiff,
            meanDifference: diffSamples > 0 ? totalDiff / Double(diffSamples) : 0,
            differentPixelCount: diffPixels,
            totalPixels: total
        )
    }

    /// The pre-D153 byte comparison, kept for Pixel Data that cannot be decoded.
    static func compareBytes(_ pixelData1: Data, _ pixelData2: Data) -> PixelDifference {
        let bytes1 = [UInt8](pixelData1), bytes2 = [UInt8](pixelData2)
        let minLength = min(bytes1.count, bytes2.count)
        var maxDiff: Double = 0
        var totalDiff: Double = 0
        var diffCount = 0
        for i in 0..<minLength {
            let diff = abs(Double(bytes1[i]) - Double(bytes2[i]))
            if diff > 0 {
                maxDiff = max(maxDiff, diff)
                totalDiff += diff
                diffCount += 1
            }
        }
        let meanDiff = diffCount > 0 ? totalDiff / Double(diffCount) : 0
        diffCount += abs(bytes1.count - bytes2.count)
        return PixelDifference(
            maxDifference: maxDiff,
            meanDifference: meanDiff,
            differentPixelCount: diffCount,
            totalPixels: max(bytes1.count, bytes2.count)
        )
    }

    /// Reads Pixel Sample Values out of native (decoded) Pixel Data.
    struct SampleReader {
        let bytes: [UInt8]
        let descriptor: PixelDataDescriptor
        let pixelCount: Int
        var samplesPerPixel: Int { descriptor.samplesPerPixel }

        init?(_ pixels: PixelData) {
            let d = pixels.descriptor
            guard [1, 8, 16, 32].contains(d.bitsAllocated), d.samplesPerPixel >= 1,
                  d.bitsStored >= 1, d.bitsStored <= d.bitsAllocated,
                  d.rows > 0, d.columns > 0 else { return nil }
            let bytes = [UInt8](pixels.data)
            let samples = d.pixelsPerFrame * d.numberOfFrames * d.samplesPerPixel
            let needed = d.bitsAllocated == 1 ? (samples + 7) / 8 : samples * d.bytesPerSample
            guard bytes.count >= needed else { return nil }
            self.bytes = bytes
            self.descriptor = d
            self.pixelCount = d.pixelsPerFrame * d.numberOfFrames
        }

        /// The Pixel Sample Value of `sample` of pixel `pixel` (frames concatenated).
        func value(pixel: Int, sample: Int) -> Int {
            let d = descriptor
            let frame = pixel / d.pixelsPerFrame
            let inFrame = pixel % d.pixelsPerFrame
            // Index of the sample in Pixel Data order (PS3.3 C.7.6.3.1.3).
            let samplesPerFrame = d.pixelsPerFrame * d.samplesPerPixel
            let index = frame * samplesPerFrame + (d.planarConfiguration == 1
                ? sample * d.pixelsPerFrame + inFrame
                : inFrame * d.samplesPerPixel + sample)
            if d.bitsAllocated == 1 {
                // PS3.5 8.1.1 / D.1: single-bit cells packed from the least significant bit.
                return Int((bytes[index / 8] >> UInt8(index % 8)) & 1)
            }
            let offset = index * d.bytesPerSample
            let cell = bytes.withUnsafeBytes { d.cellValue(in: $0, at: offset) }
            return d.storedValue(fromCell: cell)
        }
    }
}

// MARK: - Results

/// The outcome of a ``DICOMComparer`` run.
public struct ComparisonResult {
    public var totalTags: Int = 0
    public var differenceCount: Int = 0
    public var onlyInFile1: [Tag: DataElement] = [:]
    public var onlyInFile2: [Tag: DataElement] = [:]
    public var modified: [TagModification] = []
    public var identical: Set<Tag> = []
    public var pixelsCompared: Bool = false
    public var pixelsDifferent: Bool = false
    public var pixelDifference: PixelDifference?

    // Full element maps, kept for detailed output.
    public var file1Data: [Tag: DataElement] = [:]
    public var file2Data: [Tag: DataElement] = [:]

    public var hasDifferences: Bool {
        return differenceCount > 0 || pixelsDifferent
    }

    public init() {}
}

/// A tag whose value differs between the two files.
public struct TagModification {
    public let tag: Tag
    public let value1: DataElement
    public let value2: DataElement

    public init(tag: Tag, value1: DataElement, value2: DataElement) {
        self.tag = tag
        self.value1 = value1
        self.value2 = value2
    }
}

/// Pixel-data difference statistics.
public struct PixelDifference {
    public let maxDifference: Double
    public let meanDifference: Double
    public let differentPixelCount: Int
    public let totalPixels: Int

    public init(maxDifference: Double, meanDifference: Double, differentPixelCount: Int, totalPixels: Int) {
        self.maxDifference = maxDifference
        self.meanDifference = meanDifference
        self.differentPixelCount = differentPixelCount
        self.totalPixels = totalPixels
    }
}
