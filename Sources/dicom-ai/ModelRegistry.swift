// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data (local CoreML model registry: names, versions, paths, tags in a JSON file)
import Foundation

#if canImport(CoreML)
import CoreML
#endif

// MARK: - Model Registry

/// Registry for managing AI/ML models with versioning and metadata
@available(macOS 14.0, iOS 17.0, *)
class ModelRegistry {
    
    /// Model metadata entry in the registry
    struct ModelEntry: Codable, Sendable {
        let name: String
        let version: String
        let path: String
        let modelType: ModelType
        let description: String?
        let inputSize: ModelInputSize?
        let outputType: ModelOutputType
        let dateAdded: Date
        let lastUsed: Date?
        let tags: [String]
        
        enum ModelType: String, Codable, Sendable {
            case classification
            case segmentation
            case detection
            case enhancement
            case other
        }
        
        enum ModelOutputType: String, Codable, Sendable {
            case classification
            case segmentation
            case detection
            case image
            case multiArray
        }
        
        struct ModelInputSize: Codable, Sendable {
            let width: Int
            let height: Int
        }
        
        init(
            name: String,
            version: String,
            path: String,
            modelType: ModelType,
            description: String? = nil,
            inputSize: ModelInputSize? = nil,
            outputType: ModelOutputType,
            dateAdded: Date = Date(),
            lastUsed: Date? = nil,
            tags: [String] = []
        ) {
            self.name = name
            self.version = version
            self.path = path
            self.modelType = modelType
            self.description = description
            self.inputSize = inputSize
            self.outputType = outputType
            self.dateAdded = dateAdded
            self.lastUsed = lastUsed
            self.tags = tags
        }
    }
    
    private var entries: [String: ModelEntry] = [:]
    private let registryURL: URL
    private let verbose: Bool
    
    /// Initialize the model registry
    /// - Parameters:
    ///   - registryPath: Custom path to registry file (defaults to user's config directory)
    ///   - verbose: Enable verbose logging
    init(registryPath: String? = nil, verbose: Bool = false) throws {
        self.verbose = verbose
        
        if let customPath = registryPath {
            self.registryURL = URL(fileURLWithPath: customPath)
        } else {
            // Use default location in user's config directory
            let configDir = try Self.getConfigDirectory()
            self.registryURL = configDir.appendingPathComponent("model-registry.json")
        }
        
        // Load existing registry if it exists
        if FileManager.default.fileExists(atPath: registryURL.path) {
            try load()
        }
    }
    
    /// Get the config directory for storing the registry
    private static func getConfigDirectory() throws -> URL {
        #if os(macOS) || os(iOS)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configDir = homeDir.appendingPathComponent(".dicomkit")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        return configDir
        #else
        throw RegistryError.unsupportedPlatform
        #endif
    }
    
    /// Load the registry from disk
    func load() throws {
        let data = try Data(contentsOf: registryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let loadedEntries = try decoder.decode([ModelEntry].self, from: data)
        entries = Dictionary(uniqueKeysWithValues: loadedEntries.map { ($0.name, $0) })
        
        if verbose {
            print("Loaded \(entries.count) model(s) from registry")
        }
    }
    
    /// Save the registry to disk
    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(Array(entries.values))
        try data.write(to: registryURL, options: .atomic)
        
        if verbose {
            print("Saved \(entries.count) model(s) to registry at \(registryURL.path)")
        }
    }
    
    /// Add a model to the registry
    /// - Parameters:
    ///   - entry: Model entry to add
    ///   - overwrite: Whether to overwrite if a model with the same name exists
    func add(_ entry: ModelEntry, overwrite: Bool = false) throws {
        if entries[entry.name] != nil && !overwrite {
            throw RegistryError.modelAlreadyExists(entry.name)
        }
        
        // Verify the model file exists
        let modelURL = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw RegistryError.modelFileNotFound(entry.path)
        }
        
        entries[entry.name] = entry
        try save()
        
        if verbose {
            print("Added model '\(entry.name)' (version \(entry.version)) to registry")
        }
    }
    
    /// Remove a model from the registry
    /// - Parameter name: Name of the model to remove
    func remove(name: String) throws {
        guard entries[name] != nil else {
            throw RegistryError.modelNotFound(name)
        }
        
        entries.removeValue(forKey: name)
        try save()
        
        if verbose {
            print("Removed model '\(name)' from registry")
        }
    }
    
    /// Get a model entry by name
    /// - Parameter name: Name of the model
    /// - Returns: Model entry if found
    func get(name: String) -> ModelEntry? {
        return entries[name]
    }
    
    /// Update the last used timestamp for a model
    /// - Parameter name: Name of the model
    func updateLastUsed(name: String) throws {
        guard let entry = entries[name] else {
            throw RegistryError.modelNotFound(name)
        }
        
        // Create a new entry with updated lastUsed
        let updatedEntry = ModelEntry(
            name: entry.name,
            version: entry.version,
            path: entry.path,
            modelType: entry.modelType,
            description: entry.description,
            inputSize: entry.inputSize,
            outputType: entry.outputType,
            dateAdded: entry.dateAdded,
            lastUsed: Date(),
            tags: entry.tags
        )
        
        entries[name] = updatedEntry
        try save()
    }
    
    /// List all models in the registry
    /// - Parameter filterByType: Optional filter by model type
    /// - Returns: Array of model entries
    func list(filterByType: ModelEntry.ModelType? = nil) -> [ModelEntry] {
        let allEntries = Array(entries.values).sorted { $0.name < $1.name }
        
        if let type = filterByType {
            return allEntries.filter { $0.modelType == type }
        }
        
        return allEntries
    }
    
    /// Search models by tags
    /// - Parameter tags: Tags to search for
    /// - Returns: Array of model entries matching any of the tags
    func search(tags: [String]) -> [ModelEntry] {
        return Array(entries.values).filter { entry in
            entry.tags.contains(where: { tags.contains($0) })
        }.sorted { $0.name < $1.name }
    }
    
    /// Get models by semantic version matching
    /// - Parameters:
    ///   - name: Base name of the model
    ///   - versionPattern: Version pattern (e.g., "1.0.0", "1.*", ">=1.0.0")
    /// - Returns: Array of matching model entries
    func getByVersion(name: String, versionPattern: String) -> [ModelEntry] {
        // For now, just do exact match or wildcard
        if versionPattern.contains("*") {
            let prefix = versionPattern.replacingOccurrences(of: "*", with: "")
            return entries.values.filter { entry in
                entry.name == name && entry.version.hasPrefix(prefix)
            }.sorted { $0.version < $1.version }
        } else {
            // Exact match
            if let entry = entries[name], entry.version == versionPattern {
                return [entry]
            }
            return []
        }
    }
    
    /// Clear all entries from the registry
    func clear() throws {
        entries.removeAll()
        try save()
        
        if verbose {
            print("Cleared all models from registry")
        }
    }
}

// MARK: - Registry Errors

enum RegistryError: Error, LocalizedError, Sendable {
    case modelAlreadyExists(String)
    case modelNotFound(String)
    case modelFileNotFound(String)
    case unsupportedPlatform
    case invalidVersionPattern(String)
    
    var errorDescription: String? {
        switch self {
        case .modelAlreadyExists(let name):
            return "Model '\(name)' already exists in registry. Use --overwrite to replace."
        case .modelNotFound(let name):
            return "Model '\(name)' not found in registry."
        case .modelFileNotFound(let path):
            return "Model file not found at path: \(path)"
        case .unsupportedPlatform:
            return "Model registry is not supported on this platform"
        case .invalidVersionPattern(let pattern):
            return "Invalid version pattern: \(pattern)"
        }
    }
}
