// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (HL7 MLLP-style listener and a TCP stub on --listen-port that does not implement the PS3.8 Upper Layer, D-DICOM-GATEWAY-2); listen --forward builds no template-less data set and reports the PS3.3 2026a Table A.8-1 reason from GatewayOutputRules (D214)
import Foundation
import DICOMKit
import DICOMCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HL7 TCP listener for real-time message processing
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
actor HL7Listener {
    private let port: UInt16
    private let forwardDestination: String?
    private let messageTypes: Set<String>
    private let verbose: Bool
    private var isRunning = false
    private var acceptTask: Task<Void, Error>?
    
    init(port: UInt16, forwardDestination: String?, messageTypes: [String], verbose: Bool) {
        self.port = port
        self.forwardDestination = forwardDestination
        self.messageTypes = Set(messageTypes)
        self.verbose = verbose
    }
    
    func start() async throws {
        guard !isRunning else {
            throw GatewayError.invalidInput("Listener already running")
        }
        
        isRunning = true
        
        if verbose {
            print("Starting HL7 listener on port \(port)...")
            if let destination = forwardDestination {
                print("  Forward destination: \(destination)")
            }
            print("  Message types: \(messageTypes.isEmpty ? "ALL" : messageTypes.joined(separator: ", "))")
        }
        
        // Create socket listener
        #if os(Linux)
        try await startLinuxListener()
        #else
        try await startFoundationListener()
        #endif
    }
    
    func stop() async {
        isRunning = false
        acceptTask?.cancel()
        
        if verbose {
            print("Stopping HL7 listener...")
        }
    }
    
    #if !os(Linux)
    private func startFoundationListener() async throws {
        let socketFD = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard socketFD >= 0 else {
            throw GatewayError.networkError("Failed to create socket")
        }
        
        // Set socket options
        var optval: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind to port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            close(socketFD)
            throw GatewayError.networkError("Failed to bind to port \(port)")
        }
        
        // Listen
        guard listen(socketFD, 5) == 0 else {
            close(socketFD)
            throw GatewayError.networkError("Failed to listen on socket")
        }
        
        print("✓ HL7 listener started on port \(port)")
        
        // Accept connections in a loop
        acceptTask = Task {
            while !Task.isCancelled && isRunning {
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(socketFD, $0, &clientAddrLen)
                    }
                }
                
                if clientFD >= 0 {
                    Task {
                        await handleClient(clientFD: clientFD)
                    }
                }
                
                // Small delay to avoid busy loop
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            close(socketFD)
        }
        
        try await acceptTask?.value
    }
    #else
    private func startLinuxListener() async throws {
        // Linux-specific implementation would go here
        // For now, use similar socket code
        throw GatewayError.networkError("Linux listener not yet implemented")
    }
    #endif
    
    private func handleClient(clientFD: Int32) async {
        defer {
            close(clientFD)
        }
        
        do {
            // Read HL7 message
            let bufferSize = 65536
            var buffer = Data(count: bufferSize)
            
            let bytesRead = buffer.withUnsafeMutableBytes { bufferPtr in
                recv(clientFD, bufferPtr.baseAddress, bufferSize, 0)
            }
            
            guard bytesRead > 0 else {
                if verbose {
                    print("  No data received from client")
                }
                return
            }
            
            buffer = buffer.prefix(bytesRead)
            
            guard let hl7Text = String(data: buffer, encoding: .utf8) else {
                if verbose {
                    print("  Failed to decode HL7 message")
                }
                return
            }
            
            if verbose {
                print("  Received HL7 message (\(bytesRead) bytes)")
            }
            
            // Parse HL7
            let parser = HL7Parser()
            let hl7Message = try parser.parse(hl7Text)
            
            // Filter by message type if specified
            if !messageTypes.isEmpty && !messageTypes.contains(hl7Message.messageType.rawValue) {
                if verbose {
                    print("  Ignoring message type: \(hl7Message.messageType)")
                }
                
                // Send ACK
                try await sendAck(clientFD: clientFD, messageControlId: hl7Message.messageControlId)
                return
            }
            
            if verbose {
                print("  Processing \(hl7Message.messageType.rawValue) message")
            }
            
            // Forward to PACS if configured
            if let destination = forwardDestination {
                try await forwardToPACS(hl7Message: hl7Message, destination: destination)
            }
            
            // Send ACK
            try await sendAck(clientFD: clientFD, messageControlId: hl7Message.messageControlId)
            
        } catch {
            if verbose {
                print("  Error handling client: \(error)")
            }
        }
    }
    
    private func sendAck(clientFD: Int32, messageControlId: String) async throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let ack = """
            MSH|^~\\&|DICOMKit|GATEWAY|CLIENT|SYSTEM|\(timestamp)||ACK|\(messageControlId)|P|2.5\r
            MSA|AA|\(messageControlId)\r
            """
        
        guard let ackData = ack.data(using: .utf8) else {
            return
        }
        
        _ = ackData.withUnsafeBytes { bufferPtr in
            send(clientFD, bufferPtr.baseAddress, ackData.count, 0)
        }
    }
    
    /// D214: no template-less data set is built (P-GATEWAY-SC, PS3.3 Table A.8-1) and nothing
    /// is sent (D103); each message gets a one-line stderr note saying so. A real forward
    /// must take a template, as hl7-to-dicom does, before it converts anything.
    private func forwardToPACS(hl7Message: HL7Message, destination: String) async throws {
        let note = try GatewayOutputRules.listenerForwardSkipMessage(
            messageType: hl7Message.messageType.rawValue, destination: destination)
        FileHandle.standardError.write(Data("  \(note)\n".utf8))
    }
}

/// DICOM event forwarder that sends HL7/FHIR messages when DICOM operations occur
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
actor DICOMForwarder {
    private let listenPort: UInt16
    private let forwardHL7Destination: String?
    private let forwardFHIRDestination: String?
    private let messageType: String
    private let verbose: Bool
    private var isRunning = false
    private var acceptTask: Task<Void, Error>?
    
    init(
        listenPort: UInt16,
        forwardHL7Destination: String?,
        forwardFHIRDestination: String?,
        messageType: String,
        verbose: Bool
    ) {
        self.listenPort = listenPort
        self.forwardHL7Destination = forwardHL7Destination
        self.forwardFHIRDestination = forwardFHIRDestination
        self.messageType = messageType
        self.verbose = verbose
    }
    
    func start() async throws {
        guard !isRunning else {
            throw GatewayError.invalidInput("Forwarder already running")
        }
        
        isRunning = true
        
        if verbose {
            print("Starting DICOM forwarder on port \(listenPort)...")
            if let hl7Dest = forwardHL7Destination {
                print("  Forward HL7 to: \(hl7Dest)")
            }
            if let fhirDest = forwardFHIRDestination {
                print("  Forward FHIR to: \(fhirDest)")
            }
            print("  Message type: \(messageType)")
        }
        
        // Create socket listener for DICOM connections
        #if os(Linux)
        try await startLinuxForwarder()
        #else
        try await startFoundationForwarder()
        #endif
    }
    
    func stop() async {
        isRunning = false
        acceptTask?.cancel()
        
        if verbose {
            print("Stopping DICOM forwarder...")
        }
    }
    
    #if !os(Linux)
    private func startFoundationForwarder() async throws {
        let socketFD = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard socketFD >= 0 else {
            throw GatewayError.networkError("Failed to create socket")
        }
        
        var optval: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = listenPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            close(socketFD)
            throw GatewayError.networkError("Failed to bind to port \(listenPort)")
        }
        
        guard listen(socketFD, 5) == 0 else {
            close(socketFD)
            throw GatewayError.networkError("Failed to listen on socket")
        }
        
        print("✓ DICOM forwarder started on port \(listenPort)")
        
        acceptTask = Task {
            while !Task.isCancelled && isRunning {
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(socketFD, $0, &clientAddrLen)
                    }
                }
                
                if clientFD >= 0 {
                    Task {
                        await handleDICOMClient(clientFD: clientFD)
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            close(socketFD)
        }
        
        try await acceptTask?.value
    }
    #else
    private func startLinuxForwarder() async throws {
        throw GatewayError.networkError("Linux forwarder not yet implemented")
    }
    #endif
    
    private func handleDICOMClient(clientFD: Int32) async {
        defer {
            close(clientFD)
        }
        
        do {
            // For simplicity, we'll just log that we received a DICOM connection
            // A full implementation would use DICOMNetwork to handle the DIMSE protocol
            if verbose {
                print("  Received DICOM connection")
            }
            
            // In a real implementation, we would:
            // 1. Accept DICOM association
            // 2. Receive C-STORE PDUs
            // 3. Extract DICOM file
            // 4. Forward to HL7/FHIR destinations
            
            if verbose {
                print("  Note: Full DICOM DIMSE handling requires DICOMNetwork integration")
            }
            
        }
    }
    
    func forwardDICOMFile(_ dicomFile: DICOMFile) async throws {
        // Forward to HL7 destination
        if let hl7Dest = forwardHL7Destination {
            try await forwardAsHL7(dicomFile: dicomFile, destination: hl7Dest)
        }
        
        // Forward to FHIR destination
        if let fhirDest = forwardFHIRDestination {
            try await forwardAsFHIR(dicomFile: dicomFile, destination: fhirDest)
        }
    }
    
    private func forwardAsHL7(dicomFile: DICOMFile, destination: String) async throws {
        let converter = DICOMToHL7Converter()
        let hl7Message: HL7Message
        
        switch messageType.uppercased() {
        case "ADT":
            hl7Message = try converter.convertToADT(dicomFile: dicomFile, eventType: "A01")
        case "ORM":
            hl7Message = try converter.convertToORM(dicomFile: dicomFile)
        case "ORU":
            hl7Message = try converter.convertToORU(dicomFile: dicomFile)
        default:
            throw GatewayError.invalidProtocol("Unsupported message type: \(messageType)")
        }
        
        let parser = HL7Parser()
        let hl7Text = parser.generate(message: hl7Message)
        
        // Parse destination (format: hl7://host:port or tcp://host:port)
        guard let url = URL(string: destination) else {
            throw GatewayError.invalidInput("Invalid HL7 destination: \(destination)")
        }
        
        guard let host = url.host, let port = url.port else {
            throw GatewayError.invalidInput("Invalid HL7 destination format")
        }
        
        if verbose {
            print("  Forwarding HL7 to \(host):\(port)")
        }
        
        // Send HL7 message via TCP
        try await sendHL7Message(hl7Text, to: host, port: UInt16(port))
        
        if verbose {
            print("  ✓ HL7 message forwarded")
        }
    }
    
    private func forwardAsFHIR(dicomFile: DICOMFile, destination: String) async throws {
        let converter = FHIRConverter()
        let fhirResource = try converter.convertToFHIR(dicomFile: dicomFile, resourceType: .imagingStudy)
        
        if verbose {
            print("  Forwarding FHIR to \(destination)")
        }
        
        // Post FHIR resource to destination
        guard let url = URL(string: destination) else {
            throw GatewayError.invalidInput("Invalid FHIR destination: \(destination)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fhirResource, options: [])
        
        #if canImport(FoundationNetworking)
        // Linux URLSession
        let (_, response) = try await URLSession.shared.data(for: request)
        #else
        let (_, response) = try await URLSession.shared.data(for: request)
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GatewayError.networkError("Failed to post FHIR resource")
        }
        
        if verbose {
            print("  ✓ FHIR resource forwarded")
        }
    }
    
    // Note: Simplified socket implementation - production would use NIO or similar
    // Skipping actual TCP implementation for now
    private func sendHL7Message(_ message: String, to host: String, port: UInt16) async throws {
        // Would implement proper TCP socket connection here
        throw GatewayError.notImplemented("Direct TCP HL7 forwarding")
    }
}
