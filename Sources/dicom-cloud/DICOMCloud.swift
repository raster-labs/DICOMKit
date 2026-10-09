// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (cloud CLI plumbing: s3/gs/azure URLs, endpoint, region, encryption, parallelism, sync direction; no DICOMweb endpoint, transfer syntax, de-identification profile or SOP Class filter); Scripts/diff_cli.py: 0 UID, tag or code literals
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore

@main
struct DICOMCloud: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-cloud",
        abstract: "Integrate DICOM files with cloud storage providers",
        discussion: """
            Seamlessly upload, download, and manage DICOM files across cloud storage providers
            including AWS S3, Google Cloud Storage, and Azure Blob Storage.
            
            Examples:
              # Upload to AWS S3
              dicom-cloud upload study/ s3://my-bucket/studies/study1/ --recursive
              
              # Download from S3
              dicom-cloud download s3://my-bucket/studies/study1/ local-study/ --recursive
              
              # List objects in bucket
              dicom-cloud list s3://my-bucket/studies/ --recursive
              
              # Sync local with cloud
              dicom-cloud sync local-archive/ s3://my-bucket/archive/ --bidirectional
            
            Cloud URL Formats:
              AWS S3:              s3://bucket-name/path/to/object
              Google Cloud:        gs://bucket-name/path/to/object
              Azure Blob Storage:  azure://container-name/path/to/blob
              Custom S3:           s3://endpoint/bucket-name/path (use --endpoint flag)
            """,
        version: "1.4.4",
        subcommands: [Upload.self, Download.self, List.self, Delete.self, Sync.self, Copy.self],
        defaultSubcommand: Upload.self
    )
}

// MARK: - Upload Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload files or directories to cloud storage",
        discussion: """
            Upload DICOM files or entire directory structures to cloud storage.
            Supports parallel transfers, resumption, and metadata tagging.
            """
    )
    
    @Argument(help: "Local file or directory path")
    var source: String
    
    @Argument(help: "Cloud destination URL (s3://bucket/path, gs://bucket/path, azure://container/path)")
    var destination: String
    
    @Flag(name: .shortAndLong, help: "Upload directory recursively")
    var recursive: Bool = false
    
    @Option(name: .long, help: "Add metadata tags (key=value, comma-separated)")
    var tags: String?
    
    @Option(name: .long, help: "Encryption type: none, server-side, client-side")
    var encrypt: EncryptionType = .none
    
    @Flag(name: .long, help: "Enable multipart upload for large files")
    var multipart: Bool = false
    
    @Option(name: .long, help: "Number of parallel transfers")
    var parallel: Int = 4
    
    @Flag(name: .long, help: "Resume interrupted uploads")
    var resume: Bool = false
    
    @Option(name: .long, help: "Custom S3-compatible endpoint URL")
    var endpoint: String?
    
    @Option(name: .long, help: "AWS region (e.g., us-east-1, us-west-2)")
    var region: String?
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        guard FileManager.default.fileExists(atPath: source) else {
            throw ValidationError("Source path not found: \(source)")
        }
        
        let cloudURL = try CloudURL.parse(destination)
        let provider = try await CloudProvider.create(for: cloudURL, endpoint: endpoint, region: region)
        
        let metadata = try parseMetadata(tags)
        
        if verbose {
            print("Uploading '\(source)' to '\(destination)'...")
            print("Provider: \(cloudURL.provider)")
            print("Encryption: \(encrypt)")
            print("Parallel transfers: \(parallel)")
        }
        
        let uploader = CloudUploader(
            provider: provider,
            encryption: encrypt,
            multipart: multipart,
            parallelTransfers: parallel,
            resume: resume,
            verbose: verbose
        )
        
        let isDirectory = try isDirectoryPath(source)
        
        if isDirectory && !recursive {
            throw ValidationError("Source is a directory. Use --recursive to upload directories.")
        }
        
        if isDirectory {
            try await uploader.uploadDirectory(
                localPath: source,
                cloudURL: cloudURL,
                metadata: metadata
            )
        } else {
            try await uploader.uploadFile(
                localPath: source,
                cloudURL: cloudURL,
                metadata: metadata
            )
        }
        
        if verbose {
            print("Upload completed successfully.")
        }
    }
    
    private func parseMetadata(_ tagsString: String?) throws -> [String: String] {
        guard let tagsString = tagsString else { return [:] }
        
        var metadata: [String: String] = [:]
        let pairs = tagsString.split(separator: ",")
        
        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else {
                throw ValidationError("Invalid tag format: '\(pair)'. Expected 'key=value'")
            }
            let key = String(components[0]).trimmingCharacters(in: .whitespaces)
            let value = String(components[1]).trimmingCharacters(in: .whitespaces)
            metadata[key] = value
        }
        
        return metadata
    }
    
    private func isDirectoryPath(_ path: String) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(path)")
        }
        return isDirectory.boolValue
    }
}

// MARK: - Download Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download files from cloud storage",
        discussion: """
            Download DICOM files or directory structures from cloud storage to local disk.
            """
    )
    
    @Argument(help: "Cloud source URL")
    var source: String
    
    @Argument(help: "Local destination directory")
    var destination: String
    
    @Flag(name: .shortAndLong, help: "Download directory recursively")
    var recursive: Bool = false
    
    @Option(name: .long, help: "Number of parallel transfers")
    var parallel: Int = 4
    
    @Flag(name: .long, help: "Resume interrupted downloads")
    var resume: Bool = false
    
    @Option(name: .long, help: "Custom S3-compatible endpoint URL")
    var endpoint: String?
    
    @Option(name: .long, help: "AWS region (e.g., us-east-1, us-west-2)")
    var region: String?
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        let cloudURL = try CloudURL.parse(source)
        let provider = try await CloudProvider.create(for: cloudURL, endpoint: endpoint, region: region)
        
        if verbose {
            print("Downloading '\(source)' to '\(destination)'...")
            print("Provider: \(cloudURL.provider)")
            print("Parallel transfers: \(parallel)")
        }
        
        let downloader = CloudDownloader(
            provider: provider,
            parallelTransfers: parallel,
            resume: resume,
            verbose: verbose
        )
        
        if recursive {
            try await downloader.downloadDirectory(
                cloudURL: cloudURL,
                localPath: destination
            )
        } else {
            try await downloader.downloadFile(
                cloudURL: cloudURL,
                localPath: destination
            )
        }
        
        if verbose {
            print("Download completed successfully.")
        }
    }
}

// MARK: - List Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List objects in cloud storage",
        discussion: """
            List DICOM files and directories in cloud storage buckets/containers.
            """
    )
    
    @Argument(help: "Cloud URL to list")
    var cloudURL: String
    
    @Flag(name: .shortAndLong, help: "List recursively")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Show detailed information")
    var details: Bool = false
    
    @Option(name: .long, help: "Custom S3-compatible endpoint URL")
    var endpoint: String?
    
    @Option(name: .long, help: "AWS region (e.g., us-east-1, us-west-2)")
    var region: String?
    
    mutating func run() async throws {
        let url = try CloudURL.parse(cloudURL)
        let provider = try await CloudProvider.create(for: url, endpoint: endpoint, region: region)
        
        let lister = CloudLister(provider: provider, showDetails: details)
        let objects = try await lister.list(cloudURL: url, recursive: recursive)
        
        for object in objects {
            if details {
                let size = ByteCountFormatter.string(fromByteCount: Int64(object.size), countStyle: .file)
                let date = ISO8601DateFormatter().string(from: object.lastModified)
                print("\(object.key)\t\(size)\t\(date)")
            } else {
                print(object.key)
            }
        }
    }
}

// MARK: - Delete Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete objects from cloud storage",
        discussion: """
            Delete DICOM files from cloud storage. Use with caution!
            """
    )
    
    @Argument(help: "Cloud URL to delete")
    var cloudURL: String
    
    @Flag(name: .shortAndLong, help: "Delete directory recursively")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Force deletion without confirmation")
    var force: Bool = false
    
    @Option(name: .long, help: "Custom S3-compatible endpoint URL")
    var endpoint: String?
    
    @Option(name: .long, help: "AWS region (e.g., us-east-1, us-west-2)")
    var region: String?
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        let url = try CloudURL.parse(cloudURL)
        let provider = try await CloudProvider.create(for: url, endpoint: endpoint, region: region)
        
        if !force {
            print("Are you sure you want to delete '\(cloudURL)'? (yes/no): ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "yes" else {
                print("Deletion cancelled.")
                return
            }
        }
        
        if verbose {
            print("Deleting '\(cloudURL)'...")
        }
        
        let deleter = CloudDeleter(provider: provider, verbose: verbose)
        
        if recursive {
            try await deleter.deleteDirectory(cloudURL: url)
        } else {
            try await deleter.deleteFile(cloudURL: url)
        }
        
        if verbose {
            print("Deletion completed.")
        }
    }
}

// MARK: - Sync Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Synchronize local and cloud storage",
        discussion: """
            Sync DICOM files between local storage and cloud: uploads local files missing
            from the cloud; with --bidirectional also downloads cloud files missing locally.
            Files are compared by relative path only.
            """
    )
    
    @Argument(help: "Local directory path")
    var localPath: String
    
    @Argument(help: "Cloud URL")
    var cloudURL: String
    
    @Flag(name: .long, help: "Bidirectional sync (default: upload only)")
    var bidirectional: Bool = false
    
    @Flag(name: .long, help: "Delete files not present in source")
    var delete: Bool = false
    
    @Option(name: .long, help: "Custom S3-compatible endpoint URL")
    var endpoint: String?
    
    @Option(name: .long, help: "AWS region (e.g., us-east-1, us-west-2)")
    var region: String?
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw ValidationError("Local path not found: \(localPath)")
        }
        
        let url = try CloudURL.parse(cloudURL)
        let provider = try await CloudProvider.create(for: url, endpoint: endpoint, region: region)
        
        if verbose {
            print("Syncing '\(localPath)' with '\(cloudURL)'...")
            print("Mode: \(bidirectional ? "bidirectional" : "upload only")")
        }
        
        let syncer = CloudSyncer(
            provider: provider,
            bidirectional: bidirectional,
            deleteExtraneous: delete,
            verbose: verbose
        )
        
        try await syncer.sync(localPath: localPath, cloudURL: url)
        
        if verbose {
            print("Sync completed.")
        }
    }
}

// MARK: - Copy Command
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct Copy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Copy objects between cloud providers",
        discussion: """
            Copy DICOM files between different cloud storage providers.
            Supports cross-provider transfers (e.g., S3 to GCS).
            """
    )
    
    @Argument(help: "Source cloud URL")
    var source: String
    
    @Argument(help: "Destination cloud URL")
    var destination: String
    
    @Flag(name: .shortAndLong, help: "Copy directory recursively")
    var recursive: Bool = false
    
    @Option(name: .long, help: "Number of parallel transfers")
    var parallel: Int = 4
    
    @Option(name: .long, help: "AWS region for source (e.g., us-east-1)")
    var sourceRegion: String?
    
    @Option(name: .long, help: "AWS region for destination (e.g., us-east-1)")
    var destRegion: String?
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        let sourceURL = try CloudURL.parse(source)
        let destURL = try CloudURL.parse(destination)
        
        let sourceProvider = try await CloudProvider.create(for: sourceURL, endpoint: nil, region: sourceRegion)
        let destProvider = try await CloudProvider.create(for: destURL, endpoint: nil, region: destRegion)
        
        if verbose {
            print("Copying from '\(source)' to '\(destination)'...")
            print("Source provider: \(sourceURL.provider)")
            print("Destination provider: \(destURL.provider)")
        }
        
        let copier = CloudCopier(
            sourceProvider: sourceProvider,
            destProvider: destProvider,
            parallelTransfers: parallel,
            verbose: verbose
        )
        
        if recursive {
            try await copier.copyDirectory(sourceURL: sourceURL, destURL: destURL)
        } else {
            try await copier.copyFile(sourceURL: sourceURL, destURL: destURL)
        }
        
        if verbose {
            print("Copy completed successfully.")
        }
    }
}

// MARK: - Supporting Types
enum EncryptionType: String, ExpressibleByArgument {
    case none
    case serverSide = "server-side"
    case clientSide = "client-side"
}

// Entry point
