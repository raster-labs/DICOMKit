import Foundation

/// Builder for constructing DICOMweb URLs
///
/// Provides utilities for building standard DICOMweb endpoint URLs
/// according to PS3.18 specification.
///
/// NEMA-verified: 2026a, checked 2026-09-28 — URI templates diffed against PS3.18 2026a
/// Tables 10.4.1-1..4, 10.4.1.5-1, 10.5.1-1, 10.6.1-1, 11.1.1-1, 11.4.1-1, 11.10.1-1 and
/// 11.12.1-1; query parameter names against Tables 8.3.4-1, 8.3.5-1, 8.3.5-2, 10.4.1-5,
/// 11.7.2.1-1 and 11.10.1-2; window/viewport syntax per 8.3.5.1.3 and 8.3.5.1.4. The
/// `/bulkdata/{attributePath}`, `/state/{requestingAE}`, `/cancelrequest/{requestingAE}`
/// and `/ws/subscribers` paths are dcm4chee conventions, not PS3.18 templates.
///
/// Reference: PS3.18 Section 10.1 (Studies Service resources), 11.1 (Worklist Service resources)
public struct DICOMwebURLBuilder: Sendable {
    /// The base URL of the DICOMweb server
    public let baseURL: URL
    
    /// Creates a URL builder with the specified base URL
    /// - Parameter baseURL: The base URL of the DICOMweb server
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    /// Creates a URL builder from a string URL
    /// - Parameter baseURLString: The base URL string
    /// - Throws: DICOMwebError.invalidURL if the string is not a valid URL
    public init(baseURLString: String) throws {
        guard let url = URL(string: baseURLString) else {
            throw DICOMwebError.invalidURL(url: baseURLString)
        }
        self.baseURL = url
    }
    
    // MARK: - Studies Resource URLs
    
    /// URL for the studies endpoint
    /// - Returns: URL for `/studies`
    public var studiesURL: URL {
        return baseURL.appendingPathComponent("studies")
    }
    
    /// URL for a specific study
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}`
    public func studyURL(studyUID: String) -> URL {
        return studiesURL.appendingPathComponent(studyUID)
    }
    
    /// URL for study metadata
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}/metadata`
    public func studyMetadataURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID).appendingPathComponent("metadata")
    }
    
    /// URL for study rendered representation
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}/rendered`
    public func studyRenderedURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID).appendingPathComponent("rendered")
    }
    
    /// URL for study thumbnail
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}/thumbnail`
    public func studyThumbnailURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID).appendingPathComponent("thumbnail")
    }
    
    // MARK: - Series Resource URLs
    
    /// URL for series within a study
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series`
    public func seriesURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID).appendingPathComponent("series")
    }
    
    /// URL for a specific series
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}`
    public func seriesURL(studyUID: String, seriesUID: String) -> URL {
        return seriesURL(studyUID: studyUID).appendingPathComponent(seriesUID)
    }
    
    /// URL for series metadata
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/metadata`
    public func seriesMetadataURL(studyUID: String, seriesUID: String) -> URL {
        return seriesURL(studyUID: studyUID, seriesUID: seriesUID)
            .appendingPathComponent("metadata")
    }
    
    /// URL for series rendered representation
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/rendered`
    public func seriesRenderedURL(studyUID: String, seriesUID: String) -> URL {
        return seriesURL(studyUID: studyUID, seriesUID: seriesUID)
            .appendingPathComponent("rendered")
    }
    
    /// URL for series thumbnail
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/thumbnail`
    public func seriesThumbnailURL(studyUID: String, seriesUID: String) -> URL {
        return seriesURL(studyUID: studyUID, seriesUID: seriesUID)
            .appendingPathComponent("thumbnail")
    }
    
    // MARK: - Instances Resource URLs
    
    /// URL for instances within a study (across all series)
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `/studies/{studyUID}/instances`
    public func instancesInStudyURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID).appendingPathComponent("instances")
    }
    
    /// URL for instances within a series
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances`
    public func instancesURL(studyUID: String, seriesUID: String) -> URL {
        return seriesURL(studyUID: studyUID, seriesUID: seriesUID)
            .appendingPathComponent("instances")
    }
    
    /// URL for a specific instance
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}`
    public func instanceURL(studyUID: String, seriesUID: String, instanceUID: String) -> URL {
        return instancesURL(studyUID: studyUID, seriesUID: seriesUID)
            .appendingPathComponent(instanceUID)
    }
    
    /// URL for instance metadata
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/metadata`
    public func instanceMetadataURL(studyUID: String, seriesUID: String, instanceUID: String) -> URL {
        return instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
            .appendingPathComponent("metadata")
    }
    
    /// URL for instance rendered representation
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/rendered`
    public func instanceRenderedURL(studyUID: String, seriesUID: String, instanceUID: String) -> URL {
        return instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
            .appendingPathComponent("rendered")
    }
    
    /// URL for instance thumbnail
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/thumbnail`
    public func instanceThumbnailURL(studyUID: String, seriesUID: String, instanceUID: String) -> URL {
        return instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
            .appendingPathComponent("thumbnail")
    }
    
    // MARK: - Frames Resource URLs
    
    /// URL for specific frames of an instance
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frames: Array of frame numbers (1-based)
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frameList}`
    public func framesURL(studyUID: String, seriesUID: String, instanceUID: String, frames: [Int]) -> URL {
        let frameList = frames.map { String($0) }.joined(separator: ",")
        return instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
            .appendingPathComponent("frames")
            .appendingPathComponent(frameList)
    }
    
    /// URL for rendered frames
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frames: Array of frame numbers (1-based)
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frameList}/rendered`
    public func framesRenderedURL(studyUID: String, seriesUID: String, instanceUID: String, frames: [Int]) -> URL {
        return framesURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, frames: frames)
            .appendingPathComponent("rendered")
    }
    
    /// URL for frame thumbnails
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - frames: Array of frame numbers (1-based)
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/frames/{frameList}/thumbnail`
    public func framesThumbnailURL(studyUID: String, seriesUID: String, instanceUID: String, frames: [Int]) -> URL {
        return framesURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID, frames: frames)
            .appendingPathComponent("thumbnail")
    }
    
    // MARK: - Bulk Data URLs
    
    /// URL for bulk data retrieval
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - instanceUID: The SOP Instance UID
    ///   - attributePath: The attribute path (e.g., "00080018" for SOP Instance UID)
    /// - Returns: URL for `/studies/{studyUID}/series/{seriesUID}/instances/{instanceUID}/bulkdata/{attributePath}`
    public func bulkdataURL(studyUID: String, seriesUID: String, instanceUID: String, attributePath: String) -> URL {
        return instanceURL(studyUID: studyUID, seriesUID: seriesUID, instanceUID: instanceUID)
            .appendingPathComponent("bulkdata")
            .appendingPathComponent(attributePath)
    }
    
    // MARK: - STOW-RS URLs
    
    /// URL for storing instances (STOW-RS)
    /// - Returns: URL for `POST /studies`
    public var storeURL: URL {
        return studiesURL
    }
    
    /// URL for storing instances to a specific study (STOW-RS)
    /// - Parameter studyUID: The Study Instance UID
    /// - Returns: URL for `POST /studies/{studyUID}`
    public func storeURL(studyUID: String) -> URL {
        return studyURL(studyUID: studyUID)
    }
    
    // MARK: - URL with Query Parameters
    
    /// Appends query parameters to a URL
    /// - Parameters:
    ///   - url: The base URL
    ///   - parameters: Dictionary of query parameters
    /// - Returns: URL with query string appended
    public static func appendQueryParameters(to url: URL, parameters: [String: String]) -> URL {
        guard !parameters.isEmpty else { return url }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        components?.queryItems = queryItems
        return components?.url ?? url
    }
    
    /// Creates a QIDO-RS search URL with query parameters
    /// - Parameter parameters: Search parameters
    /// - Returns: URL for studies search
    public func searchStudiesURL(parameters: [String: String]) -> URL {
        return Self.appendQueryParameters(to: studiesURL, parameters: parameters)
    }
    
    /// Creates a QIDO-RS search URL for series with query parameters
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - parameters: Search parameters
    /// - Returns: URL for series search
    public func searchSeriesURL(studyUID: String, parameters: [String: String]) -> URL {
        return Self.appendQueryParameters(to: seriesURL(studyUID: studyUID), parameters: parameters)
    }
    
    /// Creates a QIDO-RS search URL for instances with query parameters
    /// - Parameters:
    ///   - studyUID: The Study Instance UID
    ///   - seriesUID: The Series Instance UID
    ///   - parameters: Search parameters
    /// - Returns: URL for instances search
    public func searchInstancesURL(studyUID: String, seriesUID: String, parameters: [String: String]) -> URL {
        return Self.appendQueryParameters(
            to: instancesURL(studyUID: studyUID, seriesUID: seriesUID),
            parameters: parameters
        )
    }
}

// MARK: - Viewport and Window Query Parameters

extension DICOMwebURLBuilder {
    /// Standard query parameter names for DICOMweb
    public enum QueryParameter {
        // MARK: - QIDO-RS Parameters
        
        /// Limit number of results
        public static let limit = "limit"
        
        /// Offset for pagination
        public static let offset = "offset"
        
        /// Include field in response (can be repeated)
        public static let includefield = "includefield"
        
        /// Fuzzy matching for patient name
        public static let fuzzymatching = "fuzzymatching"
        
        /// Empty Value Matching (PS3.18 8.3.4.5)
        public static let emptyvaluematching = "emptyvaluematching"
        
        /// Multiple Value Matching (PS3.18 8.3.4.6)
        public static let multiplevaluematching = "multiplevaluematching"
        
        // MARK: - Rendered Image Parameters (PS3.18 Table 8.3.5-1)
        
        /// Windowing: `window=center,width,function` (PS3.18 8.3.5.1.4)
        public static let window = "window"
        
        /// Viewport scaling: `viewport=vw,vh[,sx,sy,sw,sh]` (PS3.18 8.3.5.1.3)
        public static let viewport = "viewport"
        
        /// Quality (1-100) for lossy compression (PS3.18 8.3.5.1.2)
        public static let quality = "quality"
        
        /// ICC Profile for color management (PS3.18 8.3.5.1.5)
        public static let iccprofile = "iccprofile"
        
        /// Annotation types (PS3.18 8.3.5.1.1)
        public static let annotation = "annotation"
        
        /// Not PS3.18 parameters: the RESTful Retrieve Rendered Transaction takes `window`
        /// and `viewport` (8.3.5.1.3, 8.3.5.1.4); the URI Service (Chapter 9) takes
        /// `windowCenter`, `windowWidth`, `rows` and `columns`, which `WADOURIClient` sends.
        @available(*, deprecated, renamed: "window", message: "PS3.18 8.3.5.1.4: use window=center,width,function")
        public static let windowCenter = "windowcenter"
        
        @available(*, deprecated, renamed: "window", message: "PS3.18 8.3.5.1.4: use window=center,width,function")
        public static let windowWidth = "windowwidth"
        
        @available(*, deprecated, renamed: "viewport", message: "PS3.18 8.3.5.1.3: use viewport=vw,vh")
        public static let viewportWidth = "columns"
        
        @available(*, deprecated, renamed: "viewport", message: "PS3.18 8.3.5.1.3: use viewport=vw,vh")
        public static let viewportHeight = "rows"
        
        // MARK: - WADO-RS Parameters
        
        /// Accept parameter (PS3.18 8.3.3.1)
        public static let accept = "accept"
        
        /// Character set parameter (PS3.18 8.3.3.2)
        public static let charset = "charset"
        
        // MARK: - UPS-RS Parameters
        
        /// Deletion Lock on Subscribe (PS3.18 11.10.1.2)
        public static let deletionlock = "deletionlock"
        
        /// Requesting AE Title on Change State / Request Cancellation (PS3.18 Table 11.7.2.1-1)
        public static let requester = "requester"
        
        // MARK: - DICOM Attribute Tags (Common)
        
        /// Patient ID (0010,0020)
        public static let patientID = "00100020"
        
        /// Patient Name (0010,0010)
        public static let patientName = "00100010"
        
        /// Study Date (0008,0020)
        public static let studyDate = "00080020"
        
        /// Study Instance UID (0020,000D)
        public static let studyInstanceUID = "0020000D"
        
        /// Series Instance UID (0020,000E)
        public static let seriesInstanceUID = "0020000E"
        
        /// SOP Instance UID (0008,0018)
        public static let sopInstanceUID = "00080018"
        
        /// Modality (0008,0060)
        public static let modality = "00080060"
        
        /// Accession Number (0008,0050)
        public static let accessionNumber = "00080050"
    }
    
    /// Creates rendered URL with viewport and windowing parameters
    ///
    /// Emits `window=center,width,linear` when both window values are given (PS3.18
    /// 8.3.5.1.4: all three shall be present), `viewport=vw,vh` when both viewport values
    /// are given (8.3.5.1.3), and `quality` clamped to 1-100 (8.3.5.1.2).
    ///
    /// - Parameters:
    ///   - baseRenderedURL: The base rendered URL
    ///   - windowCenter: Window center value
    ///   - windowWidth: Window width value
    ///   - viewportWidth: Viewport width in pixels
    ///   - viewportHeight: Viewport height in pixels
    ///   - quality: Quality value (1-100) for lossy formats
    /// - Returns: URL with query parameters
    public static func renderedURL(
        base baseRenderedURL: URL,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        quality: Int? = nil
    ) -> URL {
        return appendQueryParameters(to: baseRenderedURL, parameters: renderedParameters(
            windowCenter: windowCenter, windowWidth: windowWidth,
            viewportWidth: viewportWidth, viewportHeight: viewportHeight, quality: quality))
    }
    
    /// The PS3.18 Table 8.3.5-1 query parameters for a rendered resource
    static func renderedParameters(
        windowCenter: Double?, windowWidth: Double?, viewportWidth: Int?, viewportHeight: Int?, quality: Int?
    ) -> [String: String] {
        var params: [String: String] = [:]
        if let wc = windowCenter, let ww = windowWidth {
            params[QueryParameter.window] = "\(decimal(wc)),\(decimal(ww)),linear"
        }
        if let vw = viewportWidth, let vh = viewportHeight {
            params[QueryParameter.viewport] = "\(vw),\(vh)"
        }
        if let q = quality {
            params[QueryParameter.quality] = String(min(100, max(1, q)))
        }
        return params
    }
    
    /// A decimal without a trailing ".0" (PS3.18 5.1.1 decimal)
    private static func decimal(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

// MARK: - UPS-RS (Unified Procedure Step) URLs

extension DICOMwebURLBuilder {
    
    /// URL for the workitems endpoint
    /// - Returns: URL for `/workitems`
    ///
    /// Reference: PS3.18 Table 11.1.1-1 - Worklist Service resources
    public var workitemsURL: URL {
        return baseURL.appendingPathComponent("workitems")
    }
    
    /// URL for a specific workitem
    /// - Parameter workitemUID: The workitem's SOP Instance UID
    /// - Returns: URL for `/workitems/{workitemUID}`
    public func workitemURL(workitemUID: String) -> URL {
        return workitemsURL.appendingPathComponent(workitemUID)
    }
    
    /// URL for creating a workitem with a client-specified UID
    /// - Parameter workitemUID: The workitem's SOP Instance UID
    /// - Returns: URL for `/workitems?workitem={workitemUID}`
    ///
    /// Per PS3.18 Section 11.4, Create uses a query parameter, not a path segment.
    public func createWorkitemURL(workitemUID: String) -> URL {
        var components = URLComponents(url: workitemsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "workitem", value: workitemUID)
        ]
        return components.url!
    }
    
    /// URL for updating a workitem with Transaction UID query parameter
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID
    ///   - transactionUID: The Transaction UID of the claimed workitem
    /// - Returns: URL for `/workitems/{workitemUID}?00081195={transactionUID}`
    ///
    /// Per PS3.18 §11.6.1, the Update Workitem Transaction uses POST with the
    /// Transaction UID as a query parameter.  The parameter name uses the DICOM
    /// tag keyword ``00081195`` (Transaction UID) which is the format expected by
    /// most UPS-RS implementations including dcm4chee-arc.
    public func updateWorkitemURL(workitemUID: String, transactionUID: String) -> URL {
        var components = URLComponents(url: workitemURL(workitemUID: workitemUID), resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "00081195", value: transactionUID)
        ]
        return components.url!
    }

    /// URL for workitem state changes
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID
    ///   - requestingAE: Optional Requesting AE Title appended as a path segment
    ///   - transactionUID: Optional Transaction UID appended as query parameter `00081195`
    /// - Returns: URL for `/workitems/{workitemUID}/state[/{requestingAE}][?00081195={transactionUID}]`
    ///
    /// Per PS3.18 §11.6, the Requesting AE may be included as the last path segment.
    /// Some servers (e.g. dcm4chee-arc) require it.  The Transaction UID is also
    /// required as a query parameter by dcm4chee-arc for state transitions from
    /// IN PROGRESS to COMPLETED or CANCELED.
    public func workitemStateURL(workitemUID: String, requestingAE: String? = nil, transactionUID: String? = nil) -> URL {
        var stateURL = workitemURL(workitemUID: workitemUID).appendingPathComponent("state")
        if let ae = requestingAE, !ae.isEmpty {
            stateURL = stateURL.appendingPathComponent(ae)
        }
        if let txUID = transactionUID, !txUID.isEmpty {
            var components = URLComponents(url: stateURL, resolvingAgainstBaseURL: false)!
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "00081195", value: txUID)
            ]
            return components.url!
        }
        return stateURL
    }
    
    /// URL for workitem cancellation requests
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID
    ///   - requestingAE: Optional Requesting AE Title appended as a path segment
    /// - Returns: URL for `/workitems/{workitemUID}/cancelrequest` or `/workitems/{workitemUID}/cancelrequest/{requestingAE}`
    ///
    /// Per PS3.18 §11.7, the Requesting AE may be included as the last path segment.
    /// Some servers (e.g. dcm4chee-arc) require it.
    public func workitemCancelRequestURL(workitemUID: String, requestingAE: String? = nil) -> URL {
        let cancelURL = workitemURL(workitemUID: workitemUID).appendingPathComponent("cancelrequest")
        if let ae = requestingAE, !ae.isEmpty {
            return cancelURL.appendingPathComponent(ae)
        }
        return cancelURL
    }
    
    /// URL for workitem subscription
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID
    ///   - aeTitle: The subscribing AE Title
    /// - Returns: URL for `/workitems/{workitemUID}/subscribers/{aeTitle}`
    public func workitemSubscriptionURL(workitemUID: String, aeTitle: String) -> URL {
        return workitemURL(workitemUID: workitemUID)
            .appendingPathComponent("subscribers")
            .appendingPathComponent(aeTitle)
    }
    
    /// Well-known UID of the Worklist (global) Subscription (PS3.18 Table 11.1.1-1; PS3.6 Table A-1)
    public static let globalSubscriptionUID = "1.2.840.10008.5.1.4.34.5"
    
    /// Well-known UID of the Filtered Worklist Subscription (PS3.18 Table 11.1.1-1; PS3.6 Table A-1)
    public static let filteredGlobalSubscriptionUID = "1.2.840.10008.5.1.4.34.5.1"
    
    /// URL for global workitem subscription (subscribe to all workitems)
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Returns: URL for `/workitems/1.2.840.10008.5.1.4.34.5/subscribers/{aeTitle}`
    public func globalWorkitemSubscriptionURL(aeTitle: String) -> URL {
        return workitemSubscriptionURL(workitemUID: Self.globalSubscriptionUID, aeTitle: aeTitle)
    }
    
    /// URL for a filtered worklist subscription (PS3.18 Table 11.10.1-1; `filter` is added by the caller)
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Returns: URL for `/workitems/1.2.840.10008.5.1.4.34.5.1/subscribers/{aeTitle}`
    public func filteredGlobalWorkitemSubscriptionURL(aeTitle: String) -> URL {
        return workitemSubscriptionURL(workitemUID: Self.filteredGlobalSubscriptionUID, aeTitle: aeTitle)
    }
    
    /// URL for suspending the global subscription (PS3.18 Table 11.12.1-1)
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Returns: URL for `/workitems/1.2.840.10008.5.1.4.34.5/subscribers/{aeTitle}/suspend`
    public func globalWorkitemSubscriptionSuspendURL(aeTitle: String) -> URL {
        return workitemSubscriptionSuspendURL(workitemUID: Self.globalSubscriptionUID, aeTitle: aeTitle)
    }
    
    /// URL for suspending a workitem subscription
    /// - Parameters:
    ///   - workitemUID: The workitem's SOP Instance UID
    ///   - aeTitle: The subscribing AE Title
    /// - Returns: URL for `/workitems/{workitemUID}/subscribers/{aeTitle}/suspend`
    public func workitemSubscriptionSuspendURL(workitemUID: String, aeTitle: String) -> URL {
        return workitemSubscriptionURL(workitemUID: workitemUID, aeTitle: aeTitle)
            .appendingPathComponent("suspend")
    }
    
    /// Creates a UPS-RS search URL with query parameters
    /// - Parameter parameters: Search parameters
    /// - Returns: URL for workitems search
    public func searchWorkitemsURL(parameters: [String: String]) -> URL {
        return Self.appendQueryParameters(to: workitemsURL, parameters: parameters)
    }
    
    /// WebSocket URL for the UPS event channel
    ///
    /// Converts the HTTP(S) base URL to a WS(S) URL and appends
    /// the event channel subscriber path.
    ///
    /// - Parameter aeTitle: The subscribing AE Title
    /// - Returns: URL for `ws[s]://<server>/ws/subscribers/{aeTitle}`
    ///
    /// Reference: PS3.18 §8.10.4 - Open Notification Connection Transaction (the URL of
    /// the WebSocket endpoint is left to the origin server; `/ws/subscribers` is dcm4chee's)
    public func webSocketEventChannelURL(aeTitle: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }
        
        // The WebSocket endpoint is a sibling of the REST endpoint, not a child.
        // Strip trailing /rs (or similar DICOMweb service suffix) so /ws is a sibling.
        var basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let serviceSuffixes = ["/rs", "/wado-rs", "/stow-rs"]
        for suffix in serviceSuffixes {
            if basePath.lowercased().hasSuffix(suffix) {
                basePath = String(basePath.dropLast(suffix.count))
                break
            }
        }
        components.path = "\(basePath)/ws/subscribers/\(aeTitle)"
        
        return components.url
    }
}
