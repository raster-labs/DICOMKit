// CloudIntegrationModel.swift
// DICOMStudio
//
// DICOM Studio — Data models for Cloud Integration (dicom-cloud)
// Reference: DICOM PS3.18 (Web Services) — cloud transport
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (cloud providers, bucket paths,
// transfer jobs). The PS3.18 line above is a pointer to the transport the files travel over, not a claim that
// any PS3.18 resource, media type or parameter is implemented here.

import Foundation

// MARK: - Navigation Tab

/// Navigation tabs for the Cloud Integration feature.
public enum CloudIntegrationTab: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case serverConfig = "SERVER_CONFIG"
    case upload       = "UPLOAD"
    case download     = "DOWNLOAD"
    case sync         = "SYNC"
    case jobs         = "JOBS"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .serverConfig: return "Connection"
        case .upload:       return "Upload"
        case .download:     return "Download"
        case .sync:         return "Sync"
        case .jobs:         return "Jobs"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .serverConfig: return "cloud"
        case .upload:       return "icloud.and.arrow.up"
        case .download:     return "icloud.and.arrow.down"
        case .sync:         return "arrow.triangle.2.circlepath.icloud"
        case .jobs:         return "list.bullet.clipboard"
        }
    }
}

// MARK: - Cloud Provider

/// Supported cloud storage providers.
public enum CloudProvider: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case awsS3   = "AWS_S3"
    case gcs     = "GCS"
    case azure   = "AZURE"
    case custom  = "CUSTOM_S3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .awsS3:  return "AWS S3"
        case .gcs:    return "Google Cloud Storage"
        case .azure:  return "Azure Blob Storage"
        case .custom: return "Custom S3-Compatible"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .awsS3:  return "cloud.fill"
        case .gcs:    return "cloud.fill"
        case .azure:  return "cloud.fill"
        case .custom: return "server.rack"
        }
    }

    /// URL scheme prefix for this provider.
    public var urlScheme: String {
        switch self {
        case .awsS3, .custom: return "s3://"
        case .gcs:            return "gs://"
        case .azure:          return "azure://"
        }
    }
}

// MARK: - Cloud Profile

/// Configuration profile for a cloud storage connection.
public struct CloudProfile: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var provider: CloudProvider
    public var bucket: String
    public var region: String
    public var endpoint: String
    public var accessKey: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        provider: CloudProvider = .awsS3,
        bucket: String = "",
        region: String = "us-east-1",
        endpoint: String = "",
        accessKey: String = "",
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.accessKey = accessKey
        self.isActive = isActive
    }
}

// MARK: - Cloud Transfer Job

/// A cloud upload, download, or sync job.
public struct CloudTransferJob: Sendable, Identifiable, Hashable {
    public let id: UUID
    public var localPath: String
    public var remotePath: String
    public var direction: TransferDirection
    public var isRecursive: Bool
    public var status: CloudJobStatus
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var fileCount: Int
    public var startedAt: Date?

    public init(
        id: UUID = UUID(),
        localPath: String,
        remotePath: String,
        direction: TransferDirection,
        isRecursive: Bool = false,
        status: CloudJobStatus = .pending,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        fileCount: Int = 0,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.localPath = localPath
        self.remotePath = remotePath
        self.direction = direction
        self.isRecursive = isRecursive
        self.status = status
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.startedAt = startedAt
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }
}

// MARK: - Transfer Direction

/// Upload or download direction.
public enum TransferDirection: String, Sendable, Equatable, Hashable, CaseIterable {
    case upload     = "UPLOAD"
    case download   = "DOWNLOAD"
    case bidirectional = "BIDIRECTIONAL"

    public var displayName: String {
        switch self {
        case .upload:        return "Upload"
        case .download:      return "Download"
        case .bidirectional: return "Bidirectional Sync"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .upload:        return "icloud.and.arrow.up"
        case .download:      return "icloud.and.arrow.down"
        case .bidirectional: return "arrow.triangle.2.circlepath.icloud"
        }
    }
}

// MARK: - Cloud Job Status

/// Status of a cloud transfer job.
public enum CloudJobStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case pending    = "PENDING"
    case running    = "RUNNING"
    case completed  = "COMPLETED"
    case failed     = "FAILED"
    case cancelled  = "CANCELLED"

    public var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .pending:   return "clock"
        case .running:   return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }
}
