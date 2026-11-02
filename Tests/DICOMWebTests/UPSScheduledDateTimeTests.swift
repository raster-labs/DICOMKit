import Foundation
import Testing
@testable import DICOMWeb

@Suite("UPS scheduled DICOM DT round trips")
struct UPSScheduledDateTimeTests {
    private let tag = "00404005"
    private let uid = "2.25.20261024"

    private func request(_ method: DICOMwebRequest.HTTPMethod, _ path: String, json: [String: Any]? = nil) throws -> DICOMwebRequest {
        DICOMwebRequest(method: method, path: "/dicom-web" + path, queryParameters: [:],
                        body: try json.map { try JSONSerialization.data(withJSONObject: $0) })
    }

    private func payload(_ value: String) -> [String: Any] {
        ["00080018": ["vr": "UI", "Value": [uid]], tag: ["vr": "DT", "Value": [value]]]
    }

    private func returnedDT(_ response: DICOMwebResponse, search: Bool = false) throws -> String {
        #expect(response.statusCode == 200)
        let object = try JSONSerialization.jsonObject(with: #require(response.body))
        let json = try #require(search ? (object as? [[String: Any]])?.first : object as? [String: Any])
        let element = try #require(json[tag] as? [String: Any])
        #expect(element["vr"] as? String == "DT")
        return try #require((element["Value"] as? [String])?.first)
    }

    /// Independent decoder for the full-precision response fixtures: does not use
    /// DICOMDateTime or the new production validation/formatting implementation.
    private func decodedInstant(_ value: String) throws -> Date {
        #expect(value.range(of: "^[0-9]{14}\\.[0-9]{6}[+-][0-9]{4}$", options: .regularExpression) != nil)
        let chars = Array(value)
        func integer(_ start: Int, _ count: Int) throws -> Int {
            try #require(Int(String(chars[start..<(start + count)])))
        }
        let sign = chars[21] == "+" ? 1 : -1
        let offset = try sign * (integer(22, 2) * 60 + integer(24, 2))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: offset * 60))
        let parts = try DateComponents(year: integer(0, 4), month: integer(4, 2), day: integer(6, 2),
            hour: integer(8, 2), minute: integer(10, 2), second: integer(12, 2))
        return try #require(calendar.date(from: parts)).addingTimeInterval(Double(integer(15, 6)) / 1_000_000)
    }

    @Test("Create, retrieve and search retain fractions, offset and instant")
    func createRetrieveSearch() async throws {
        let storage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: InMemoryStorageProvider(), upsStorage: storage)
        let input = "20261024103000.123456+0530"
        let created = await server.handleRequest(try request(.post, "/workitems", json: payload(input)))
        #expect(created.statusCode == 201)
        let saved = try #require(await storage.getWorkitem(workitemUID: uid))
        let expected = try decodedInstant(input)
        #expect(abs(try #require(saved.scheduledStartDateTime).timeIntervalSince(expected)) < 0.0000011)
        for (path, search) in [("/workitems/" + uid, false), ("/workitems", true)] {
            let value = try returnedDT(await server.handleRequest(request(.get, path)), search: search)
            #expect(value == input)
            #expect(abs(try decodedInstant(value).timeIntervalSince(expected)) < 0.0000011)
        }
    }

    @Test("Updates preserve legal precision and reject malformed input atomically")
    func updates() async throws {
        let storage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: InMemoryStorageProvider(), upsStorage: storage)
        _ = await server.handleRequest(try request(.post, "/workitems", json: payload("20261024103000.123456+0530")))
        for value in ["2026", "202610", "20261024", "2026102410+0530", "202610241030", "20261024103000.1-0800",
                      "20261024103000.123456+0530"] {
            let updated = await server.handleRequest(try request(.post, "/workitems/" + uid, json: payload(value)))
            #expect(updated.statusCode == 200)
            #expect(try returnedDT(await server.handleRequest(request(.get, "/workitems/" + uid))) == value)
        }
        let before = try #require(await storage.getWorkitem(workitemUID: uid))
        for value in ["20260231", "20261024103000.", "20261024103000.1234567", "20261024103000-0000",
                      "20261024103000+1460", "2026-10-24T10:30:00+05:30", "", "20261024250000"] {
            var invalid = payload(value)
            invalid["00100020"] = ["vr": "LO", "Value": ["MUST_NOT_CHANGE"]]
            let response = await server.handleRequest(try request(.post, "/workitems/" + uid, json: invalid))
            #expect(response.statusCode == 400, "\(value)")
            #expect(try await storage.getWorkitem(workitemUID: uid) == before)
        }
    }

    @Test("Malformed DT create payloads are rejected without storing a workitem")
    func malformedCreate() async throws {
        let storage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: InMemoryStorageProvider(), upsStorage: storage)
        let elements: [[String: Any]] = [
            ["vr": "DT", "Value": ["20260231"]], ["vr": "DA", "Value": ["20261024"]],
            ["vr": "DT", "Value": ["2026", "2027"]], ["vr": "DT", "Value": [2026]], ["vr": "DT"]
        ]
        for element in elements {
            var json = payload("2026")
            json[tag] = element
            let response = await server.handleRequest(try request(.post, "/workitems", json: json))
            #expect(response.statusCode == 400)
            #expect(try await storage.getWorkitem(workitemUID: uid) == nil)
        }
    }

    @Test("Stored Dates emit compact UTC DT; persisted raw precision survives until the date changes")
    func dateAndPersistence() async throws {
        let date = try decodedInstant("20261024103000.123456+0530")
        var item = Workitem(workitemUID: uid, scheduledStartDateTime: date)
        let storage = InMemoryUPSStorageProvider()
        let server = DICOMwebServer(configuration: .development, storage: InMemoryStorageProvider(), upsStorage: storage)
        try await storage.createWorkitem(item)
        let value = try returnedDT(await server.handleRequest(request(.get, "/workitems/" + uid)))
        #expect(value == "20261024050000.123456+0000")
        #expect(abs(try decodedInstant(value).timeIntervalSince(date)) < 0.0000011)
        let accepted = item.setScheduledStartDateTime(dicomValue: "20261024103000.1+0530")
        #expect(accepted)
        item = try JSONDecoder().decode(Workitem.self, from: JSONEncoder().encode(item))
        #expect(item.scheduledStartDICOMString == "20261024103000.1+0530")
        item.scheduledStartDateTime = date
        #expect(item.scheduledStartDICOMString == "20261024050000.123456+0000")
        // The separate client encoder retains its existing compact-second contract.
        let clientElement = try #require(item.toDICOMJSON()[tag] as? [String: Any])
        #expect((clientElement["Value"] as? [String])?.first?.range(of: "^[0-9]{14}$", options: .regularExpression) != nil)
    }
}
