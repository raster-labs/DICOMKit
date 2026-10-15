import Darwin

@_silgen_name("dc_external_probe_arm") private func arm(_ mode: Int32)
@_silgen_name("dc_external_probe_disarm") private func disarm()
@_silgen_name("dc_external_probe_maps") private func maps() -> Int32
@_silgen_name("dc_external_probe_unmaps") private func unmaps() -> Int32

private struct ProbeState {
    var retains = 0
    var admits = 0
    var releases = 0
    var final = 0
    var charged = 0
}

@main enum BootstrapProbe {
    static func main() {
        let mode = Int32(CommandLine.arguments[1])!
        let raw = mmap(nil, Int(getpagesize()), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)!
        precondition(raw != MAP_FAILED)
        let state = raw.bindMemory(to: ProbeState.self, capacity: 1)
        state.initialize(to: ProbeState())
        let callbacks = DICOMExternalAllocationCallbacks(context: state, retainContext: { raw in
            raw!.assumingMemoryBound(to: ProbeState.self).pointee.retains += 1
            return 0
        }, admit: { raw, resource, payload, control, token in
            let state = raw!.assumingMemoryBound(to: ProbeState.self)
            precondition(resource == 5 && payload == 0 && control == Int(getpagesize()))
            state.pointee.admits += 1
            state.pointee.charged = control
            token!.pointee = 1
            return 0
        }, release: { raw, token in
            let state = raw!.assumingMemoryBound(to: ProbeState.self)
            precondition(token == 1 && state.pointee.final == 0)
            state.pointee.releases += 1
            state.pointee.charged = 0
        }, transfer: { _, _, _ in 99 }, releaseContext: { raw in
            let state = raw!.assumingMemoryBound(to: ProbeState.self)
            precondition(state.pointee.releases == 1 && state.pointee.charged == 0)
            state.pointee.final += 1
        })
        arm(mode)
        switch DICOMAllocationBudget.make(externalAdmission: callbacks) {
        case .success:
            precondition(mode == 0)
        case .failure(let error):
            precondition(error == (mode == 1 ? .allocationFailed : .synchronizationFailed))
        }
        disarm()
        let quarantined = mode == 3
        precondition(state.pointee.retains == 1 && state.pointee.admits == 1)
        precondition(state.pointee.releases == (quarantined ? 0 : 1))
        precondition(state.pointee.final == (quarantined ? 0 : 1))
        precondition(state.pointee.charged == (quarantined ? Int(getpagesize()) : 0))
        precondition(maps() == 1 && unmaps() == (mode == 1 ? 0 : 1))
        print("{\"mode\":\(mode),\"maps\":\(maps()),\"unmaps\":\(unmaps()),\"releases\":\(state.pointee.releases),\"contextReleases\":\(state.pointee.final),\"charged\":\(state.pointee.charged),\"passed\":true}")
        // A quarantined context remains mapped until this disposable process exits.
        if !quarantined { precondition(munmap(raw, Int(getpagesize())) == 0) }
    }
}
