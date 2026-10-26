import Foundation
import Testing
import DICOMCore
@testable import DICOMWeb
#if canImport(Network)
import Network
#endif

@Suite("UPS Create identity — PS3.18 2026a 11.4.1.1")
struct UPSCreateIdentityTests {
    private let dt = "20261024103000.123456+0530"

    private func payload(_ uid: String? = nil) -> [String: Any] {
        var result: [String: Any] = [
            "00404005": ["vr": "DT", "Value": [dt]],
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]],
            "00100020": ["vr": "LO", "Value": ["SYNTHETIC-UPS"]]
        ]
        if let uid { result["00080018"] = ["vr": "UI", "Value": [uid]] }
        return result
    }

    @Test("Collection identity is retained; generation occurs only for genuine absence")
    func collectionIdentity() throws {
        let original = payload("2.25.701")
        let retained = try UPSCreateIdentity(workitem: original, explicitUID: nil)
        #expect(retained.uid == "2.25.701")
        #expect(!retained.usesQueryParameter)
        #expect(NSDictionary(dictionary: retained.workitem).isEqual(to: original))
        let first = try UPSCreateIdentity(workitem: payload(), explicitUID: nil)
        let second = try UPSCreateIdentity(workitem: payload(), explicitUID: nil)
        #expect(first.uid != second.uid)
        #expect(DICOMValueRules.isValidUID(first.uid))
        #expect((first.workitem["00080018"] as? [String: Any])?["vr"] as? String == "UI")
        #expect((first.workitem["00080018"] as? [String: Any])?["Value"] as? [String] == [first.uid])
    }

    #if canImport(Network)
    enum Facade: CaseIterable, Sendable { case ups, combined }

    private func create(_ facade: Facade, base: URL, body: [String: Any], uid: String? = nil) async throws -> UPSCreateResponse {
        let config = DICOMwebConfiguration(baseURL: base,
            timeouts: .init(connectTimeout: 2, readTimeout: 2, resourceTimeout: 4))
        switch facade {
        case .ups: return try await UPSClient(configuration: config).createWorkitem(workitem: body, uid: uid)
        case .combined: return try await DICOMwebClient(configuration: config).createWorkitem(workitem: body, uid: uid)
        }
    }

    @Test("Both public clients send the correct body/query identity and preserve unrelated attributes", arguments: Facade.allCases)
    func wireForms(_ facade: Facade) async throws {
        let peer = try UPSIdentityHTTPPeer()
        let base = try await peer.start()
        do {
            let supplied = try await create(facade, base: base, body: payload("2.25.701"))
            #expect(supplied.workitemUID == "2.25.701")
            let query = try await create(facade, base: base, body: payload(), uid: "2.25.702")
            #expect(query.workitemUID == "2.25.702")
            let matched = try await create(facade, base: base, body: payload("2.25.703"), uid: "2.25.703")
            #expect(matched.workitemUID == "2.25.703")
            let generated = try await create(facade, base: base, body: payload())
            #expect(DICOMValueRules.isValidUID(generated.workitemUID))
            let boundaryUID = "2." + String(repeating: "1", count: 62)
            let boundary = try await create(facade, base: base, body: payload(boundaryUID))
            #expect(boundary.workitemUID == boundaryUID)
            let requests = await peer.requests
            #expect(requests.count == 5)
            #expect(requests.map(\.target) == ["/dicom-web/workitems", "/dicom-web/workitems?workitem=2.25.702",
                "/dicom-web/workitems?workitem=2.25.703", "/dicom-web/workitems", "/dicom-web/workitems"])
            for (index, request) in requests.enumerated() {
                let json = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
                let uid = (json["00080018"] as? [String: Any])?["Value"] as? [String]
                #expect(uid == [0: ["2.25.701"], 3: [generated.workitemUID], 4: [boundaryUID]][index])
                #expect((json["00404005"] as? [String: Any])?["Value"] as? [String] == [dt])
                #expect((json["00100020"] as? [String: Any])?["Value"] as? [String] == ["SYNTHETIC-UPS"])
                #expect((json["00741000"] as? [String: Any])?["Value"] as? [String] == ["SCHEDULED"])
            }
            await peer.stop()
        } catch { await peer.stop(); throw error }
    }

    @Test("Invalid or conflicting identity is refused before either facade opens a connection", arguments: Facade.allCases)
    func refusalBeforeHTTP(_ facade: Facade) async throws {
        let peer = try UPSIdentityHTTPPeer()
        let base = try await peer.start()
        do {
            let badElements: [Any] = [
                NSNull(), "2.25.1", ["Value": ["2.25.1"]], ["vr": "LO", "Value": ["2.25.1"]],
                ["vr": "UI"], ["vr": "UI", "Value": []], ["vr": "UI", "Value": ["2.25.1", "2.25.2"]],
                ["vr": "UI", "Value": [123]], ["vr": "UI", "Value": [NSNull()]],
                ["vr": "UI", "Value": ["2.25.1"], "InlineBinary": ""],
                ["vr": "UI", "Value": ["2.25.1"], "BulkDataURI": "http://127.0.0.1/unused"]
            ] + ["", "1..2", "1.02.3", " 1.2", "1.2\n", "1.2\0", "١.2", String(repeating: "1", count: 65)]
                .map { ["vr": "UI", "Value": [$0]] }
            for bad in badElements {
                var body = payload(); body["00080018"] = bad
                for explicit in [String?.none, "2.25.1"] {
                    do {
                        _ = try await create(facade, base: base, body: body, uid: explicit)
                        Issue.record("Malformed supplied identity was accepted")
                    } catch let error as UPSError {
                        guard case .invalidWorkitemData = error else { throw error }
                    }
                }
            }
            for uid in ["", "1..2", "1.02", "1.2 ", "١.2", String(repeating: "1", count: 65)] {
                do {
                    _ = try await create(facade, base: base, body: payload(), uid: uid)
                    Issue.record("Malformed query identity was accepted")
                } catch let error as UPSError {
                    guard case .invalidWorkitemData = error else { throw error }
                }
            }
            do {
                _ = try await create(facade, base: base, body: payload("2.25.1"), uid: "2.25.2")
                Issue.record("Conflicting identities were accepted")
            } catch let error as UPSError {
                guard case .invalidWorkitemData = error else { throw error }
            }
            #expect(await peer.connectionCount == 0)
            #expect(await peer.requests.isEmpty)
            await peer.stop()
        } catch { await peer.stop(); throw error }
    }

    @Test("Collection duplicate error identifies the resolved UID", arguments: Facade.allCases)
    func duplicateIdentity(_ facade: Facade) async throws {
        let peer = try UPSIdentityHTTPPeer()
        let base = try await peer.start()
        do {
            _ = try await create(facade, base: base, body: payload("2.25.704"))
            do {
                _ = try await create(facade, base: base, body: payload("2.25.704"))
                Issue.record("Duplicate creation was accepted")
            } catch let error as UPSError {
                #expect(error == .workitemAlreadyExists(uid: "2.25.704"))
            }
            #expect(await peer.requests.count == 2)
            await peer.stop()
        } catch { await peer.stop(); throw error }
    }

    @Test("Response without Location falls back to the actual supplied or generated UID", arguments: Facade.allCases)
    func responseFallback(_ facade: Facade) async throws {
        let peer = try UPSIdentityHTTPPeer(omitLocation: true)
        let base = try await peer.start()
        do {
            let response = try await create(facade, base: base, body: payload("2.25.705"))
            #expect(response.workitemUID == "2.25.705")
            let generated = try await create(facade, base: base, body: payload())
            let last = try #require(await peer.requests.last)
            let json = try #require(JSONSerialization.jsonObject(with: last.body) as? [String: Any])
            #expect((json["00080018"] as? [String: Any])?["Value"] as? [String] == [generated.workitemUID])
            #expect(DICOMValueRules.isValidUID(generated.workitemUID))
            await peer.stop()
        } catch { await peer.stop(); throw error }
    }
    #endif
}

#if canImport(Network)
/// Independent HTTP origin for the public-client tests. It does not call the
/// production identity helper or UID validator and rejects missing identity.
private actor UPSIdentityHTTPPeer {
    struct Request: Sendable { let target: String; let body: Data }
    private let listener: NWListener
    private let omitLocation: Bool
    private var stored = Set<String>()
    private(set) var requests: [Request] = []
    private(set) var connectionCount = 0
    private var tasks: [Task<Void, Never>] = []

    init(omitLocation: Bool = false) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.omitLocation = omitLocation
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        let once = UPSIdentityReadyFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: URLError(.cancelled)) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        listener.stateUpdateHandler = nil
        return URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/dicom-web")!
    }

    func stop() {
        listener.cancel()
        tasks.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        connectionCount += 1
        tasks.append(Task {
            connection.start(queue: .global())
            defer { connection.cancel() }
            do {
                var buffer = Data()
                while buffer.count < 65_536 {
                    let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                            if let error { continuation.resume(throwing: error) }
                            else if let data, !data.isEmpty { continuation.resume(returning: data) }
                            else { continuation.resume(throwing: URLError(complete ? .networkConnectionLost : .badServerResponse)) }
                        }
                    }
                    buffer.append(chunk)
                    guard let split = buffer.range(of: Data("\r\n\r\n".utf8)),
                          let header = String(data: buffer[..<split.lowerBound], encoding: .utf8) else { continue }
                    let lines = header.components(separatedBy: "\r\n")
                    let length = lines.first { $0.lowercased().hasPrefix("content-length:") }
                        .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    guard buffer.count - split.upperBound >= length else { continue }
                    let target = String(lines[0].split(separator: " ")[1])
                    let body = Data(buffer[split.upperBound..<(split.upperBound + length)])
                    let response = reply(Request(target: target, body: body))
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        })
                    }
                    return
                }
            } catch { /* Client failures surface in the awaited request and captured counts. */ }
        })
    }

    private func reply(_ request: Request) -> String {
        requests.append(request)
        let components = URLComponents(string: "http://127.0.0.1" + request.target)
        let queryUID = components?.queryItems?.first { $0.name == "workitem" }?.value
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        let element = json?["00080018"] as? [String: Any]
        let values = element?["Value"] as? [String]
        let bodyUID = element?["vr"] as? String == "UI" && values?.count == 1 ? values?.first : nil
        let uid = queryUID ?? bodyUID
        let validUID = uid.map { $0.utf8.count <= 64 && $0.range(of: "^(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$", options: .regularExpression) != nil } ?? false
        let valid = validUID && components?.path == "/dicom-web/workitems" && (queryUID == nil || json?["00080018"] == nil)
        let code: Int
        if !valid { code = 400 }
        else if stored.contains(uid!) { code = 409 }
        else { stored.insert(uid!); code = 201 }
        let location = code == 201 && !omitLocation ? "Location: http://127.0.0.1:\(listener.port!.rawValue)/dicom-web/workitems/\(uid!)\r\n" : ""
        return "HTTP/1.1 \(code) Test\r\n\(location)Content-Length: 0\r\nConnection: close\r\n\r\n"
    }
}

private final class UPSIdentityReadyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
#endif
