// Test-only C entry point. Link the existing optimized package objects; do not
// compile replacement library sources. Caller-owned fixture/context/stack are
// outside this narrow allocation probe, not evidence of worker admission.
import DICOMCore
import DICOMKit

@_silgen_name("vsm_retain") private func retainContext(_ context: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("vsm_admit") private func admit(_ context: UnsafeMutableRawPointer?, _ resource: Int32,
    _ payload: Int, _ control: Int, _ token: UnsafeMutablePointer<UInt64>?) -> Int32
@_silgen_name("vsm_release") private func release(_ context: UnsafeMutableRawPointer?, _ token: UInt64)
@_silgen_name("vsm_transfer") private func transfer(_ context: UnsafeMutableRawPointer?,
    _ token: UInt64, _ resource: Int32) -> Int32
@_silgen_name("vsm_release_context") private func releaseContext(_ context: UnsafeMutableRawPointer?)
@_silgen_name("vsm_checkpoint") private func checkpoint(_ context: UnsafeMutableRawPointer?,
    _ stage: Int32, _ metadata: Int, _ encoded: Int, _ total: Int, _ owners: Int) -> Int32

@_cdecl("verified_source_metrics_probe")
public func verifiedSourceMetricsProbe(_ descriptor: Int32, _ size: Int,
    _ context: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UInt64>) -> Int32 {
    guard size >= 0, size <= VerifiedFileByteSource.blockBytes + 13 else { return 1 }
    let callbacks = DICOMExternalAllocationCallbacks(context: context,
        retainContext: { retainContext($0) },
        admit: { admit($0, $1, $2, $3, $4) },
        release: { release($0, $1) },
        transfer: { transfer($0, $1, $2) },
        releaseContext: { releaseContext($0) })
    switch DICOMAllocationBudget.make(externalAdmission: callbacks) {
    case .failure: return 2
    case .success(let budget):
        let result = probeBudget(descriptor, size, context, output, budget)
        destroyBudget(budget)
        return result
    }
}

private func probeBudget(_ descriptor: Int32, _ size: Int, _ context: UnsafeMutableRawPointer?,
    _ output: UnsafeMutablePointer<UInt64>, _ budget: borrowing DICOMAllocationBudget) -> Int32 {
    guard check(context, 0, budget) else { return 3 }
    switch VerifiedFileByteSource.capture(descriptor: descriptor, budget: budget) {
    case .failure: return 4
    case .success(let source):
        let result = probeSource(size, context, output, budget, source)
        destroySource(source)
        guard result == 0 else { return result }
        return check(context, 6, budget) ? 0 : 5
    }
}

private func probeSource(_ size: Int, _ context: UnsafeMutableRawPointer?,
    _ output: UnsafeMutablePointer<UInt64>, _ budget: borrowing DICOMAllocationBudget,
    _ source: borrowing VerifiedFileByteSource) -> Int32 {
    guard source.count == size, check(context, 1, budget) else { return 6 }
    let initial = source.workMetrics
    write(initial, to: output)
    guard initial.isValid else { return 7 }
    switch source.shareOutcome() {
    case .failure: return 8
    case .success(let alias):
        guard check(context, 2, budget), alias.workMetrics == initial else { return 9 }
        let result = probeRead(size, context, budget, alias)
        let final = alias.workMetrics
        destroySource(alias)
        guard result == 0 else { return result }
        guard check(context, 5, budget), final.isValid, source.workMetrics == final else { return 10 }
        write(final, to: output.advanced(by: 10))
        // Repeated getters cover the hot snapshot path without any caller formatting.
        for _ in 0..<16 { if source.workMetrics != final { return 11 } }
        return 0
    }
}

private func probeRead(_ size: Int, _ context: UnsafeMutableRawPointer?,
    _ budget: borrowing DICOMAllocationBudget, _ source: borrowing VerifiedFileByteSource) -> Int32 {
    let lower = size > VerifiedFileByteSource.blockBytes ? VerifiedFileByteSource.blockBytes - 2 : 0
    let upper = size > VerifiedFileByteSource.blockBytes ? VerifiedFileByteSource.blockBytes + 3 : min(size, 5)
    switch source.readOutcome(lower..<upper) {
    case .failure: return 12
    case .success(let buffer):
        let contentsMatch = buffer.withBorrowedBytes { bytes in
            guard bytes.count == upper - lower else { return false }
            for byte in bytes { if byte != 0x5a { return false } }
            return true
        }
        let live = check(context, 3, budget)
        destroyBuffer(buffer)
        guard contentsMatch, live, check(context, 4, budget) else { return 13 }
        return 0
    }
}

private func check(_ context: UnsafeMutableRawPointer?, _ stage: Int32,
    _ budget: borrowing DICOMAllocationBudget) -> Bool {
    let receipt = budget.receipt
    return checkpoint(context, stage, receipt.current.metadata, receipt.current.encoded,
                      receipt.currentTotal, receipt.liveAllocations) == 0
}

private func write(_ value: VerifiedSourceWorkMetrics, to output: UnsafeMutablePointer<UInt64>) {
    output[0] = value.readNanoseconds
    output[1] = value.hashNanoseconds
    output[2] = value.copyNanoseconds
    output[3] = value.readCalls
    output[4] = value.hashUpdates
    output[5] = value.hashFinalizations
    output[6] = value.copyCalls
    output[7] = value.bytesRead
    output[8] = value.bytesCopied
    output[9] = value.isValid ? 1 : 0
}

// Concrete consumption avoids generic destroy-metadata setup in the measured path.
private func destroySource(_ value: consuming VerifiedFileByteSource) {}
private func destroyBuffer(_ value: consuming DICOMByteBuffer) {}
private func destroyBudget(_ value: consuming DICOMAllocationBudget) {}
