//
// PrintSCPIntegrationTests.swift
// DICOMNetworkTests
//
// End-to-end Print SCU workflow tests against the in-process MockPrintSCP
// (enhancement plan Milestone D — the previously blocked test-matrix rows).
//

import XCTest
import DICOMCore
@testable import DICOMNetwork

#if canImport(Network)

final class PrintSCPIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfiguration(port: UInt16, timeout: TimeInterval = 10) -> PrintConfiguration {
        PrintConfiguration(
            host: "127.0.0.1",
            port: port,
            callingAETitle: "TEST_SCU",
            calledAETitle: "MOCK_SCP",
            timeout: timeout
        )
    }

    /// A tiny 2×2 8-bit MONOCHROME2 image + matching descriptor.
    private func makeImage() -> (Data, PrintImageData) {
        let pixels = Data([0, 64, 128, 255])
        let descriptor = PrintImageData(
            pixelData: pixels,
            rows: 2, columns: 2,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            samplesPerPixel: 1, pixelRepresentation: 0,
            photometricInterpretation: "MONOCHROME2"
        )
        return (pixels, descriptor)
    }

    // MARK: - Happy path

    func testHappyPathSingleAssociation() async throws {
        let scp = MockPrintSCP()
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels],
            imageDescriptors: [descriptor]
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.printJobUID, "1.2.826.0.1.3680043.9.9001.1.1")
        XCTAssertEqual(result.filmSessionUID, "1.2.826.0.1.3680043.9.9001.2.1")

        // PS3.4 H.4: the whole job must run on ONE association.
        let associations = await scp.associationCount
        XCTAssertEqual(associations, 1)
        let released = await scp.releasedCleanly
        XCTAssertTrue(released)

        // Full DIMSE sequence in order.
        let log = await scp.commandLog
        XCTAssertEqual(log, [
            .nCreateRequest,  // film session
            .nCreateRequest,  // film box
            .nSetRequest,     // image box
            .nActionRequest,  // print
            .nDeleteRequest   // cleanup
        ])
    }

    func testMultiFilmSingleAssociation() async throws {
        let scp = MockPrintSCP()
        try await scp.start()
        defer { Task { await scp.stop() } }

        // 3 images on a 2×1 layout → 2 film boxes, still one association.
        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels, pixels, pixels],
            imageDescriptors: [descriptor, descriptor, descriptor],
            layout: PrintLayout(rows: 2, columns: 1)
        )

        XCTAssertTrue(result.success)
        let associations = await scp.associationCount
        XCTAssertEqual(associations, 1)

        let log = await scp.commandLog
        XCTAssertEqual(log.filter { $0 == .nCreateRequest }.count, 3) // 1 session + 2 film boxes
        XCTAssertEqual(log.filter { $0 == .nSetRequest }.count, 3)   // 3 image boxes
        XCTAssertEqual(log.filter { $0 == .nActionRequest }.count, 2) // one print per film box
        XCTAssertEqual(log.filter { $0 == .nDeleteRequest }.count, 1)
    }

    // MARK: - Failure injection

    func testFailureCarriesErrorCommentToThrownError() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.failOn = .nSetRequest
        behavior.errorComment = "OUT OF FILM"
        behavior.errorID = 42
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: makeConfiguration(port: await scp.port),
                images: [pixels],
                imageDescriptors: [descriptor]
            )
            XCTFail("Expected printOperationFailed")
        } catch let error as DICOMNetworkError {
            guard case .printOperationFailed(_, let detail) = error else {
                return XCTFail("Expected printOperationFailed, got \(error)")
            }
            XCTAssertEqual(detail, "OUT OF FILM (Error ID 42)")
        }
    }

    func testFilmSessionCreateFailureAborts() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.failOn = .nCreateRequest
        behavior.errorComment = "SESSION REFUSED"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: makeConfiguration(port: await scp.port),
                images: [pixels],
                imageDescriptors: [descriptor]
            )
            XCTFail("Expected printOperationFailed")
        } catch let error as DICOMNetworkError {
            guard case .printOperationFailed(_, let detail) = error else {
                return XCTFail("Expected printOperationFailed, got \(error)")
            }
            XCTAssertEqual(detail, "SESSION REFUSED")
        }
        // No further workflow steps after the failed film-session create.
        let log = await scp.commandLog
        XCTAssertEqual(log, [.nCreateRequest])
    }

    func testDefensiveFilmSessionDeleteBeforeAbort() async throws {
        // P2-3: after the film session exists, a later failure must trigger a
        // best-effort in-association Film Session N-DELETE before the abort.
        var behavior = MockPrintSCPBehavior()
        behavior.failOn = .nActionRequest
        behavior.errorComment = "PRINTER JAM"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: makeConfiguration(port: await scp.port),
                images: [pixels],
                imageDescriptors: [descriptor]
            )
            XCTFail("Expected printOperationFailed")
        } catch let error as DICOMNetworkError {
            guard case .printOperationFailed(_, let detail) = error else {
                return XCTFail("Expected printOperationFailed, got \(error)")
            }
            XCTAssertEqual(detail, "PRINTER JAM")
        }

        let log = await scp.commandLog
        XCTAssertEqual(log.last, .nDeleteRequest,
                       "expected a defensive Film Session N-DELETE after the failed N-ACTION")
    }

    // MARK: - Timeout (P1-4)

    func testSilentSCPTimesOutInsteadOfHanging() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.silentAfterAccept = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        let started = Date()
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: makeConfiguration(port: await scp.port, timeout: 2),
                images: [pixels],
                imageDescriptors: [descriptor]
            )
            XCTFail("Expected a timeout error")
        } catch let error as DICOMNetworkError {
            guard case .operationTimeout = error else {
                return XCTFail("Expected operationTimeout, got \(error)")
            }
        }
        // Must fail near the configured 2s timeout — not hang.
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    // MARK: - Zero-context rejection

    func testAllContextsRejectedFailsCleanly() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.rejectAllContexts = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        do {
            _ = try await DICOMPrintService.printImages(
                configuration: makeConfiguration(port: await scp.port),
                images: [pixels],
                imageDescriptors: [descriptor]
            )
            XCTFail("Expected a context-rejection error")
        } catch let error as DICOMNetworkError {
            switch error {
            case .noPresentationContextAccepted, .sopClassNotSupported:
                break // both express "the SCP refused the print SOP class"
            default:
                XCTFail("Expected a context-rejection error, got \(error)")
            }
        }
    }

    // MARK: - Implicit VR LE printer (P1-3 full support)

    func testImplicitVROnlySCPPrintsSuccessfully() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.acceptOnlyImplicitVR = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels],
            imageDescriptors: [descriptor]
        )

        // The whole round-trip runs Implicit VR LE: film-session/box N-CREATEs
        // (serialized implicit) and the film-box response's Referenced Image
        // Box Sequence (parsed implicit) must all work.
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.printJobUID, "1.2.826.0.1.3680043.9.9001.1.1")
        let released = await scp.releasedCleanly
        XCTAssertTrue(released)
    }

    func testImplicitVROnlySCPPrinterStatus() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.acceptOnlyImplicitVR = true
        behavior.printerStatus = "FAILURE"
        behavior.printerStatusInfo = "OUT OF FILM"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let status = try await DICOMPrintService.getPrinterStatus(
            configuration: makeConfiguration(port: await scp.port))

        XCTAssertEqual(status.status, "FAILURE")
        XCTAssertEqual(status.statusInfo, "OUT OF FILM")
    }

    // MARK: - Printer status (P0-3 end-to-end)

    func testGetPrinterStatusWarning() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.printerStatus = "WARNING"
        behavior.printerStatusInfo = "SUPPLY LOW"
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let status = try await DICOMPrintService.getPrinterStatus(
            configuration: makeConfiguration(port: await scp.port))

        XCTAssertEqual(status.status, "WARNING")
        XCTAssertEqual(status.statusInfo, "SUPPLY LOW")
        XCTAssertEqual(status.printerName, "MOCK-PRINTER")
        XCTAssertFalse(status.isNormal)
    }

    // MARK: - Interleaved N-EVENT-REPORT

    func testInterleavedEventIsDeliveredAndWorkflowSucceeds() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.pushEventBeforeFirstResponse = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let received = EventCollector()
        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels],
            imageDescriptors: [descriptor],
            eventHandler: { event in received.append(event) }
        )

        XCTAssertTrue(result.success)
        let events = received.snapshot()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.printerEvent, .warning)

        // The SCU must have acknowledged the event (N-EVENT-REPORT-RSP).
        let log = await scp.commandLog
        XCTAssertTrue(log.contains(.nEventReportResponse))
    }

    func testEventDuringReleaseWindowDoesNotBreakRelease() async throws {
        // P2-7: an N-EVENT-REPORT arriving between A-RELEASE-RQ and
        // A-RELEASE-RP must be discarded — previously it aborted the
        // association and failed an otherwise successful print.
        var behavior = MockPrintSCPBehavior()
        behavior.pushEventDuringRelease = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels],
            imageDescriptors: [descriptor]
        )

        XCTAssertTrue(result.success)
        let released = await scp.releasedCleanly
        XCTAssertTrue(released)
    }

    // MARK: - Omitted job UID (P2-4)

    func testOmittedPrintJobUIDIsNotRecorded() async throws {
        var behavior = MockPrintSCPBehavior()
        behavior.omitPrintJobUID = true
        let scp = MockPrintSCP(behavior: behavior)
        try await scp.start()
        defer { Task { await scp.stop() } }

        let (pixels, descriptor) = makeImage()
        let result = try await DICOMPrintService.printImages(
            configuration: makeConfiguration(port: await scp.port),
            images: [pixels],
            imageDescriptors: [descriptor]
        )

        XCTAssertTrue(result.success)
        XCTAssertNil(result.printJobUID) // empty UID must not be recorded
    }
}

/// Thread-safe collector for events delivered on the networking task.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [PrintEvent] = []

    func append(_ event: PrintEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [PrintEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

#endif
