// DICOMwebHelpersTests.swift
// DICOMStudioTests

import Testing
@testable import DICOMStudio
import Foundation

@Suite("DICOMweb Helpers Tests")
struct DICOMwebHelpersTests {

    // MARK: - DICOMwebURLHelpers

    @Test("DICOMwebURLHelpers isValidURL https://example.com is valid")
    func testURLHelpersValidHTTPS() {
        #expect(DICOMwebURLHelpers.isValidURL("https://example.com") == true)
    }

    @Test("DICOMwebURLHelpers isValidURL http://localhost:8042 is valid")
    func testURLHelpersValidHTTPLocalhost() {
        #expect(DICOMwebURLHelpers.isValidURL("http://localhost:8042") == true)
    }

    @Test("DICOMwebURLHelpers isValidURL empty string is not valid")
    func testURLHelpersEmptyInvalid() {
        #expect(DICOMwebURLHelpers.isValidURL("") == false)
    }

    @Test("DICOMwebURLHelpers isValidURL ftp scheme is not valid")
    func testURLHelpersFTPInvalid() {
        #expect(DICOMwebURLHelpers.isValidURL("ftp://example.com") == false)
    }

    @Test("DICOMwebURLHelpers isValidURL non-URL string is not valid")
    func testURLHelpersNonURLInvalid() {
        #expect(DICOMwebURLHelpers.isValidURL("not-a-url") == false)
    }

    @Test("DICOMwebURLHelpers normalizeURL trims whitespace and trailing slash")
    func testURLHelpersNormalizeTrimsWhitespaceAndSlash() {
        #expect(DICOMwebURLHelpers.normalizeURL("  https://example.com/  ") == "https://example.com")
    }

    @Test("DICOMwebURLHelpers normalizeURL preserves path without trailing slash")
    func testURLHelpersNormalizePreservesPath() {
        #expect(DICOMwebURLHelpers.normalizeURL("https://pacs.example.com/dicom-web") == "https://pacs.example.com/dicom-web")
    }

    @Test("DICOMwebURLHelpers validationError for empty string is not nil")
    func testURLHelpersValidationErrorForEmpty() {
        #expect(DICOMwebURLHelpers.validationError(for: "") != nil)
    }

    @Test("DICOMwebURLHelpers validationError for valid https URL is nil")
    func testURLHelpersValidationErrorForValidURL() {
        #expect(DICOMwebURLHelpers.validationError(for: "https://example.com") == nil)
    }

    @Test("DICOMwebURLHelpers validationError for ftp scheme is not nil")
    func testURLHelpersValidationErrorForFTP() {
        #expect(DICOMwebURLHelpers.validationError(for: "ftp://x") != nil)
    }

    @Test("DICOMwebURLHelpers displayHost returns host and port")
    func testURLHelpersDisplayHost() {
        let host = DICOMwebURLHelpers.displayHost(for: "https://pacs.hospital.com:8042/dicom-web")
        #expect(host == "pacs.hospital.com:8042")
    }

    // MARK: - DICOMwebAuthHelpers

    @Test("DICOMwebAuthHelpers requiresToken bearer is true")
    func testAuthHelpersRequiresTokenBearer() {
        #expect(DICOMwebAuthHelpers.requiresToken(.bearer) == true)
    }

    @Test("DICOMwebAuthHelpers requiresToken jwt is true")
    func testAuthHelpersRequiresTokenJWT() {
        #expect(DICOMwebAuthHelpers.requiresToken(.jwt) == true)
    }

    @Test("DICOMwebAuthHelpers requiresToken none is false")
    func testAuthHelpersRequiresTokenNone() {
        #expect(DICOMwebAuthHelpers.requiresToken(.none) == false)
    }

    @Test("DICOMwebAuthHelpers requiresToken basic is false")
    func testAuthHelpersRequiresTokenBasic() {
        #expect(DICOMwebAuthHelpers.requiresToken(.basic) == false)
    }

    @Test("DICOMwebAuthHelpers requiresCredentials basic is true")
    func testAuthHelpersRequiresCredentialsBasic() {
        #expect(DICOMwebAuthHelpers.requiresCredentials(.basic) == true)
    }

    @Test("DICOMwebAuthHelpers requiresCredentials bearer is false")
    func testAuthHelpersRequiresCredentialsBearer() {
        #expect(DICOMwebAuthHelpers.requiresCredentials(.bearer) == false)
    }

    @Test("DICOMwebAuthHelpers requiresOAuth oauth2PKCE is true")
    func testAuthHelpersRequiresOAuthPKCE() {
        #expect(DICOMwebAuthHelpers.requiresOAuth(.oauth2PKCE) == true)
    }

    @Test("DICOMwebAuthHelpers requiresOAuth bearer is false")
    func testAuthHelpersRequiresOAuthBearer() {
        #expect(DICOMwebAuthHelpers.requiresOAuth(.bearer) == false)
    }

    @Test("DICOMwebAuthHelpers tokenPreview long token shows prefix and suffix")
    func testAuthHelpersTokenPreviewLong() {
        let token = "abcdefghijklmnopqrstuvwxyz"
        let preview = DICOMwebAuthHelpers.tokenPreview(for: token)
        #expect(preview.contains("abcdefgh"))
        #expect(preview.contains("..."))
        #expect(preview.contains("wxyz"))
    }

    @Test("DICOMwebAuthHelpers tokenPreview empty returns empty")
    func testAuthHelpersTokenPreviewEmpty() {
        #expect(DICOMwebAuthHelpers.tokenPreview(for: "") == "")
    }

    @Test("DICOMwebAuthHelpers tokenPreview short token returns masked string")
    func testAuthHelpersTokenPreviewShort() {
        #expect(DICOMwebAuthHelpers.tokenPreview(for: "short") == "••••••••")
    }

    @Test("DICOMwebAuthHelpers validationError bearer with empty token is not nil")
    func testAuthHelpersValidationErrorBearerEmptyToken() {
        let err = DICOMwebAuthHelpers.validationError(
            for: .bearer, token: "", username: "", password: "")
        #expect(err != nil)
    }

    @Test("DICOMwebAuthHelpers validationError bearer with valid token is nil")
    func testAuthHelpersValidationErrorBearerValidToken() {
        let err = DICOMwebAuthHelpers.validationError(
            for: .bearer, token: "my-valid-token", username: "", password: "")
        #expect(err == nil)
    }

    @Test("DICOMwebAuthHelpers validationError basic with empty username is not nil")
    func testAuthHelpersValidationErrorBasicEmptyUsername() {
        let err = DICOMwebAuthHelpers.validationError(
            for: .basic, token: "", username: "", password: "pass")
        #expect(err != nil)
    }

    @Test("DICOMwebAuthHelpers validationError none with no credentials is nil")
    func testAuthHelpersValidationErrorNoneIsNil() {
        let err = DICOMwebAuthHelpers.validationError(
            for: .none, token: "", username: "", password: "")
        #expect(err == nil)
    }

    // MARK: - DICOMwebTLSHelpers

    @Test("DICOMwebTLSHelpers sfSymbol for none is lock.slash")
    func testTLSHelpersSFSymbolNone() {
        #expect(DICOMwebTLSHelpers.sfSymbol(for: .none) == "lock.slash")
    }

    @Test("DICOMwebTLSHelpers sfSymbol for modifiedBCP195 is lock.shield")
    func testTLSHelpersSFSymbolStrict() {
        #expect(DICOMwebTLSHelpers.sfSymbol(for: .modifiedBCP195) == "lock.shield")
    }

    @Test("DICOMwebTLSHelpers isProductionSafe bcp195 is true")
    func testTLSHelpersIsProductionSafeCompatible() {
        #expect(DICOMwebTLSHelpers.isProductionSafe(.bcp195) == true)
    }

    @Test("DICOMwebTLSHelpers isProductionSafe modifiedBCP195 is true")
    func testTLSHelpersIsProductionSafeStrict() {
        #expect(DICOMwebTLSHelpers.isProductionSafe(.modifiedBCP195) == true)
    }

    @Test("DICOMwebTLSHelpers isProductionSafe none is false")
    func testTLSHelpersIsProductionSafeNone() {
        #expect(DICOMwebTLSHelpers.isProductionSafe(.none) == false)
    }

    @Test("DICOMwebTLSHelpers isProductionSafe development is false")
    func testTLSHelpersIsProductionSafeDevelopment() {
        #expect(DICOMwebTLSHelpers.isProductionSafe(.development) == false)
    }

    @Test("DICOMwebTLSHelpers securityDescription for none is non-empty")
    func testTLSHelpersSecurityDescriptionNone() {
        #expect(!DICOMwebTLSHelpers.securityDescription(for: .none).isEmpty)
    }

    @Test("DICOMwebTLSHelpers securityDescription for development mentions self-signed or development")
    func testTLSHelpersSecurityDescriptionDevelopment() {
        let desc = DICOMwebTLSHelpers.securityDescription(for: .development).lowercased()
        #expect(desc.contains("self-signed") || desc.contains("development"))
    }

    // MARK: - DICOMwebQIDOHelpers

    @Test("DICOMwebQIDOHelpers endpointSuffix for study is /studies")
    func testQIDOHelpersEndpointSuffixStudy() {
        #expect(DICOMwebQIDOHelpers.endpointSuffix(for: .study) == "/studies")
    }

    @Test("DICOMwebQIDOHelpers endpointSuffix for series is /series")
    func testQIDOHelpersEndpointSuffixSeries() {
        #expect(DICOMwebQIDOHelpers.endpointSuffix(for: .series) == "/series")
    }

    @Test("DICOMwebQIDOHelpers endpointSuffix for instance is /instances")
    func testQIDOHelpersEndpointSuffixInstance() {
        #expect(DICOMwebQIDOHelpers.endpointSuffix(for: .instance) == "/instances")
    }

    @Test("DICOMwebQIDOHelpers formatPatientName empty returns dash")
    func testQIDOHelpersFormatPatientNameEmpty() {
        #expect(DICOMwebQIDOHelpers.formatPatientName("") == "—")
    }

    @Test("DICOMwebQIDOHelpers formatPatientName caret-delimited contains both components")
    func testQIDOHelpersFormatPatientNameCaret() {
        let result = DICOMwebQIDOHelpers.formatPatientName("SMITH^JOHN")
        #expect(result.contains("SMITH"))
        #expect(result.contains("JOHN"))
    }

    @Test("DICOMwebQIDOHelpers formatStudyDate empty from and to returns any-date string")
    func testQIDOHelpersFormatStudyDateBothEmpty() {
        #expect(DICOMwebQIDOHelpers.formatStudyDate(from: "", to: "") == "Any date")
    }

    @Test("DICOMwebQIDOHelpers formatStudyDate with from contains from date")
    func testQIDOHelpersFormatStudyDateFromOnly() {
        let result = DICOMwebQIDOHelpers.formatStudyDate(from: "2024-01-01", to: "")
        #expect(result.contains("2024-01-01"))
    }

    @Test("DICOMwebQIDOHelpers buildQuerySummary with all-empty params returns non-empty string")
    func testQIDOHelpersBuildQuerySummaryEmpty() {
        #expect(!DICOMwebQIDOHelpers.buildQuerySummary(params: QIDOQueryParams()).isEmpty)
    }

    // MARK: - DICOMwebWADOHelpers

    @Test("DICOMwebWADOHelpers formattedBytesReceived 512 contains 512")
    func testWADOHelpersFormattedBytes512() {
        #expect(DICOMwebWADOHelpers.formattedBytesReceived(512).contains("512"))
    }

    @Test("DICOMwebWADOHelpers formattedBytesReceived 1MB contains MB or 1")
    func testWADOHelpersFormattedBytesMB() {
        let result = DICOMwebWADOHelpers.formattedBytesReceived(1024 * 1024)
        #expect(result.contains("MB") || result.contains("1"))
    }

    @Test("DICOMwebWADOHelpers formattedTransferRate nil returns dash")
    func testWADOHelpersFormattedTransferRateNil() {
        #expect(DICOMwebWADOHelpers.formattedTransferRate(nil) == "—")
    }

    @Test("DICOMwebWADOHelpers formattedTransferRate non-nil returns rate with units")
    func testWADOHelpersFormattedTransferRateNonNil() {
        let result = DICOMwebWADOHelpers.formattedTransferRate(1_000_000)
        #expect(result.contains("B/s") || result.contains("KB/s") || result.contains("MB/s"))
    }

    // MARK: - DICOMwebSTOWHelpers

    @Test("DICOMwebSTOWHelpers duplicateHandlingDescription reject contains 409 or Reject")
    func testSTOWHelpersDuplicateHandlingReject() {
        let desc = DICOMwebSTOWHelpers.duplicateHandlingDescription(.reject)
        #expect(desc.contains("409") || desc.lowercased().contains("reject"))
    }

    @Test("DICOMwebSTOWHelpers duplicateHandlingDescription overwrite contains overwrite")
    func testSTOWHelpersDuplicateHandlingOverwrite() {
        let desc = DICOMwebSTOWHelpers.duplicateHandlingDescription(.overwrite).lowercased()
        #expect(desc.contains("overwrite"))
    }

    @Test("DICOMwebSTOWHelpers duplicateHandlingDescription ignore contains skip or ignore or silent")
    func testSTOWHelpersDuplicateHandlingIgnore() {
        let desc = DICOMwebSTOWHelpers.duplicateHandlingDescription(.ignore).lowercased()
        #expect(desc.contains("skip") || desc.contains("ignore") || desc.contains("silent"))
    }

    // MARK: - DICOMwebUPSHelpers

    @Test("DICOMwebUPSHelpers sfSymbol for scheduled is calendar")
    func testUPSHelpersSFSymbolScheduled() {
        #expect(DICOMwebUPSHelpers.sfSymbol(for: .scheduled) == "calendar")
    }

    @Test("DICOMwebUPSHelpers sfSymbol for completed is checkmark.circle.fill")
    func testUPSHelpersSFSymbolCompleted() {
        #expect(DICOMwebUPSHelpers.sfSymbol(for: .completed) == "checkmark.circle.fill")
    }

    @Test("DICOMwebUPSHelpers canTransition from scheduled to inProgress is true")
    func testUPSHelpersCanTransitionScheduledToInProgress() {
        #expect(DICOMwebUPSHelpers.canTransition(from: .scheduled, to: .inProgress) == true)
    }

    @Test("DICOMwebUPSHelpers canTransition from completed to cancelled is false")
    func testUPSHelpersCanTransitionCompletedToCancelled() {
        #expect(DICOMwebUPSHelpers.canTransition(from: .completed, to: .canceled) == false)
    }

    @Test("DICOMwebUPSHelpers availableTransitions from inProgress has 2 transitions")
    func testUPSHelpersAvailableTransitionsInProgress() {
        #expect(DICOMwebUPSHelpers.availableTransitions(from: .inProgress).count == 2)
    }

    // MARK: - DICOMwebUPSHelpers Event Channel Helpers

    @Test("DICOMwebUPSHelpers eventChannelSFSymbol for connected is wifi")
    func testUPSHelpersEventChannelSFSymbolConnected() {
        #expect(DICOMwebUPSHelpers.eventChannelSFSymbol(for: .connected) == "wifi")
    }

    @Test("DICOMwebUPSHelpers eventChannelSFSymbol for disconnected is wifi.slash")
    func testUPSHelpersEventChannelSFSymbolDisconnected() {
        #expect(DICOMwebUPSHelpers.eventChannelSFSymbol(for: .disconnected) == "wifi.slash")
    }

    @Test("DICOMwebUPSHelpers eventChannelSFSymbol for reconnecting is arrow.triangle.2.circlepath")
    func testUPSHelpersEventChannelSFSymbolReconnecting() {
        #expect(DICOMwebUPSHelpers.eventChannelSFSymbol(for: .reconnecting) == "arrow.triangle.2.circlepath")
    }

    @Test("DICOMwebUPSHelpers eventChannelColor for connected is green")
    func testUPSHelpersEventChannelColorConnected() {
        #expect(DICOMwebUPSHelpers.eventChannelColor(for: .connected) == ".green")
    }

    @Test("DICOMwebUPSHelpers eventChannelColor for disconnected is secondary")
    func testUPSHelpersEventChannelColorDisconnected() {
        #expect(DICOMwebUPSHelpers.eventChannelColor(for: .disconnected) == ".secondary")
    }

    @Test("DICOMwebUPSHelpers eventChannelColor for closed is red")
    func testUPSHelpersEventChannelColorClosed() {
        #expect(DICOMwebUPSHelpers.eventChannelColor(for: .closed) == ".red")
    }

    @Test("DICOMwebUPSHelpers eventTypeSFSymbol for stateChange is arrow.left.arrow.right")
    func testUPSHelpersEventTypeSFSymbolStateChange() {
        #expect(DICOMwebUPSHelpers.eventTypeSFSymbol(for: .stateChange) == "arrow.left.arrow.right")
    }

    @Test("DICOMwebUPSHelpers eventTypeSFSymbol for cancellationRequested is xmark.octagon")
    func testUPSHelpersEventTypeSFSymbolCancellation() {
        #expect(DICOMwebUPSHelpers.eventTypeSFSymbol(for: .cancellationRequested) == "xmark.octagon")
    }

    @Test("DICOMwebUPSHelpers eventTypeColor for stateChange is blue")
    func testUPSHelpersEventTypeColorStateChange() {
        #expect(DICOMwebUPSHelpers.eventTypeColor(for: .stateChange) == ".blue")
    }

    @Test("DICOMwebUPSHelpers eventTypeColor for cancellationRequested is red")
    func testUPSHelpersEventTypeColorCancellation() {
        #expect(DICOMwebUPSHelpers.eventTypeColor(for: .cancellationRequested) == ".red")
    }

    @Test("DICOMwebUPSHelpers monitorToggleLabel active returns Stop Monitoring")
    func testUPSHelpersMonitorToggleLabelActive() {
        #expect(DICOMwebUPSHelpers.monitorToggleLabel(isActive: true) == "Stop Monitoring")
    }

    @Test("DICOMwebUPSHelpers monitorToggleLabel inactive returns Start Monitoring")
    func testUPSHelpersMonitorToggleLabelInactive() {
        #expect(DICOMwebUPSHelpers.monitorToggleLabel(isActive: false) == "Start Monitoring")
    }

    @Test("DICOMwebUPSHelpers monitorToggleSFSymbol active returns stop.circle.fill")
    func testUPSHelpersMonitorToggleSFSymbolActive() {
        #expect(DICOMwebUPSHelpers.monitorToggleSFSymbol(isActive: true) == "stop.circle.fill")
    }

    @Test("DICOMwebUPSHelpers monitorToggleSFSymbol inactive returns play.circle.fill")
    func testUPSHelpersMonitorToggleSFSymbolInactive() {
        #expect(DICOMwebUPSHelpers.monitorToggleSFSymbol(isActive: false) == "play.circle.fill")
    }

    @Test("DICOMwebUPSHelpers relativeTimeString shows just now for recent date")
    func testUPSHelpersRelativeTimeStringJustNow() {
        let now = Date()
        #expect(DICOMwebUPSHelpers.relativeTimeString(from: now, relativeTo: now) == "just now")
    }

    @Test("DICOMwebUPSHelpers relativeTimeString shows seconds ago for date within 60s")
    func testUPSHelpersRelativeTimeStringSeconds() {
        let now = Date()
        let thirtySecondsAgo = now.addingTimeInterval(-30)
        let result = DICOMwebUPSHelpers.relativeTimeString(from: thirtySecondsAgo, relativeTo: now)
        #expect(result == "30s ago")
    }

    @Test("DICOMwebUPSHelpers relativeTimeString shows minutes ago for date within 1h")
    func testUPSHelpersRelativeTimeStringMinutes() {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        let result = DICOMwebUPSHelpers.relativeTimeString(from: fiveMinutesAgo, relativeTo: now)
        #expect(result == "5m ago")
    }

    @Test("DICOMwebUPSHelpers relativeTimeString shows hours ago for date within 1d")
    func testUPSHelpersRelativeTimeStringHours() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let result = DICOMwebUPSHelpers.relativeTimeString(from: twoHoursAgo, relativeTo: now)
        #expect(result == "2h ago")
    }

    @Test("DICOMwebUPSHelpers relativeTimeString shows days ago for date beyond 1d")
    func testUPSHelpersRelativeTimeStringDays() {
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-259200)
        let result = DICOMwebUPSHelpers.relativeTimeString(from: threeDaysAgo, relativeTo: now)
        #expect(result == "3d ago")
    }

    @Test("DICOMwebUPSHelpers all event channel states have non-empty symbols")
    func testUPSHelpersAllEventChannelStatesHaveSymbols() {
        for state in UPSEventChannelState.allCases {
            #expect(!DICOMwebUPSHelpers.eventChannelSFSymbol(for: state).isEmpty)
        }
    }

    @Test("DICOMwebUPSHelpers all event types have non-empty symbols")
    func testUPSHelpersAllEventTypesHaveSymbols() {
        for type in UPSEventType.allCases {
            #expect(!DICOMwebUPSHelpers.eventTypeSFSymbol(for: type).isEmpty)
        }
    }

    // MARK: - DICOMwebPerformanceHelpers

    @Test("DICOMwebPerformanceHelpers formattedLatency 0.5ms contains < 1")
    func testPerformanceHelpersFormattedLatencySubMs() {
        let result = DICOMwebPerformanceHelpers.formattedLatency(0.5)
        #expect(result.contains("< 1") || result.contains("ms"))
    }

    @Test("DICOMwebPerformanceHelpers formattedLatency 1500ms contains s")
    func testPerformanceHelpersFormattedLatencySeconds() {
        let result = DICOMwebPerformanceHelpers.formattedLatency(1500)
        #expect(result.contains("s"))
    }

    @Test("DICOMwebPerformanceHelpers formattedCompressionRatio contains ratio and x")
    func testPerformanceHelpersFormattedCompressionRatio() {
        let result = DICOMwebPerformanceHelpers.formattedCompressionRatio(2.5)
        #expect(result.contains("2.5"))
        #expect(result.contains("×"))
    }

    @Test("DICOMwebPerformanceHelpers formattedHitRate contains 85 and percent")
    func testPerformanceHelpersFormattedHitRate() {
        let result = DICOMwebPerformanceHelpers.formattedHitRate(0.853)
        #expect(result.contains("85") || result.contains("%"))
    }

    @Test("DICOMwebPerformanceHelpers http2StreamsDescription contains active and max counts")
    func testPerformanceHelpersHTTP2StreamsDescription() {
        let result = DICOMwebPerformanceHelpers.http2StreamsDescription(active: 12, max: 100)
        #expect(result.contains("12"))
        #expect(result.contains("100"))
    }

    @Test("DICOMwebPerformanceHelpers overallHealthDescription excellent for low error and latency")
    func testPerformanceHelpersHealthExcellent() {
        let stats = DICOMwebPerformanceStats(
            averageLatencyMs: 50,
            totalRequestCount: 100,
            errorCount: 0
        )
        #expect(DICOMwebPerformanceHelpers.overallHealthDescription(stats: stats) == "Excellent")
    }

    @Test("DICOMwebPerformanceHelpers overallHealthDescription poor for high error rate")
    func testPerformanceHelpersHealthPoor() {
        let stats = DICOMwebPerformanceStats(
            averageLatencyMs: 5000,
            totalRequestCount: 10,
            errorCount: 5
        )
        #expect(DICOMwebPerformanceHelpers.overallHealthDescription(stats: stats) == "Poor")
    }

    // MARK: - UPSEventPayloadParser

    @Test("UPSEventPayloadParser parses state from DICOM JSON")
    func testPayloadParserParsesState() throws {
        let json: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "stateReport")
        #expect(result.newState == "IN PROGRESS")
    }

    @Test("UPSEventPayloadParser infers previous state for IN PROGRESS transition")
    func testPayloadParserInfersPreviousStateInProgress() throws {
        let json: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "StateReport")
        #expect(result.previousState == "SCHEDULED")
        #expect(result.newState == "IN PROGRESS")
    }

    @Test("UPSEventPayloadParser infers previous state for COMPLETED transition")
    func testPayloadParserInfersPreviousStateCompleted() throws {
        let json: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["COMPLETED"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "StateReport")
        #expect(result.previousState == "IN PROGRESS")
        #expect(result.newState == "COMPLETED")
    }

    @Test("UPSEventPayloadParser parses progress percentage and description")
    func testPayloadParserParsesProgress() throws {
        let json: [String: Any] = [
            "00741004": ["vr": "DS", "Value": ["75"]],
            "00741006": ["vr": "ST", "Value": ["Processing series 3 of 4"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "ProgressReport")
        #expect(result.progressPercentage == 75)
        #expect(result.progressDescription == "Processing series 3 of 4")
    }

    @Test("UPSEventPayloadParser parses progress percentage as integer")
    func testPayloadParserParsesProgressInt() throws {
        let json: [String: Any] = [
            "00741004": ["vr": "DS", "Value": [50]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "ProgressReport")
        #expect(result.progressPercentage == 50)
    }

    @Test("UPSEventPayloadParser parses cancellation reason")
    func testPayloadParserParsesCancellationReason() throws {
        let json: [String: Any] = [
            "00741238": ["vr": "LT", "Value": ["Patient declined procedure"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "CancelRequested")
        #expect(result.reason == "Patient declined procedure")
    }

    @Test("UPSEventPayloadParser parses state change reason")
    func testPayloadParserParsesStateChangeReason() throws {
        let json: [String: Any] = [
            "00741000": ["vr": "CS", "Value": ["IN PROGRESS"]],
            "ReasonForStateChange": ["vr": "LO", "Value": ["Started by technologist"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "StateReport")
        #expect(result.reason == "Started by technologist")
        #expect(result.newState == "IN PROGRESS")
    }

    @Test("UPSEventPayloadParser parses contact from performer sequence")
    func testPayloadParserParsesPerformerContact() throws {
        let json: [String: Any] = [
            "00404035": ["vr": "SQ", "Value": [
                ["00404037": ["vr": "PN", "Value": ["Dr. Smith"]]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "Assigned")
        #expect(result.contactDisplayName == "Dr. Smith")
    }

    @Test("UPSEventPayloadParser parses contact from ContactDisplayName field")
    func testPayloadParserParsesContactDisplayName() throws {
        let json: [String: Any] = [
            "ContactDisplayName": ["vr": "LO", "Value": ["TechStation-01"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "ProgressReport")
        #expect(result.contactDisplayName == "TechStation-01")
    }

    @Test("UPSEventPayloadParser returns empty for empty data")
    func testPayloadParserEmptyData() {
        let result = UPSEventPayloadParser.parse(rawJSON: Data(), eventType: "stateReport")
        #expect(result.newState == nil)
        #expect(result.progressPercentage == nil)
        #expect(result.reason == nil)
    }

    @Test("UPSEventPayloadParser returns empty for invalid JSON")
    func testPayloadParserInvalidJSON() {
        let result = UPSEventPayloadParser.parse(rawJSON: Data("not json".utf8), eventType: "stateReport")
        #expect(result.newState == nil)
    }

    @Test("UPSEventPayloadParser parses completion notes as reason")
    func testPayloadParserCompletionNotes() throws {
        let json: [String: Any] = [
            "CompletionNotes": ["vr": "ST", "Value": ["All series processed successfully"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "Completed")
        #expect(result.reason == "All series processed successfully")
    }

    // MARK: - UPSEventDetailHelpers

    @Test("UPSEventDetailHelpers workitemContextDescription with full context")
    func testEventDetailHelpersFullContext() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            summary: "State changed",
            patientName: "John Doe",
            patientID: "P12345",
            procedureStepLabel: "CT Chest",
            workitemState: "IN PROGRESS",
            workitemPriority: "MEDIUM",
            accessionNumber: "ACC001",
            isWorkitemContextLoaded: true
        )
        let desc = UPSEventDetailHelpers.workitemContextDescription(event)
        #expect(desc != nil)
        #expect(desc!.contains("CT Chest"))
        #expect(desc!.contains("John Doe"))
        #expect(desc!.contains("P12345"))
        #expect(desc!.contains("IN PROGRESS"))
        #expect(desc!.contains("MEDIUM"))
        #expect(desc!.contains("ACC001"))
    }

    @Test("UPSEventDetailHelpers workitemContextDescription returns nil when not loaded")
    func testEventDetailHelpersNotLoaded() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            summary: "State changed"
        )
        #expect(UPSEventDetailHelpers.workitemContextDescription(event) == nil)
    }

    @Test("UPSEventDetailHelpers workitemContextDescription returns nil for loaded but empty context")
    func testEventDetailHelpersEmptyContext() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            summary: "State changed",
            isWorkitemContextLoaded: true
        )
        #expect(UPSEventDetailHelpers.workitemContextDescription(event) == nil)
    }

    @Test("UPSEventDetailHelpers workitemShortIdentifier prefers label")
    func testEventDetailHelpersShortIDLabel() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            patientName: "Jane Doe",
            procedureStepLabel: "MRI Brain",
            isWorkitemContextLoaded: true
        )
        #expect(UPSEventDetailHelpers.workitemShortIdentifier(event) == "MRI Brain")
    }

    @Test("UPSEventDetailHelpers workitemShortIdentifier falls back to patient name with ID")
    func testEventDetailHelpersShortIDPatient() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            patientName: "Jane Doe",
            patientID: "P999",
            isWorkitemContextLoaded: true
        )
        #expect(UPSEventDetailHelpers.workitemShortIdentifier(event) == "Jane Doe (P999)")
    }

    @Test("UPSEventDetailHelpers workitemShortIdentifier returns nil when no context")
    func testEventDetailHelpersShortIDNil() {
        let event = UPSReceivedEvent(
            eventType: .stateChange,
            workitemUID: "1.2.3.4",
            isWorkitemContextLoaded: true
        )
        #expect(UPSEventDetailHelpers.workitemShortIdentifier(event) == nil)
    }

    @Test("UPSEventDetailHelpers stateTransitionSFSymbol for known states")
    func testEventDetailHelpersStateTransitionSymbol() {
        #expect(UPSEventDetailHelpers.stateTransitionSFSymbol(newState: "SCHEDULED") == "calendar")
        #expect(UPSEventDetailHelpers.stateTransitionSFSymbol(newState: "IN PROGRESS") == "arrow.triangle.2.circlepath")
        #expect(UPSEventDetailHelpers.stateTransitionSFSymbol(newState: "COMPLETED") == "checkmark.circle.fill")
        #expect(UPSEventDetailHelpers.stateTransitionSFSymbol(newState: "CANCELED") == "xmark.circle.fill")
        #expect(UPSEventDetailHelpers.stateTransitionSFSymbol(newState: nil) == "arrow.left.arrow.right")
    }

    @Test("UPSEventDetailHelpers stateTransitionColor for known states")
    func testEventDetailHelpersStateTransitionColor() {
        #expect(UPSEventDetailHelpers.stateTransitionColor(newState: "SCHEDULED") == ".blue")
        #expect(UPSEventDetailHelpers.stateTransitionColor(newState: "IN PROGRESS") == ".orange")
        #expect(UPSEventDetailHelpers.stateTransitionColor(newState: "COMPLETED") == ".green")
        #expect(UPSEventDetailHelpers.stateTransitionColor(newState: "CANCELED") == ".red")
        #expect(UPSEventDetailHelpers.stateTransitionColor(newState: nil) == ".secondary")
    }


    // MARK: - Change Workitem State refusals (PS3.18 2026a 11.7.1.4; PS3.4 2026a Table CC.1.1-2)

    @Test("DICOMwebUPSHelpers availableTransitions from scheduled is IN PROGRESS only (Table CC.1.1-2)")
    func testUPSHelpersAvailableTransitionsScheduled() {
        #expect(DICOMwebUPSHelpers.availableTransitions(from: .scheduled) == [.inProgress])
        #expect(DICOMwebUPSHelpers.canTransition(from: .scheduled, to: .canceled) == false)
    }

    @Test("DICOMwebUPSHelpers changeStateRefusal for a SCHEDULED target is the dicom-wado message")
    func testUPSHelpersChangeStateRefusalScheduledTarget() {
        let expected = "SCHEDULED is not a Change Workitem State target: PS3.18 2026a 11.7.1.4 "
            + "allows IN PROGRESS, COMPLETED or CANCELED, and PS3.4 2026a Table CC.1.1-2 refuses a change "
            + "to SCHEDULED (C303H)"
        for from in WebUPSState.allCases {
            #expect(DICOMwebUPSHelpers.changeStateRefusal(from: from, to: .scheduled) == expected)
        }
    }

    @Test("DICOMwebUPSHelpers changeStateRefusal is nil for the allowed Table CC.1.1-2 transitions")
    func testUPSHelpersChangeStateRefusalAllowed() {
        #expect(DICOMwebUPSHelpers.changeStateRefusal(from: .scheduled, to: .inProgress) == nil)
        #expect(DICOMwebUPSHelpers.changeStateRefusal(from: .inProgress, to: .completed) == nil)
        #expect(DICOMwebUPSHelpers.changeStateRefusal(from: .inProgress, to: .canceled) == nil)
    }

    @Test("DICOMwebUPSHelpers changeStateRefusal names the Table CC.1.1-2 status code")
    func testUPSHelpersChangeStateRefusalCodes() throws {
        let c310 = try #require(DICOMwebUPSHelpers.changeStateRefusal(from: .scheduled, to: .canceled))
        #expect(c310.contains("C310H"))
        #expect(c310.contains("SCHEDULED to CANCELED"))
        let c300 = try #require(DICOMwebUPSHelpers.changeStateRefusal(from: .completed, to: .canceled))
        #expect(c300.contains("C300H"))
        let b306 = try #require(DICOMwebUPSHelpers.changeStateRefusal(from: .completed, to: .completed))
        #expect(b306.contains("B306H"))
        let c302 = try #require(DICOMwebUPSHelpers.changeStateRefusal(from: .inProgress, to: .inProgress))
        #expect(c302.contains("C302H"))
    }


    // MARK: - UPSEventPayloadParser vs PS3.4 2026a Table CC.2.4-1 (NEMA pins)

    @Test("UPSEventPayloadParser reads progress nested in Procedure Step Progress Information Sequence (0074,1002)")
    func testPayloadParserNestedProgress() throws {
        let json: [String: Any] = [
            "00741002": ["vr": "SQ", "Value": [[
                "00741004": ["vr": "DS", "Value": ["42"]],
                "00741006": ["vr": "ST", "Value": ["Reconstructing"]],
                "00741008": ["vr": "SQ", "Value": [[
                    "0074100A": ["vr": "UR", "Value": ["mailto:tech@example.org"]],
                    "0074100C": ["vr": "LO", "Value": ["Tech on duty"]]
                ]]]
            ]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "ProgressReport")
        #expect(result.progressPercentage == 42)
        #expect(result.progressDescription == "Reconstructing")
        #expect(result.contactDisplayName == "Tech on duty")
    }

    @Test("UPSEventPayloadParser reads Contact Display Name (0074,100C) of a Cancel Requested report")
    func testPayloadParserCancelRequestedContact() throws {
        let json: [String: Any] = [
            "00741236": ["vr": "AE", "Value": ["WORKSTATION1"]],
            "00741238": ["vr": "LT", "Value": ["Wrong patient"]],
            "0074100C": ["vr": "LO", "Value": ["Dr. Who"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "CancelRequested")
        #expect(result.reason == "Wrong patient")
        #expect(result.contactDisplayName == "Dr. Who")
    }

    @Test("UPSEventPayloadParser reads the Human Performer Code Sequence meaning of a UPS Assigned report")
    func testPayloadParserAssignedPerformer() throws {
        let json: [String: Any] = [
            "00404009": ["vr": "SQ", "Value": [[
                "00080100": ["vr": "SH", "Value": ["RAD1"]],
                "00080102": ["vr": "SH", "Value": ["99LOCAL"]],
                "00080104": ["vr": "LO", "Value": ["Radiologist One"]]
            ]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "Assigned")
        #expect(result.contactDisplayName == "Radiologist One")
    }

    @Test("UPSEventPayloadParser infers IN PROGRESS before CANCELED (Table CC.1.1-2: Request Cancel of a SCHEDULED UPS reports IN PROGRESS first)")
    func testPayloadParserInfersPreviousStateCanceled() throws {
        let json: [String: Any] = ["00741000": ["vr": "CS", "Value": ["CANCELED"]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "StateReport")
        #expect(result.previousState == "IN PROGRESS")
        #expect(result.newState == "CANCELED")
    }

    @Test("UPSEventPayloadParser does not invent a previous state for SCHEDULED (only N-CREATE enters it)")
    func testPayloadParserNoPreviousStateForScheduled() throws {
        let json: [String: Any] = ["00741000": ["vr": "CS", "Value": ["SCHEDULED"]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = UPSEventPayloadParser.parse(rawJSON: data, eventType: "StateReport")
        #expect(result.previousState == nil)
    }
}
