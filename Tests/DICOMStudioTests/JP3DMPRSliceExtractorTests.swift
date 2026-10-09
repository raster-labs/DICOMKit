// JP3DMPRSliceExtractorTests.swift
// DICOMStudioTests
//
// Tests for JP3DMPRSliceExtractor and JP3DMPRRenderHelpers.

import Testing
@testable import DICOMStudio
import DICOMKit
import DICOMCore
import Foundation

// MARK: - Test Volume Factory

/// Creates a minimal DICOMVolume for testing.
///
/// The volume is W×H×D with 16-bit unsigned voxels.
/// Voxel value at (x, y, z) = z * 1000 + y * 100 + x
/// (encoded as little-endian UInt16).
private func makeTestVolume(
    width: Int = 4,
    height: Int = 3,
    depth: Int = 2,
    bitsAllocated: Int = 16
) -> DICOMVolume {
    let bytesPerVoxel = bitsAllocated / 8
    var pixels = Data(count: width * height * depth * bytesPerVoxel)
    for z in 0..<depth {
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt16(z * 1000 + y * 100 + x)
                let offset = (z * height * width + y * width + x) * bytesPerVoxel
                pixels[offset]     = UInt8(value & 0xFF)
                pixels[offset + 1] = UInt8((value >> 8) & 0xFF)
            }
        }
    }
    return DICOMVolume(
        width: width,
        height: height,
        depth: depth,
        bitsAllocated: bitsAllocated,
        bitsStored: bitsAllocated,
        isSigned: false,
        spacingX: 1.0,
        spacingY: 2.0,
        spacingZ: 3.0,
        pixelData: pixels
    )
}

/// Creates a minimal 8-bit volume for simpler byte arithmetic in tests.
private func makeVolume8(
    width: Int = 4,
    height: Int = 3,
    depth: Int = 2
) -> DICOMVolume {
    var pixels = Data(count: width * height * depth)
    for z in 0..<depth {
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8((z * height * width + y * width + x) % 256)
                pixels[z * height * width + y * width + x] = value
            }
        }
    }
    return DICOMVolume(
        width: width,
        height: height,
        depth: depth,
        bitsAllocated: 8,
        bitsStored: 8,
        isSigned: false,
        spacingX: 0.5,
        spacingY: 0.5,
        spacingZ: 1.0,
        pixelData: pixels
    )
}

// MARK: - dimensionsModel Tests

@Suite("JP3DMPRSliceExtractor.dimensionsModel")
struct JP3DMPRDimensionsModelTests {

    @Test("Width, height, depth match volume")
    func testDimensionsMatchVolume() {
        let vol = makeTestVolume(width: 10, height: 8, depth: 6)
        let dims = JP3DMPRSliceExtractor.dimensionsModel(for: vol)
        #expect(dims.width == 10)
        #expect(dims.height == 8)
        #expect(dims.depth == 6)
    }

    @Test("Spacing matches volume")
    func testSpacingMatchesVolume() {
        let vol = makeTestVolume()
        let dims = JP3DMPRSliceExtractor.dimensionsModel(for: vol)
        #expect(dims.spacingX == 1.0)
        #expect(dims.spacingY == 2.0)
        #expect(dims.spacingZ == 3.0)
    }
}

// MARK: - sliceRange Tests

@Suite("JP3DMPRSliceExtractor.sliceRange")
struct JP3DMPRSliceRangeTests {

    @Test("Axial range is 0...depth-1")
    func testAxialRange() {
        let vol = makeTestVolume(width: 4, height: 3, depth: 5)
        let range = JP3DMPRSliceExtractor.sliceRange(for: .axial, in: vol)
        #expect(range == 0...4)
    }

    @Test("Sagittal range is 0...width-1")
    func testSagittalRange() {
        let vol = makeTestVolume(width: 7, height: 3, depth: 2)
        let range = JP3DMPRSliceExtractor.sliceRange(for: .sagittal, in: vol)
        #expect(range == 0...6)
    }

    @Test("Coronal range is 0...height-1")
    func testCoronalRange() {
        let vol = makeTestVolume(width: 4, height: 9, depth: 2)
        let range = JP3DMPRSliceExtractor.sliceRange(for: .coronal, in: vol)
        #expect(range == 0...8)
    }

    @Test("Minimum range for 1-deep volume")
    func testMinimumRange() {
        let vol = makeTestVolume(width: 1, height: 1, depth: 1)
        #expect(JP3DMPRSliceExtractor.sliceRange(for: .axial, in: vol) == 0...0)
    }
}

// MARK: - Axial Slice Tests

@Suite("JP3DMPRSliceExtractor axial")
struct JP3DMPRAxialTests {

    @Test("Returns nil for out-of-range index")
    func testOutOfRange() {
        let vol = makeTestVolume()
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: -1) == nil)
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 2) == nil)
    }

    @Test("Axial slice has correct dimensions")
    func testAxialDimensions() {
        let vol = makeTestVolume(width: 6, height: 5, depth: 4)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 0)
        #expect(slice != nil)
        #expect(slice?.pixelWidth == 6)
        #expect(slice?.pixelHeight == 5)
    }

    @Test("Axial slice has correct spacing")
    func testAxialSpacing() {
        let vol = makeTestVolume()
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 0)
        #expect(slice?.spacingX == 1.0)
        #expect(slice?.spacingY == 2.0)
    }

    @Test("Axial slice data size is width * height * bytesPerVoxel")
    func testAxialDataSize() {
        let vol = makeTestVolume(width: 4, height: 3, depth: 2)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 0)
        #expect(slice?.data.count == 4 * 3 * 2)
    }

    @Test("Axial slice data matches expected voxel values")
    func testAxialVoxelValues() {
        // 8-bit volume: voxel(x,y,z) = z*H*W + y*W + x
        let vol = makeVolume8(width: 4, height: 3, depth: 2)
        // axial z=0: bytes [0, 1, 2, 3,  4, 5, 6, 7,  8, 9, 10, 11]
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 0)
        #expect(slice != nil)
        let data = slice!.data
        // Row 0
        #expect(data[0] == 0)
        #expect(data[1] == 1)
        #expect(data[3] == 3)
        // Row 1
        #expect(data[4] == 4)
        #expect(data[7] == 7)
        // Row 2
        #expect(data[8] == 8)
    }

    @Test("Second axial slice voxels correctly offset")
    func testAxialSlice1() {
        let vol = makeVolume8(width: 4, height: 3, depth: 2)
        // axial z=1: bytes [12, 13, 14, 15, ...]
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .axial, at: 1)
        #expect(slice != nil)
        #expect(slice!.data[0] == 12)
        #expect(slice!.data[11] == 23)
    }
}

// MARK: - Sagittal Slice Tests

@Suite("JP3DMPRSliceExtractor sagittal")
struct JP3DMPRSagittalTests {

    @Test("Returns nil for out-of-range index")
    func testOutOfRange() {
        let vol = makeTestVolume()
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: -1) == nil)
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: 4) == nil)
    }

    @Test("Sagittal slice has correct dimensions")
    func testSagittalDimensions() {
        // sagittal: width=H, height=D
        let vol = makeTestVolume(width: 4, height: 5, depth: 6)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: 0)
        #expect(slice?.pixelWidth == 5)   // height of volume
        #expect(slice?.pixelHeight == 6)  // depth of volume
    }

    @Test("Sagittal slice spacing: x=spacingY, y=spacingZ")
    func testSagittalSpacing() {
        let vol = makeTestVolume()
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: 0)
        #expect(slice?.spacingX == 2.0)  // vol.spacingY
        #expect(slice?.spacingY == 3.0)  // vol.spacingZ
    }

    @Test("Sagittal slice data size is height * depth * bytesPerVoxel")
    func testSagittalDataSize() {
        let vol = makeTestVolume(width: 4, height: 3, depth: 2)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: 0)
        #expect(slice?.data.count == 3 * 2 * 2)  // H*D*2bytes
    }

    @Test("Sagittal slice voxels match expected voxel(x0,y,z) values")
    func testSagittalVoxelValues() {
        // 8-bit volume: voxel(x,y,z) = z*H*W + y*W + x
        // sagittal x=2: for z in [0,1], y in [0,1,2]:
        //   row z=0: y=0→2, y=1→6, y=2→10
        //   row z=1: y=0→14, y=1→18, y=2→22
        let vol = makeVolume8(width: 4, height: 3, depth: 2)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .sagittal, at: 2)
        #expect(slice != nil)

        // dst layout: row z, col y → dst[z*sliceWidth + y]
        // sliceWidth = H = 3
        let data = slice!.data
        #expect(data[0] == 2)   // (x=2, y=0, z=0): 0*12 + 0*4 + 2 = 2
        #expect(data[1] == 6)   // (x=2, y=1, z=0): 0*12 + 1*4 + 2 = 6
        #expect(data[2] == 10)  // (x=2, y=2, z=0): 0*12 + 2*4 + 2 = 10
        #expect(data[3] == 14)  // (x=2, y=0, z=1): 1*12 + 0*4 + 2 = 14
        #expect(data[4] == 18)  // (x=2, y=1, z=1): 1*12 + 1*4 + 2 = 18
        #expect(data[5] == 22)  // (x=2, y=2, z=1): 1*12 + 2*4 + 2 = 22
    }
}

// MARK: - Coronal Slice Tests

@Suite("JP3DMPRSliceExtractor coronal")
struct JP3DMPRCoronalTests {

    @Test("Returns nil for out-of-range index")
    func testOutOfRange() {
        let vol = makeTestVolume()
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: -1) == nil)
        #expect(JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: 3) == nil)
    }

    @Test("Coronal slice has correct dimensions")
    func testCoronalDimensions() {
        // coronal: width=W, height=D
        let vol = makeTestVolume(width: 7, height: 5, depth: 4)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: 0)
        #expect(slice?.pixelWidth == 7)   // width of volume
        #expect(slice?.pixelHeight == 4)  // depth of volume
    }

    @Test("Coronal slice spacing: x=spacingX, y=spacingZ")
    func testCoronalSpacing() {
        let vol = makeTestVolume()
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: 0)
        #expect(slice?.spacingX == 1.0)  // vol.spacingX
        #expect(slice?.spacingY == 3.0)  // vol.spacingZ
    }

    @Test("Coronal slice data size is width * depth * bytesPerVoxel")
    func testCoronalDataSize() {
        let vol = makeTestVolume(width: 4, height: 3, depth: 2)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: 0)
        #expect(slice?.data.count == 4 * 2 * 2)  // W*D*2bytes
    }

    @Test("Coronal slice voxels match expected voxel(x,y0,z) values")
    func testCoronalVoxelValues() {
        // 8-bit volume: voxel(x,y,z) = z*H*W + y*W + x
        // coronal y=1: for z in [0,1], x in [0,1,2,3]:
        //   z=0: [0*12+1*4+0, ...+1, ...+2, ...+3] = [4, 5, 6, 7]
        //   z=1: [1*12+1*4+0, ...+1, ...+2, ...+3] = [16,17,18,19]
        let vol = makeVolume8(width: 4, height: 3, depth: 2)
        let slice = JP3DMPRSliceExtractor.extractSlice(from: vol, plane: .coronal, at: 1)
        #expect(slice != nil)

        let data = slice!.data
        // Row z=0: x=0..3
        #expect(data[0] == 4)
        #expect(data[1] == 5)
        #expect(data[2] == 6)
        #expect(data[3] == 7)
        // Row z=1: x=0..3
        #expect(data[4] == 16)
        #expect(data[5] == 17)
        #expect(data[6] == 18)
        #expect(data[7] == 19)
    }
}

// MARK: - Window/Level Tests

@Suite("JP3DMPRSliceExtractor.applyWindowLevel")
struct JP3DMPRWindowLevelTests {

    private func makeSlice(values: [UInt8]) -> JP3DMPRRawSlice {
        JP3DMPRRawSlice(
            pixelWidth: values.count,
            pixelHeight: 1,
            spacingX: 1.0,
            spacingY: 1.0,
            data: Data(values),
            bitsAllocated: 8,
            isSigned: false
        )
    }

    @Test("Full-range window maps 0→0 and 255→255")
    func testFullRange() {
        let slice = makeSlice(values: [0, 128, 255])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 127.5, windowWidth: 255)
        #expect(out[0] == 0)
        #expect(out[2] == 255)
    }

    @Test("Zero windowWidth returns mid-grey")
    func testZeroWindowWidth() {
        let slice = makeSlice(values: [0, 128, 255])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 128, windowWidth: 0)
        for byte in out {
            #expect(byte == 128)
        }
    }

    @Test("Values below lower bound clamp to 0")
    func testLowerClamp() {
        // window: center=200, width=100 → lower=150, upper=250
        let slice = makeSlice(values: [0, 100, 149])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 200, windowWidth: 100)
        #expect(out[0] == 0)
        #expect(out[1] == 0)
        #expect(out[2] == 0)
    }

    @Test("Values above upper bound clamp to 255")
    func testUpperClamp() {
        // window: center=200, width=100 → lower=150, upper=250
        let slice = makeSlice(values: [251, 255])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 200, windowWidth: 100)
        #expect(out[0] == 255)
        #expect(out[1] == 255)
    }

    @Test("The mapping is the PS3.3 C.11.2.1.2.1 default LINEAR function")
    func testLinearFunctionPerPS3_3() {
        // PS3.3 2026a C.11.2.1.2.1, c = 128, w = 101: x <= 128 - 0.5 - 50 = 77.5 → 0;
        // x > 128 - 0.5 + 50 = 177.5 → 255; x = 127.5 (the centre, c - 0.5) → 127.5 → 128;
        // x = 100 → ((100 - 127.5) / 100 + 0.5) * 255 = 57.375 → 57.
        let slice = makeSlice(values: [77, 78, 100, 127, 128, 177, 178])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 128, windowWidth: 101)
        #expect(out[0] == 0)
        #expect(out[1] == 1)    // ((78 - 127.5)/100 + 0.5) * 255 = 1.275
        #expect(out[2] == 57)
        #expect(out[3] == 126)  // ((127 - 127.5)/100 + 0.5) * 255 = 126.225
        #expect(out[4] == 129)  // ((128 - 127.5)/100 + 0.5) * 255 = 128.775
        #expect(out[5] == 254)  // ((177 - 127.5)/100 + 0.5) * 255 = 253.725
        #expect(out[6] == 255)
    }

    @Test("Width 1 is a threshold at c - 0.5, never a division by zero")
    func testWidthOneIsThreshold() {
        // PS3.3 2026a C.11.2.1.2.1: "the value of 1 for w does not cause division by zero".
        let slice = makeSlice(values: [99, 100, 101])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 100, windowWidth: 1)
        #expect(out[0] == 0)    // 99 <= 99.5
        #expect(out[1] == 255)  // 100 > 99.5
        #expect(out[2] == 255)
    }

    @Test("Output count equals pixel count")
    func testOutputCount() {
        let slice = makeSlice(values: [10, 20, 30, 40])
        let out = JP3DMPRSliceExtractor.applyWindowLevel(to: slice, windowCenter: 25, windowWidth: 50)
        #expect(out.count == 4)
    }
}

// MARK: - JP3DMPRRenderHelpers Tests

@Suite("JP3DMPRRenderHelpers")
struct JP3DMPRRenderHelpersTests {

    @Test("referenceLineRGB returns distinct colours for each plane")
    func testDistinctColours() {
        let axial    = JP3DMPRRenderHelpers.referenceLineRGB(for: .axial)
        let sagittal = JP3DMPRRenderHelpers.referenceLineRGB(for: .sagittal)
        let coronal  = JP3DMPRRenderHelpers.referenceLineRGB(for: .coronal)
        #expect(axial != sagittal)
        #expect(axial != coronal)
        #expect(sagittal != coronal)
    }

    @Test("referenceLineAxis: sagittal shown in axial is vertical")
    func testAxisSagittalInAxial() {
        let axis = JP3DMPRRenderHelpers.referenceLineAxis(referencePlane: .sagittal, displayPlane: .axial)
        #expect(axis == .vertical)
    }

    @Test("referenceLineAxis: coronal shown in axial is horizontal")
    func testAxisCoronalInAxial() {
        let axis = JP3DMPRRenderHelpers.referenceLineAxis(referencePlane: .coronal, displayPlane: .axial)
        #expect(axis == .horizontal)
    }

    @Test("referenceLineAxis: axial shown in sagittal is horizontal")
    func testAxisAxialInSagittal() {
        let axis = JP3DMPRRenderHelpers.referenceLineAxis(referencePlane: .axial, displayPlane: .sagittal)
        #expect(axis == .horizontal)
    }

    @Test("referenceLineAxis: sagittal shown in coronal is vertical")
    func testAxisSagittalInCoronal() {
        let axis = JP3DMPRRenderHelpers.referenceLineAxis(referencePlane: .sagittal, displayPlane: .coronal)
        #expect(axis == .vertical)
    }

    @Test("cgImage returns nil for zero-size buffer")
    func testCGImageNilForZeroSize() {
        let result = JP3DMPRRenderHelpers.cgImage(from: Data(), width: 0, height: 0)
        #expect(result == nil)
    }

    @Test("cgImage returns nil when buffer is too small")
    func testCGImageNilForSmallBuffer() {
        // 4×4=16 expected, only 8 bytes provided
        let result = JP3DMPRRenderHelpers.cgImage(from: Data(count: 8), width: 4, height: 4)
        #expect(result == nil)
    }

    @Test("cgImage returns non-nil for valid grayscale buffer")
    func testCGImageValidBuffer() {
        let buffer = Data(repeating: 128, count: 4 * 4)
        let result = JP3DMPRRenderHelpers.cgImage(from: buffer, width: 4, height: 4)
        #expect(result != nil)
    }

    @Test("cgImage dimensions match input")
    func testCGImageDimensions() {
        let buffer = Data(repeating: 200, count: 8 * 6)
        let img = JP3DMPRRenderHelpers.cgImage(from: buffer, width: 8, height: 6)
        #expect(img?.width == 8)
        #expect(img?.height == 6)
    }
}

// MARK: - JP3DMPRViewModel Tests

@Suite("JP3DMPRViewModel")
struct JP3DMPRViewModelTests {

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("Initial state: no volume, no buffers")
    func testInitialState() {
        let vm = JP3DMPRViewModel()
        #expect(vm.volume == nil)
        #expect(vm.dimensions == nil)
        #expect(vm.axialBuffer == nil)
        #expect(vm.sagittalBuffer == nil)
        #expect(vm.coronalBuffer == nil)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setVolume populates slice indices to centre")
    @MainActor
    func testSetVolumeIndex() {
        let vm = JP3DMPRViewModel()
        let vol = makeTestVolume(width: 10, height: 8, depth: 6)
        vm.setVolume(vol)
        #expect(vm.axialIndex == 3)    // depth/2 = 3
        #expect(vm.sagittalIndex == 5) // width/2 = 5
        #expect(vm.coronalIndex == 4)  // height/2 = 4
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setVolume populates all three buffers")
    @MainActor
    func testSetVolumeBuffers() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume())
        #expect(vm.axialBuffer != nil)
        #expect(vm.sagittalBuffer != nil)
        #expect(vm.coronalBuffer != nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setSliceIndex clamps to valid range")
    @MainActor
    func testSetSliceIndexClamping() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume(width: 4, height: 3, depth: 2))
        vm.setSliceIndex(-5, for: .axial)
        #expect(vm.axialIndex == 0)
        vm.setSliceIndex(999, for: .axial)
        #expect(vm.axialIndex == 1)  // max = depth-1 = 1
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("scroll increments and decrements slice index")
    @MainActor
    func testScroll() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume(width: 4, height: 3, depth: 5))
        vm.setSliceIndex(2, for: .axial)
        vm.scroll(delta: 1, in: .axial)
        #expect(vm.axialIndex == 3)
        vm.scroll(delta: -2, in: .axial)
        #expect(vm.axialIndex == 1)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setWindowLevel with valid width updates windowCenter and windowWidth")
    @MainActor
    func testSetWindowLevel() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume())
        vm.setWindowLevel(center: 100.0, width: 200.0)
        #expect(vm.windowCenter == 100.0)
        #expect(vm.windowWidth == 200.0)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setWindowLevel with zero width is ignored")
    @MainActor
    func testSetWindowLevelZeroWidth() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume())
        let originalCenter = vm.windowCenter
        let originalWidth = vm.windowWidth
        vm.setWindowLevel(center: 50.0, width: 0)
        #expect(vm.windowCenter == originalCenter)
        #expect(vm.windowWidth == originalWidth)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("setSliceIndex with no volume is a no-op")
    @MainActor
    func testSetSliceIndexNoVolume() {
        let vm = JP3DMPRViewModel()
        vm.setSliceIndex(5, for: .axial)
        #expect(vm.axialIndex == 0)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("handleClick without linking does not update indices")
    @MainActor
    func testHandleClickNoLinking() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume(width: 10, height: 8, depth: 6))
        vm.crosshairLinkingEnabled = false
        let beforeAxial = vm.axialIndex
        vm.handleClick(x: 5, y: 5, in: .axial)
        #expect(vm.axialIndex == beforeAxial)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("referenceLinePosition returns nil when no volume")
    @MainActor
    func testRefLineNoVolume() {
        let vm = JP3DMPRViewModel()
        let result = vm.referenceLinePosition(referencePlane: .axial, displayPlane: .sagittal)
        #expect(result == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("referenceLinePosition returns nil when reference lines hidden")
    @MainActor
    func testRefLineHidden() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume())
        vm.showReferenceLines = false
        let result = vm.referenceLinePosition(referencePlane: .axial, displayPlane: .sagittal)
        #expect(result == nil)
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("referenceLinePosition returns value in [0,1] when enabled")
    @MainActor
    func testRefLineInRange() {
        let vm = JP3DMPRViewModel()
        vm.setVolume(makeTestVolume(width: 4, height: 3, depth: 5))
        vm.showReferenceLines = true
        let result = vm.referenceLinePosition(referencePlane: .axial, displayPlane: .sagittal)
        if let t = result {
            #expect(t >= 0.0)
            #expect(t <= 1.0)
        }
    }
}

// MARK: - MONOCHROME1 display (PS3.3 C.7.6.3.1.2)

@Suite("MONOCHROME1 volume display")
struct Monochrome1VolumeDisplayTests {

    /// 2x1x1, 8-bit: stored values 0 and 255.
    private func volume(_ photometric: PhotometricInterpretation) -> DICOMVolume {
        DICOMVolume(width: 2, height: 1, depth: 1, bitsAllocated: 8, bitsStored: 8,
                    photometricInterpretation: photometric, pixelData: Data([0, 255]))
    }

    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    @Test("MPR buffer of a MONOCHROME1 volume shows the minimum as white, after windowing")
    @MainActor
    func mprBufferInverted() {
        let mono2 = JP3DMPRViewModel()
        mono2.setVolume(volume(.monochrome2))
        mono2.setWindowLevel(center: 127.5, width: 255)
        let mono1 = JP3DMPRViewModel()
        mono1.setVolume(volume(.monochrome1))
        mono1.setWindowLevel(center: 127.5, width: 255)
        #expect(mono2.axialBuffer.map { Array($0) } == [0, 255])
        #expect(mono1.axialBuffer.map { Array($0) } == [255, 0])
    }

    @Test("thick-slab projection of a MONOCHROME1 volume is inverted after projection")
    func thickSlabInverted() {
        let v1 = volume(.monochrome1)
        let dims = JP3DMPRSliceExtractor.dimensionsModel(for: v1)
        let out = EnterpriseRenderHelpers.thickSlabBuffer(
            volume: v1, plane: .axial, centerIndex: 0, slabThicknessMM: 1,
            projectionMode: .mip, windowCenter: 127.5, windowWidth: 255, dimensions: dims)
        #expect(out.map { Array($0) } == [255, 0])
        let v2 = volume(.monochrome2)
        let out2 = EnterpriseRenderHelpers.thickSlabBuffer(
            volume: v2, plane: .axial, centerIndex: 0, slabThicknessMM: 1,
            projectionMode: .mip, windowCenter: 127.5, windowWidth: 255, dimensions: dims)
        #expect(out2.map { Array($0) } == [0, 255])
    }
}
