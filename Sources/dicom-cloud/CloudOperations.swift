// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (upload/download/list/delete/sync/copy of opaque file bytes; files are not parsed as DICOM); Scripts/diff_cli.py: 0 UID, tag or code literals
import Foundation

// MARK: - Cloud Uploader
struct CloudUploader {
    let provider: any CloudProviderProtocol
    let encryption: EncryptionType
    let multipart: Bool
    let parallelTransfers: Int
    let resume: Bool
    let verbose: Bool
    
    func uploadFile(localPath: String, cloudURL: CloudURL, metadata: [String: String]) async throws {
        let fileURL = URL(fileURLWithPath: localPath)
        let data = try Data(contentsOf: fileURL)
        
        if verbose {
            print("Uploading: \(localPath) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
        }
        
        try await provider.upload(data: data, to: cloudURL, metadata: metadata, encryption: encryption)
        
        if verbose {
            print("✓ Uploaded: \(cloudURL.key)")
        }
    }
    
    func uploadDirectory(localPath: String, cloudURL: CloudURL, metadata: [String: String]) async throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: localPath) else {
            throw CloudError.operationFailed("Failed to enumerate directory: \(localPath)")
        }
        
        var files: [String] = []
        while let file = enumerator.nextObject() as? String {
            let fullPath = (localPath as NSString).appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                files.append(file)
            }
        }
        
        if verbose {
            print("Found \(files.count) files to upload")
        }
        
        // Upload files in parallel (up to parallelTransfers at a time)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeUploads = 0
            var fileIndex = 0
            
            while fileIndex < files.count || activeUploads > 0 {
                // Add new uploads up to parallel limit
                while activeUploads < parallelTransfers && fileIndex < files.count {
                    let file = files[fileIndex]
                    let fullPath = (localPath as NSString).appendingPathComponent(file)
                    let objectKey = cloudURL.key.isEmpty ? file : "\(cloudURL.key)/\(file)"
                    let fileCloudURL = cloudURL.with(key: objectKey)
                    
                    group.addTask {
                        try await uploadFile(localPath: fullPath, cloudURL: fileCloudURL, metadata: metadata)
                    }
                    
                    activeUploads += 1
                    fileIndex += 1
                }
                
                // Wait for one to complete
                if activeUploads > 0 {
                    try await group.next()
                    activeUploads -= 1
                }
            }
        }
        
        if verbose {
            print("✓ Upload directory completed: \(files.count) files")
        }
    }
}

// MARK: - Cloud Downloader
struct CloudDownloader {
    let provider: any CloudProviderProtocol
    let parallelTransfers: Int
    let resume: Bool
    let verbose: Bool
    
    func downloadFile(cloudURL: CloudURL, localPath: String) async throws {
        if verbose {
            print("Downloading: \(cloudURL.key)")
        }
        
        let data = try await provider.download(from: cloudURL)
        
        let fileURL = URL(fileURLWithPath: localPath)
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        try data.write(to: fileURL)
        
        if verbose {
            print("✓ Downloaded: \(localPath) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
        }
    }
    
    func downloadDirectory(cloudURL: CloudURL, localPath: String) async throws {
        let objects = try await provider.list(cloudURL: cloudURL, recursive: true)
        
        if verbose {
            print("Found \(objects.count) objects to download")
        }
        
        // Download files in parallel
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeDownloads = 0
            var objectIndex = 0
            
            while objectIndex < objects.count || activeDownloads > 0 {
                while activeDownloads < parallelTransfers && objectIndex < objects.count {
                    let object = objects[objectIndex]
                    let fileCloudURL = cloudURL.with(key: object.key)
                    
                    // Calculate relative path correctly, handling empty cloudURL.key
                    let relativePath: String
                    if cloudURL.key.isEmpty {
                        relativePath = object.key
                    } else {
                        relativePath = String(object.key.dropFirst(cloudURL.key.count + 1))
                    }
                    let filePath = (localPath as NSString).appendingPathComponent(relativePath)
                    
                    group.addTask {
                        try await downloadFile(cloudURL: fileCloudURL, localPath: filePath)
                    }
                    
                    activeDownloads += 1
                    objectIndex += 1
                }
                
                if activeDownloads > 0 {
                    try await group.next()
                    activeDownloads -= 1
                }
            }
        }
        
        if verbose {
            print("✓ Download directory completed: \(objects.count) files")
        }
    }
}

// MARK: - Cloud Lister
struct CloudLister {
    let provider: any CloudProviderProtocol
    let showDetails: Bool
    
    func list(cloudURL: CloudURL, recursive: Bool) async throws -> [CloudObject] {
        return try await provider.list(cloudURL: cloudURL, recursive: recursive)
    }
}

// MARK: - Cloud Deleter
struct CloudDeleter {
    let provider: any CloudProviderProtocol
    let verbose: Bool
    
    func deleteFile(cloudURL: CloudURL) async throws {
        if verbose {
            print("Deleting: \(cloudURL.key)")
        }
        
        try await provider.delete(cloudURL: cloudURL)
        
        if verbose {
            print("✓ Deleted: \(cloudURL.key)")
        }
    }
    
    func deleteDirectory(cloudURL: CloudURL) async throws {
        let objects = try await provider.list(cloudURL: cloudURL, recursive: true)
        
        if verbose {
            print("Found \(objects.count) objects to delete")
        }
        
        for object in objects {
            let fileCloudURL = cloudURL.with(key: object.key)
            try await deleteFile(cloudURL: fileCloudURL)
        }
        
        if verbose {
            print("✓ Delete directory completed: \(objects.count) files")
        }
    }
}

// MARK: - Cloud Syncer
struct CloudSyncer {
    let provider: any CloudProviderProtocol
    let bidirectional: Bool
    let deleteExtraneous: Bool
    let verbose: Bool
    
    func sync(localPath: String, cloudURL: CloudURL) async throws {
        // Get local files
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: localPath) else {
            throw CloudError.operationFailed("Failed to enumerate directory: \(localPath)")
        }
        
        var localFiles: Set<String> = []
        while let file = enumerator.nextObject() as? String {
            let fullPath = (localPath as NSString).appendingPathComponent(file)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                localFiles.insert(file)
            }
        }
        
        // Get cloud files
        let cloudObjects = try await provider.list(cloudURL: cloudURL, recursive: true)
        let cloudFiles: Set<String> = Set(cloudObjects.map { object in
            // Calculate relative path correctly, handling empty cloudURL.key
            if cloudURL.key.isEmpty {
                return object.key
            } else {
                return String(object.key.dropFirst(cloudURL.key.count + 1))
            }
        })
        
        if verbose {
            print("Local files: \(localFiles.count), Cloud files: \(cloudFiles.count)")
        }
        
        // Upload files that are in local but not in cloud
        let filesToUpload = localFiles.subtracting(cloudFiles)
        if verbose && !filesToUpload.isEmpty {
            print("Uploading \(filesToUpload.count) new files...")
        }
        
        for file in filesToUpload {
            let fullPath = (localPath as NSString).appendingPathComponent(file)
            let objectKey = cloudURL.key.isEmpty ? file : "\(cloudURL.key)/\(file)"
            let fileCloudURL = cloudURL.with(key: objectKey)
            
            let uploader = CloudUploader(
                provider: provider,
                encryption: .none,
                multipart: false,
                parallelTransfers: 1,
                resume: false,
                verbose: verbose
            )
            
            try await uploader.uploadFile(localPath: fullPath, cloudURL: fileCloudURL, metadata: [:])
        }
        
        // Download files if bidirectional
        if bidirectional {
            let filesToDownload = cloudFiles.subtracting(localFiles)
            if verbose && !filesToDownload.isEmpty {
                print("Downloading \(filesToDownload.count) new files...")
            }
            
            for file in filesToDownload {
                let objectKey = cloudURL.key.isEmpty ? file : "\(cloudURL.key)/\(file)"
                let fileCloudURL = cloudURL.with(key: objectKey)
                let filePath = (localPath as NSString).appendingPathComponent(file)
                
                let downloader = CloudDownloader(
                    provider: provider,
                    parallelTransfers: 1,
                    resume: false,
                    verbose: verbose
                )
                
                try await downloader.downloadFile(cloudURL: fileCloudURL, localPath: filePath)
            }
        }
        
        // Delete extraneous files if requested
        if deleteExtraneous {
            let extraneousCloud = cloudFiles.subtracting(localFiles)
            if verbose && !extraneousCloud.isEmpty {
                print("Deleting \(extraneousCloud.count) extraneous cloud files...")
            }
            
            for file in extraneousCloud {
                let objectKey = cloudURL.key.isEmpty ? file : "\(cloudURL.key)/\(file)"
                let fileCloudURL = cloudURL.with(key: objectKey)
                
                let deleter = CloudDeleter(provider: provider, verbose: verbose)
                try await deleter.deleteFile(cloudURL: fileCloudURL)
            }
        }
        
        if verbose {
            print("✓ Sync completed")
        }
    }
}

// MARK: - Cloud Copier
struct CloudCopier {
    let sourceProvider: any CloudProviderProtocol
    let destProvider: any CloudProviderProtocol
    let parallelTransfers: Int
    let verbose: Bool
    
    func copyFile(sourceURL: CloudURL, destURL: CloudURL) async throws {
        if verbose {
            print("Copying: \(sourceURL.key) -> \(destURL.key)")
        }
        
        let data = try await sourceProvider.download(from: sourceURL)
        try await destProvider.upload(data: data, to: destURL, metadata: [:], encryption: .none)
        
        if verbose {
            print("✓ Copied: \(destURL.key) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
        }
    }
    
    func copyDirectory(sourceURL: CloudURL, destURL: CloudURL) async throws {
        let objects = try await sourceProvider.list(cloudURL: sourceURL, recursive: true)
        
        if verbose {
            print("Found \(objects.count) objects to copy")
        }
        
        // Copy files in parallel
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeCopies = 0
            var objectIndex = 0
            
            while objectIndex < objects.count || activeCopies > 0 {
                while activeCopies < parallelTransfers && objectIndex < objects.count {
                    let object = objects[objectIndex]
                    let sourceFileURL = sourceURL.with(key: object.key)
                    
                    // Calculate relative path correctly, handling empty sourceURL.key
                    let relativePath: String
                    if sourceURL.key.isEmpty {
                        relativePath = object.key
                    } else {
                        relativePath = String(object.key.dropFirst(sourceURL.key.count + 1))
                    }
                    let destKey = destURL.key.isEmpty ? relativePath : "\(destURL.key)/\(relativePath)"
                    let destFileURL = destURL.with(key: destKey)
                    
                    group.addTask {
                        try await copyFile(sourceURL: sourceFileURL, destURL: destFileURL)
                    }
                    
                    activeCopies += 1
                    objectIndex += 1
                }
                
                if activeCopies > 0 {
                    try await group.next()
                    activeCopies -= 1
                }
            }
        }
        
        if verbose {
            print("✓ Copy directory completed: \(objects.count) files")
        }
    }
}
