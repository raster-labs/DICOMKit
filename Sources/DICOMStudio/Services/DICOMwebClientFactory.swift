// DICOMwebClientFactory.swift
// DICOMStudio
// NEMA-verified: 2026a, checked 2026-10-06 — makeConfiguration(from:timeouts:) is plumbing (PS3.18 names no timeout; D260); buildQIDOQuery keys diffed against PS3.18 2026a Table 10.6.1-5 (study level Modalities in Study (0008,0061), series/instance Modality (0008,0060) — corrected) and Table 8.3.4-1 (fuzzymatching, limit, offset — fuzzymatching now sent); open Study Date ranges against PS3.4 2026a C.2.2.2.5; the tags themselves are DICOMWeb.QIDOQueryAttribute (verified 2026-09-28); authentication is plumbing (PS3.18 8.11 names no mechanism); the profile TLS mode is passed as DICOMwebConfiguration.tlsProfile (PS3.15 2026a B.12 / B.13, P-STUDIO-TLS-PROFILES, 2026-10-06)
//
// DICOM Studio — Factory for creating DICOMwebClient instances from server profiles
// Reference: DICOM PS3.18 (Web Services)

import Foundation
import DICOMWeb

/// Creates `DICOMwebClient` instances from DICOMStudio `DICOMwebServerProfile` models.
///
/// Bridges the DICOMStudio display-layer profile configuration with the
/// DICOMWeb library's `DICOMwebConfiguration` and `DICOMwebClient` types.
public enum DICOMwebClientFactory: Sendable {

    /// Creates a `DICOMwebConfiguration` from a server profile.
    ///
    /// Use this when you need the raw configuration (e.g. for `UPSEventChannelManager`)
    /// rather than a full `DICOMwebClient`.
    ///
    /// - Parameters:
    ///   - profile: The DICOMweb server profile containing URL, auth, and TLS settings.
    ///   - timeouts: The request timeouts (default `.default`); the CLI Workshop passes the
    ///     `retrieve --timeout` mapping (`DICOMwebOptionRules.timeouts(seconds:)`, DICOMWeb) so the
    ///     configuration is built once instead of rebuilt around the profile's URL and auth (D260).
    /// - Throws: `DICOMwebError.invalidURL` if the profile's base URL is malformed.
    /// - Returns: A configured `DICOMwebConfiguration`.
    public static func makeConfiguration(
        from profile: DICOMwebServerProfile,
        timeouts: DICOMwebConfiguration.TimeoutConfiguration = .default
    ) throws -> DICOMwebConfiguration {
        guard let baseURL = URL(string: profile.baseURL) else {
            throw DICOMwebError.invalidURL(url: profile.baseURL)
        }

        let authentication = mapAuthentication(profile)

        return DICOMwebConfiguration(
            baseURL: baseURL,
            authentication: authentication,
            timeouts: timeouts,
            maxConcurrentRequests: 4,
            tlsProfile: profile.tlsMode.webTLSProfile
        )
    }

    /// Creates a `DICOMwebClient` from a server profile.
    ///
    /// - Parameter profile: The DICOMweb server profile containing URL, auth, and TLS settings.
    /// - Throws: `DICOMwebError.invalidURL` if the profile's base URL is malformed.
    /// - Returns: A configured `DICOMwebClient` ready for QIDO/WADO/STOW/UPS operations.
    public static func makeClient(from profile: DICOMwebServerProfile) throws -> DICOMwebClient {
        let configuration = try makeConfiguration(from: profile)
        return DICOMwebClient(configuration: configuration)
    }

    /// Maps a DICOMStudio auth method to the DICOMWeb library's `Authentication` type.
    private static func mapAuthentication(
        _ profile: DICOMwebServerProfile
    ) -> DICOMwebConfiguration.Authentication? {
        switch profile.authMethod {
        case .none:
            return nil
        case .bearer, .jwt:
            guard !profile.bearerToken.isEmpty else { return nil }
            return .bearer(token: profile.bearerToken)
        case .basic:
            guard !profile.username.isEmpty else { return nil }
            return .basic(username: profile.username, password: profile.password)
        case .oauth2PKCE:
            // OAuth2 PKCE requires a full OAuth2 flow; fall back to bearer if a token is present
            guard !profile.bearerToken.isEmpty else { return nil }
            return .bearer(token: profile.bearerToken)
        }
    }

    /// Creates a `WADOURIClient` from a server profile for WADO-URI (legacy) retrieval.
    ///
    /// WADO-URI uses query parameters (`?requestType=WADO&studyUID=...`) instead of
    /// RESTful path segments. Common for legacy PACS such as dcm4chee2.
    ///
    /// - Parameter profile: The DICOMweb server profile containing URL and auth settings.
    /// - Throws: `DICOMwebError.invalidURL` if the profile's base URL is malformed.
    /// - Returns: A configured `WADOURIClient` for WADO-URI operations.
    public static func makeWADOURIClient(from profile: DICOMwebServerProfile) throws -> WADOURIClient {
        guard let baseURL = URL(string: profile.baseURL) else {
            throw DICOMwebError.invalidURL(url: profile.baseURL)
        }

        let authentication = mapAuthentication(profile)

        let configuration = DICOMwebConfiguration(
            baseURL: baseURL,
            authentication: authentication,
            maxConcurrentRequests: 4,
            tlsProfile: profile.tlsMode.webTLSProfile
        )

        return WADOURIClient(configuration: configuration)
    }

    /// Builds a `QIDOQuery` from DICOMStudio `QIDOQueryParams`.
    ///
    /// Matching keys follow PS3.18 Table 10.6.1-5: at the study level the modality filter is
    /// Modalities in Study (0008,0061); at the series and instance levels it is Modality
    /// (0008,0060). A Study Date with only one bound is sent as the open range of PS3.4
    /// C.2.2.2.5 (`YYYYMMDD-` / `-YYYYMMDD`). `fuzzymatching=true` (PS3.18 8.3.4.2) is sent
    /// only when requested, since its absence already means false; `limit` and `offset`
    /// are the pagination parameters of PS3.18 8.3.4.4.
    public static func buildQIDOQuery(from params: QIDOQueryParams) -> QIDOQuery {
        var query = QIDOQuery()

        if !params.patientName.isEmpty {
            query = query.patientName(params.patientName)
        }
        if !params.patientID.isEmpty {
            query = query.patientID(params.patientID)
        }
        if !params.studyDateFrom.isEmpty, !params.studyDateTo.isEmpty {
            query = query.studyDate(from: params.studyDateFrom, to: params.studyDateTo)
        } else if !params.studyDateFrom.isEmpty {
            query = query.studyDateRange(from: params.studyDateFrom, to: nil)
        } else if !params.studyDateTo.isEmpty {
            query = query.studyDateRange(from: nil, to: params.studyDateTo)
        }
        if !params.modality.isEmpty {
            switch params.queryLevel {
            case .study:             query = query.modalitiesInStudy(params.modality)
            case .series, .instance: query = query.modality(params.modality)
            }
        }
        if params.fuzzyMatching {
            query = query.fuzzyMatching(true)
        }
        if !params.accessionNumber.isEmpty {
            query = query.accessionNumber(params.accessionNumber)
        }
        if !params.studyDescription.isEmpty {
            query = query.studyDescription(params.studyDescription)
        }
        if params.limit > 0 {
            query = query.limit(params.limit)
        }
        if params.offset > 0 {
            query = query.offset(params.offset)
        }

        return query
    }

    /// Converts `QIDOStudyResult` from the library to `QIDOResultItem` for display.
    public static func mapStudyResults(_ results: QIDOStudyResults) -> [QIDOResultItem] {
        results.results.map { study in
            QIDOResultItem(
                studyInstanceUID: study.studyInstanceUID ?? "",
                patientName: study.patientName ?? "",
                patientID: study.patientID ?? "",
                studyDate: study.studyDate ?? "",
                modality: study.modalitiesInStudy.joined(separator: ", "),
                studyDescription: study.studyDescription ?? "",
                numberOfSeries: study.numberOfStudyRelatedSeries,
                numberOfInstances: study.numberOfStudyRelatedInstances,
                queryLevel: .study
            )
        }
    }

    /// Converts `QIDOSeriesResult` from the library to `QIDOResultItem` for display.
    public static func mapSeriesResults(_ results: QIDOSeriesResults) -> [QIDOResultItem] {
        results.results.map { series in
            QIDOResultItem(
                studyInstanceUID: series.studyInstanceUID ?? "",
                seriesInstanceUID: series.seriesInstanceUID,
                patientName: "",
                patientID: "",
                studyDate: "",
                modality: series.modality ?? "",
                studyDescription: series.seriesDescription ?? "",
                numberOfInstances: series.numberOfSeriesRelatedInstances,
                queryLevel: .series
            )
        }
    }

    /// Converts `QIDOInstanceResult` from the library to `QIDOResultItem` for display.
    public static func mapInstanceResults(_ results: QIDOInstanceResults) -> [QIDOResultItem] {
        results.results.map { inst in
            QIDOResultItem(
                sopInstanceUID: inst.sopInstanceUID,
                patientName: "",
                patientID: "",
                studyDate: "",
                modality: "",
                studyDescription: "",
                queryLevel: .instance
            )
        }
    }
}
