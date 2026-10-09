// NEMA-verified: 2026a, checked 2026-10-01 — the 5 operation labels C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET are the DIMSE-C service names of PS3.7 2026a 9.1.1-9.1.5; the rest is counters and formatting (plumbing)
import Foundation

/// Server statistics tracking
actor ServerStatistics {
    // Connection statistics
    private(set) var totalConnections: Int = 0
    private(set) var activeConnections: Int = 0
    private(set) var failedConnections: Int = 0
    
    // DIMSE operation statistics
    private(set) var echoRequests: Int = 0
    private(set) var storeRequests: Int = 0
    private(set) var findRequests: Int = 0
    private(set) var moveRequests: Int = 0
    private(set) var getRequests: Int = 0
    
    // Success/failure counters
    private(set) var successfulStores: Int = 0
    private(set) var failedStores: Int = 0
    private(set) var successfulFinds: Int = 0
    private(set) var failedFinds: Int = 0
    private(set) var successfulMoves: Int = 0
    private(set) var failedMoves: Int = 0
    private(set) var successfulGets: Int = 0
    private(set) var failedGets: Int = 0
    
    // Bandwidth and storage
    private(set) var bytesReceived: Int64 = 0
    private(set) var bytesSent: Int64 = 0
    private(set) var totalStoredInstances: Int = 0
    
    // Timing
    let startTime: Date = Date()
    
    // MARK: - Connection Tracking
    
    func recordConnectionStart() {
        totalConnections += 1
        activeConnections += 1
    }
    
    func recordConnectionEnd() {
        activeConnections = max(0, activeConnections - 1)
    }
    
    func recordConnectionFailure() {
        failedConnections += 1
    }
    
    // MARK: - DIMSE Operations
    
    func recordEchoRequest() {
        echoRequests += 1
    }
    
    func recordStoreRequest(success: Bool, bytesReceived: Int64 = 0) {
        storeRequests += 1
        if success {
            successfulStores += 1
            self.bytesReceived += bytesReceived
            totalStoredInstances += 1
        } else {
            failedStores += 1
        }
    }
    
    func recordFindRequest(success: Bool) {
        findRequests += 1
        if success {
            successfulFinds += 1
        } else {
            failedFinds += 1
        }
    }
    
    func recordMoveRequest(success: Bool, instancesSent: Int = 0) {
        moveRequests += 1
        if success {
            successfulMoves += 1
        } else {
            failedMoves += 1
        }
    }
    
    func recordGetRequest(success: Bool, bytesSent: Int64 = 0) {
        getRequests += 1
        if success {
            successfulGets += 1
            self.bytesSent += bytesSent
        } else {
            failedGets += 1
        }
    }
    
    // MARK: - Statistics Summary
    
    func getSummary() -> StatisticsSummary {
        let uptime = Date().timeIntervalSince(startTime)
        
        return StatisticsSummary(
            // Connection stats
            totalConnections: totalConnections,
            activeConnections: activeConnections,
            failedConnections: failedConnections,
            
            // Operation stats
            echoRequests: echoRequests,
            storeRequests: storeRequests,
            findRequests: findRequests,
            moveRequests: moveRequests,
            getRequests: getRequests,
            
            // Success rates
            successfulStores: successfulStores,
            failedStores: failedStores,
            successfulFinds: successfulFinds,
            failedFinds: failedFinds,
            successfulMoves: successfulMoves,
            failedMoves: failedMoves,
            successfulGets: successfulGets,
            failedGets: failedGets,
            
            // Bandwidth
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            totalStoredInstances: totalStoredInstances,
            
            // Timing
            startTime: startTime,
            uptime: uptime
        )
    }
    
    func reset() {
        totalConnections = 0
        activeConnections = 0
        failedConnections = 0
        
        echoRequests = 0
        storeRequests = 0
        findRequests = 0
        moveRequests = 0
        getRequests = 0
        
        successfulStores = 0
        failedStores = 0
        successfulFinds = 0
        failedFinds = 0
        successfulMoves = 0
        failedMoves = 0
        successfulGets = 0
        failedGets = 0
        
        bytesReceived = 0
        bytesSent = 0
        totalStoredInstances = 0
    }
}

/// Statistics summary structure
public struct StatisticsSummary: Sendable {
    // Connection stats
    let totalConnections: Int
    let activeConnections: Int
    let failedConnections: Int
    
    // Operation stats
    let echoRequests: Int
    let storeRequests: Int
    let findRequests: Int
    let moveRequests: Int
    let getRequests: Int
    
    // Success/failure counts
    let successfulStores: Int
    let failedStores: Int
    let successfulFinds: Int
    let failedFinds: Int
    let successfulMoves: Int
    let failedMoves: Int
    let successfulGets: Int
    let failedGets: Int
    
    // Bandwidth
    let bytesReceived: Int64
    let bytesSent: Int64
    let totalStoredInstances: Int
    
    // Timing
    let startTime: Date
    let uptime: TimeInterval
    
    /// Format as human-readable string
    func formatted() -> String {
        let output = """
        =================================
        DICOM Server Statistics
        =================================
        
        Uptime: \(formatUptime(uptime))
        Started: \(formatDate(startTime))
        
        CONNECTIONS:
          Total:       \(totalConnections)
          Active:      \(activeConnections)
          Failed:      \(failedConnections)
        
        OPERATIONS:
          C-ECHO:      \(echoRequests)
          C-STORE:     \(storeRequests) (✓ \(successfulStores), ✗ \(failedStores))
          C-FIND:      \(findRequests) (✓ \(successfulFinds), ✗ \(failedFinds))
          C-MOVE:      \(moveRequests) (✓ \(successfulMoves), ✗ \(failedMoves))
          C-GET:       \(getRequests) (✓ \(successfulGets), ✗ \(failedGets))
        
        STORAGE:
          Instances:   \(totalStoredInstances)
          Received:    \(formatBytes(bytesReceived))
          Sent:        \(formatBytes(bytesSent))
        
        SUCCESS RATES:
          C-STORE:     \(successRate(successfulStores, failedStores))%
          C-FIND:      \(successRate(successfulFinds, failedFinds))%
          C-MOVE:      \(successRate(successfulMoves, failedMoves))%
          C-GET:       \(successRate(successfulGets, failedGets))%
        
        =================================
        """
        
        return output
    }
    
    private func successRate(_ success: Int, _ failure: Int) -> String {
        let total = success + failure
        guard total > 0 else { return "N/A" }
        let rate = Double(success) / Double(total) * 100.0
        return String(format: "%.1f", rate)
    }
    
    private func formatUptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(secs)s"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        } else {
            return String(format: "%.2f %@", value, units[unitIndex])
        }
    }
}
