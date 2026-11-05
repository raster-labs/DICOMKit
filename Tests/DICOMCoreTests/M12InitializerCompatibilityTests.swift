import Foundation
import XCTest
import DICOMCore
import DICOMKit

final class M12InitializerCompatibilityTests: XCTestCase {
    func testOriginalInitializerReferencesBindWithTheirOriginalTypes() {
        let manager: () -> CompressionManager = CompressionManager.init
        let converter: (TranscodingConfiguration, CompressionConfiguration) -> TransferSyntaxConverter =
            TransferSyntaxConverter.init(configuration:compressionConfiguration:)
        let configuration: ([TransferSyntax], Bool, Bool) -> TranscodingConfiguration =
            TranscodingConfiguration.init(preferredSyntaxes:allowLossyCompression:preservePixelDataFidelity:)
        let result: (Data, TransferSyntax, TransferSyntax, Bool, Bool) -> TranscodingResult =
            TranscodingResult.init(data:sourceTransferSyntax:targetTransferSyntax:wasTranscoded:isLossless:)
        let metrics: (Int, Int, Bool, String?, Int?, TimeInterval?, TimeInterval) -> CompressionManager.CompressMetrics =
            CompressionManager.CompressMetrics.init(inputSize:outputSize:isRecompression:sourceTransferSyntaxName:intermediateSize:decompressElapsed:compressElapsed:)

        let policy = configuration([.jpeg2000Lossless], false, true)
        XCTAssertFalse(policy.allowBitDepthReductionTo8Bit)
        XCTAssertEqual(manager().codecRegistry.j2kProvider.providerID, .j2kSwift)
        XCTAssertEqual(converter(policy, .lossless).codecRegistry.j2kProvider.providerID, .j2kSwift)
        XCTAssertNil(result(Data(), .jpeg2000Lossless, .explicitVRLittleEndian, true, true).resolvedDecodeProviderID)
        XCTAssertNil(metrics(1, 2, false, nil, nil, nil, 0).resolvedEncodeProviderID)
    }
}
