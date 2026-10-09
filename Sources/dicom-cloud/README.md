# dicom-cloud

Cloud storage integration tool for DICOM medical imaging files. Seamlessly upload, download, and manage DICOM files across AWS S3, Google Cloud Storage, and Azure Blob Storage.

## Features

### Cloud Providers
- ✅ **AWS S3** (implemented - full support via AWS SDK for Swift)
- ✅ **Google Cloud Storage** (implemented - REST API with OAuth2 token authentication)
- ✅ **Azure Blob Storage** (implemented - REST API with SAS token authentication)
- ✅ **Custom S3-compatible providers** (MinIO, DigitalOcean Spaces, LocalStack, etc.)

### Operations
- **Upload**: Upload individual files or entire directory structures
- **Download**: Download from cloud storage to local disk
- **List**: List objects in buckets/containers with detailed information
- **Delete**: Remove objects from cloud (with confirmation prompts)
- **Sync**: Bidirectional synchronization between local and cloud storage
- **Copy**: Cross-provider copying (e.g., S3 to GCS)

### Advanced Features
- ✅ **Parallel Transfers**: Configure concurrent uploads/downloads for improved performance
- 🚧 Multipart Upload: Efficient large file transfers (planned for Phase B completion)
- 🚧 Resume Capability: Resume interrupted transfers (planned for Phase D)
- ✅ **Metadata Tagging**: Add custom metadata to uploaded objects
- ✅ **Server-side Encryption**: AES256 encryption support
- 🚧 Client-side Encryption: Planned for Phase D
- ✅ **Custom Endpoints**: Full support for S3-compatible services (MinIO, LocalStack, etc.)
- ✅ **Region Configuration**: Flexible AWS region specification
- ✅ **Automatic Credentials**: Support for environment variables, AWS config files, IAM roles

## Installation

### From Source
```bash
cd DICOMKit
swift build -c release
cp .build/release/dicom-cloud /usr/local/bin/
```

### Using Homebrew (when available)
```bash
brew install dicomkit
```

## Configuration

### AWS Credentials

The tool uses the AWS SDK for Swift, which automatically handles credentials through multiple sources in this order:

1. **Environment Variables** (highest priority):
   ```bash
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_SESSION_TOKEN=your_session_token  # Optional, for temporary credentials
   export AWS_REGION=us-east-1                  # Optional, can also use --region flag
   ```

2. **AWS Credentials File** (~/.aws/credentials):
   ```ini
   [default]
   aws_access_key_id = your_access_key
   aws_secret_access_key = your_secret_key
   
   [profile-name]
   aws_access_key_id = another_access_key
   aws_secret_access_key = another_secret_key
   ```
   
   Use a specific profile:
   ```bash
   export AWS_PROFILE=profile-name
   dicom-cloud upload study/ s3://my-bucket/study/ --recursive
   ```

3. **AWS Config File** (~/.aws/config):
   ```ini
   [default]
   region = us-east-1
   output = json
   
   [profile profile-name]
   region = us-west-2
   ```

4. **IAM Role** (when running on EC2, ECS, or Lambda)

5. **Web Identity Token** (for Kubernetes, EKS)

### Region Configuration

Specify the AWS region in one of three ways:

1. **Command-line flag** (highest priority):
   ```bash
   dicom-cloud upload study/ s3://my-bucket/study/ --region us-west-2 --recursive
   ```

2. **Environment variable**:
   ```bash
   export AWS_REGION=us-west-2
   ```

3. **AWS config file** (~/.aws/config)

### Google Cloud Storage Credentials

GCS support uses REST API with OAuth2 authentication. You need a service account JSON key file and an access token.

#### Method 1: Using gcloud CLI (Recommended for Development)

1. **Install gcloud CLI**: Follow the [Google Cloud SDK installation guide](https://cloud.google.com/sdk/docs/install)

2. **Authenticate and generate access token**:
   ```bash
   # Authenticate with your Google account
   gcloud auth login
   
   # Generate and export access token
   export GCS_ACCESS_TOKEN=$(gcloud auth print-access-token)
   
   # Set your service account credentials path (optional, for validation)
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
   ```

3. **Upload to GCS**:
   ```bash
   dicom-cloud upload study/ gs://my-bucket/studies/study1/ --recursive
   ```

**Note**: Access tokens expire after 1 hour. Re-run `export GCS_ACCESS_TOKEN=$(gcloud auth print-access-token)` to refresh.

#### Method 2: Service Account with JWT (Production - Requires Additional Setup)

For production use, implement JWT signing to exchange service account credentials for access tokens. This requires adding a JWT library to the project (e.g., SwiftJWT).

```bash
# Set service account credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# The tool will use these credentials to generate access tokens automatically
# (requires JWT implementation - see Phase C.2 in CLI_TOOLS_PHASE7.md)
```

### Azure Blob Storage Credentials

Azure Blob Storage support uses REST API with Shared Access Signature (SAS) token authentication.

1. **Set storage account name**:
   ```bash
   export AZURE_STORAGE_ACCOUNT=mystorageaccount
   ```

2. **Generate and export SAS token**:
   
   - **Via Azure Portal**:
     1. Navigate to your Storage Account → Shared access signature
     2. Configure permissions (Read, Write, Delete, List)
     3. Set expiry date
     4. Click "Generate SAS and connection string"
     5. Copy the SAS token (starts with `?sv=...`)
   
   - **Via Azure CLI**:
     ```bash
     # Generate SAS token with 1-day expiry
     az storage account generate-sas \
       --account-name mystorageaccount \
       --services b \
       --resource-types sco \
       --permissions rwdlac \
       --expiry $(date -u -d "1 day" '+%Y-%m-%dT%H:%MZ') \
       --https-only
     
     # Export the token (include the leading '?')
     export AZURE_STORAGE_SAS_TOKEN="?sv=2021-06-08&ss=b&srt=sco&sp=rwdlac&se=..."
     ```

3. **Upload to Azure**:
   ```bash
   dicom-cloud upload study/ azure://my-container/studies/study1/ --recursive
   ```

**Security Note**: SAS tokens provide time-limited access. Rotate tokens regularly and never commit them to version control.

### Testing with LocalStack

For local development and testing, you can use [LocalStack](https://localstack.cloud/):

```bash
# Start LocalStack with S3 service
docker run -d -p 4566:4566 localstack/localstack

# Configure to use LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1

# Upload to LocalStack
dicom-cloud upload study/ s3://test-bucket/study/ \
  --endpoint http://localhost:4566 \
  --region us-east-1 \
  --recursive
```

### Testing with MinIO

[MinIO](https://min.io/) is a high-performance S3-compatible object storage:

```bash
# Start MinIO
docker run -d -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"

# Configure credentials
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin

# Upload to MinIO
dicom-cloud upload study/ s3://test-bucket/study/ \
  --endpoint http://localhost:9000 \
  --region us-east-1 \
  --recursive
```

## Usage

### Upload Files

```bash
# Upload single file to AWS S3
dicom-cloud upload scan.dcm s3://my-bucket/scans/scan.dcm

# Upload to Google Cloud Storage
dicom-cloud upload scan.dcm gs://my-bucket/scans/scan.dcm

# Upload to Azure Blob Storage
dicom-cloud upload scan.dcm azure://my-container/scans/scan.dcm

# Upload directory recursively
dicom-cloud upload study/ s3://my-bucket/studies/study1/ --recursive

# Specify AWS region
dicom-cloud upload study/ s3://my-bucket/studies/study1/ \
  --region us-west-2 \
  --recursive

# Upload with metadata tags
dicom-cloud upload scan.dcm s3://my-bucket/scans/ \
  --tags "PatientID=12345,StudyDate=20240101,Modality=CT"
# (tag keys are free-form object metadata, not DICOM attributes, and are not de-identified:
#  a PatientID tag is visible to anyone who can list the bucket)

# Upload with server-side encryption
dicom-cloud upload study/ s3://my-bucket/studies/ \
  --recursive \
  --encrypt server-side

# Parallel multipart upload (multipart planned for Phase B completion)
dicom-cloud upload large-study/ s3://my-bucket/large/ \
  --recursive \
  --parallel 8
```

### Download Files

```bash
# Download single file from S3
dicom-cloud download s3://my-bucket/scans/scan.dcm local-scan.dcm

# Download from Google Cloud Storage
dicom-cloud download gs://my-bucket/scans/scan.dcm local-scan.dcm

# Download from Azure Blob Storage
dicom-cloud download azure://my-container/scans/scan.dcm local-scan.dcm

# Download directory recursively
dicom-cloud download s3://my-bucket/studies/study1/ local-study/ --recursive

# Download with parallel transfers
dicom-cloud download s3://my-bucket/studies/ local/ \
  --recursive \
  --parallel 8
```

### List Objects

```bash
# List objects in bucket
dicom-cloud list s3://my-bucket/studies/

# List recursively with details
dicom-cloud list s3://my-bucket/studies/ --recursive --details

# Output shows: key, size, last modified date
```

### Delete Objects

```bash
# Delete single file (with confirmation)
dicom-cloud delete s3://my-bucket/scans/old-scan.dcm

# Delete directory recursively
dicom-cloud delete s3://my-bucket/old-studies/ --recursive

# Force delete without confirmation
dicom-cloud delete s3://my-bucket/temp/ --recursive --force
```

### Sync with Cloud

```bash
# Sync local to cloud (upload only)
dicom-cloud sync local-archive/ s3://my-bucket/archive/

# Bidirectional sync
dicom-cloud sync local-archive/ s3://my-bucket/archive/ --bidirectional

# Sync and delete extraneous files
dicom-cloud sync local-archive/ s3://my-bucket/archive/ \
  --bidirectional \
  --delete
```

### Copy Between Providers

```bash
# Copy from S3 to Google Cloud Storage
dicom-cloud copy s3://my-s3-bucket/study/ gs://my-gcs-bucket/study/ --recursive

# Copy from S3 to Azure
dicom-cloud copy s3://my-s3-bucket/study/ azure://my-container/study/ --recursive

# Copy with parallel transfers
dicom-cloud copy s3://source/data/ s3://dest/data/ \
  --recursive \
  --parallel 8
```

### Custom S3-Compatible Endpoints

```bash
# Use MinIO or other S3-compatible service
dicom-cloud upload study/ s3://my-bucket/study/ \
  --endpoint https://minio.example.com \
  --recursive

# DigitalOcean Spaces
dicom-cloud upload study/ s3://my-space/study/ \
  --endpoint https://nyc3.digitaloceanspaces.com \
  --recursive
```

## Cloud URL Formats

### AWS S3
```
s3://bucket-name/path/to/object
```

### Google Cloud Storage
```
gs://bucket-name/path/to/object
```

### Azure Blob Storage
```
azure://container-name/path/to/blob
```

### Custom S3-Compatible
```
s3://endpoint/bucket-name/path/to/object
```
Use with `--endpoint` flag to specify custom endpoint URL.

## Authentication

### AWS S3

**Environment Variables:**
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

**AWS Credentials File** (`~/.aws/credentials`):
```ini
[default]
aws_access_key_id = your-access-key
aws_secret_access_key = your-secret-key
region = us-east-1
```

### Google Cloud Storage

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

### Azure Blob Storage

```bash
export AZURE_STORAGE_CONNECTION_STRING="your-connection-string"
```

## Configuration

### Parallel Transfers

Control the number of concurrent operations:
```bash
dicom-cloud upload study/ s3://bucket/study/ --recursive --parallel 8
```

Default: 4 parallel transfers

### Verbose Mode

Enable detailed logging:
```bash
dicom-cloud upload study/ s3://bucket/study/ --recursive --verbose
```

## Examples

### Clinical Workflow: Archive Study to Cloud

```bash
# 1. Validate DICOM files
dicom-validate study/*.dcm

# 2. De-identify for archival (PS3.15 Annex E Basic Application Level Confidentiality Profile)
dicom-anon study/ --output anon-study/ --profile ps315 --recursive

# 3. Upload to cloud with metadata
dicom-cloud upload anon-study/ s3://pacs-archive/studies/$(date +%Y%m%d)/ \
  --recursive \
  --tags "ArchiveDate=$(date +%Y%m%d),Source=PACS1" \
  --verbose

# 4. Verify upload
dicom-cloud list s3://pacs-archive/studies/$(date +%Y%m%d)/ --recursive --details
```

### Disaster Recovery: Sync to Multiple Clouds

```bash
# Sync primary archive to AWS S3
dicom-cloud sync /var/pacs/archive/ s3://primary-backup/ --bidirectional

# Copy to Google Cloud for geographic redundancy
dicom-cloud copy s3://primary-backup/ gs://secondary-backup/ --recursive --parallel 8

# Copy to Azure for additional redundancy
dicom-cloud copy s3://primary-backup/ azure://tertiary-backup/ --recursive --parallel 8
```

### Research Data Distribution

```bash
# Upload de-identified research dataset
dicom-cloud upload research-dataset/ s3://research-data/dataset-v1.0/ \
  --recursive \
  --tags "Dataset=CardiacCT,Version=1.0,Cases=500" \
  --verbose

# Generate presigned URLs for data access (future feature)
# dicom-cloud share s3://research-data/dataset-v1.0/ --expires 30d
```

## Implementation Status

### Current Status (v1.4.4)

This is the initial release of `dicom-cloud` with **framework and CLI interface complete**.

**✅ Implemented:**
- Complete CLI interface with all subcommands
- URL parsing for S3, GCS, Azure
- Operation framework (upload, download, list, delete, sync, copy)
- Parallel transfer architecture
- Metadata tagging support
- Verbose logging

**⚠️ Pending Integration:**
- AWS SDK for Swift integration
- Google Cloud SDK integration
- Azure SDK integration
- Actual cloud provider implementations

**Why the delay?**
Cloud SDK dependencies are substantial (100+ MB each) and require:
1. Package.swift dependency additions
2. SDK-specific authentication implementations
3. Platform-specific build configurations
4. Extensive integration testing with real cloud accounts

**Current Capability:**
The tool provides a complete CLI interface and will display clear error messages
indicating that cloud SDK integration is required. This allows:
- Testing of CLI argument parsing
- Validation of workflow logic
- Integration with other DICOMKit tools
- Future SDK integration without breaking changes

### Phase A: AWS S3 Support (Planned)

**Deliverables:**
- [ ] Integrate AWS SDK for Swift dependency
- [ ] Implement S3 authentication (SigV4)
- [ ] Implement S3 upload with PutObject
- [ ] Implement S3 download with GetObject
- [ ] Implement S3 list with ListObjectsV2
- [ ] Implement S3 delete with DeleteObject
- [ ] Add multipart upload support
- [ ] Handle S3-specific errors
- [ ] Test with real AWS S3 buckets

**Estimated Effort:** 2-3 days

### Phase B: Multi-Provider Support (Planned)

**Deliverables:**
- [ ] Integrate Google Cloud Storage SDK
- [ ] Implement GCS operations
- [ ] Integrate Azure Blob Storage SDK
- [ ] Implement Azure operations
- [ ] Add custom S3-compatible provider support
- [ ] Test cross-provider copying

**Estimated Effort:** 3-4 days

### Phase C: Advanced Features (Planned)

**Deliverables:**
- [ ] Implement multipart upload
- [ ] Add resume capability
- [ ] Implement server-side encryption
- [ ] Implement client-side encryption
- [ ] Add progress bars for transfers
- [ ] Optimize parallel transfer performance

**Estimated Effort:** 2-3 days

## Testing

### Unit Tests
```bash
swift test --filter DICOMCloudTests
```

### Integration Tests (requires cloud credentials)
```bash
# Set up test environment
export AWS_ACCESS_KEY_ID="test-key"
export AWS_SECRET_ACCESS_KEY="test-secret"
export DICOM_CLOUD_TEST_BUCKET="test-bucket"

# Run integration tests
swift test --filter DICOMCloudIntegrationTests
```

### Manual Testing with MinIO
```bash
# Start MinIO locally
docker run -p 9000:9000 -p 9001:9001 \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  minio/minio server /data --console-address ":9001"

# Configure credentials
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin"

# Test upload
dicom-cloud upload test.dcm s3://test-bucket/test.dcm \
  --endpoint http://localhost:9000
```

## Security Best Practices

### 1. Credential Management
- Never hardcode credentials in scripts
- Use environment variables or credential files
- Rotate credentials regularly
- Use IAM roles on EC2/ECS when possible

### 2. Encryption
- Enable server-side encryption for sensitive data
- Use client-side encryption for PHI (Protected Health Information)
- Ensure encryption at rest and in transit

### 3. Access Control
- Use least-privilege IAM policies
- Enable bucket versioning for data protection
- Implement lifecycle policies for old data
- Enable access logging

### 4. Compliance
- Follow HIPAA guidelines for PHI
- Implement audit trails
- Use signed URLs for temporary access
- Regular security audits

## Troubleshooting

### Authentication Errors
```
Error: Authentication failed: Invalid credentials
```
**Solution:** Verify AWS credentials are set correctly via environment variables or `~/.aws/credentials`.

### Network Errors
```
Error: Network error: Connection timeout
```
**Solution:** Check internet connectivity, firewall rules, and endpoint URLs.

### Permission Errors
```
Error: Permission denied: Access denied to bucket
```
**Solution:** Verify IAM permissions include `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject`.

### Not Implemented Errors
```
Error: Not implemented: AWS S3 upload requires AWS SDK integration
```
**Solution:** This is expected in v1.4.4. AWS SDK integration is planned for future releases. See "Implementation Status" section above.

## Performance Tuning

### Parallel Transfers
- Default: 4 concurrent transfers
- Recommended for large datasets: 8-16
- Too many can cause rate limiting

### Multipart Upload (Planned)
- Automatically used for files > 100 MB
- Improves reliability for large files
- Configurable chunk size

### Network Optimization
- Use --resume for unreliable connections
- Enable --multipart for large files
- Adjust --parallel based on bandwidth

## API Integration

For programmatic access, use the CloudProvider API directly:

```swift
import Foundation

// Parse cloud URL
let cloudURL = try CloudURL.parse("s3://my-bucket/path/to/file.dcm")

// Create provider
let provider = try CloudProvider.create(for: cloudURL, endpoint: nil)

// Upload file
let data = try Data(contentsOf: fileURL)
try await provider.upload(
    data: data,
    to: cloudURL,
    metadata: ["PatientID": "12345"],
    encryption: .serverSide
)

// Download file
let downloadedData = try await provider.download(from: cloudURL)

// List objects
let objects = try await provider.list(cloudURL: cloudURL, recursive: true)
for object in objects {
    print("\(object.key): \(object.size) bytes")
}
```

## Related Tools

- **dicom-send**: Send DICOM files to PACS servers via DICOM protocol
- **dicom-archive**: Manage local DICOM archives with SQLite indexing
- **dicom-export**: Export DICOM files with advanced filtering

## References

- [AWS S3 Documentation](https://aws.amazon.com/s3/)
- [Google Cloud Storage Documentation](https://cloud.google.com/storage)
- [Azure Blob Storage Documentation](https://azure.microsoft.com/en-us/services/storage/blobs/)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [DICOM Standard](https://www.dicomstandard.org/)

## Version History

### v1.4.4 (2026-02-13)
- Initial release with complete CLI framework
- URL parsing for S3, GCS, Azure
- Operation framework (upload, download, list, delete, sync, copy)
- Parallel transfer architecture
- SDK integration planned for future releases

## License

MIT License - see LICENSE file for details

---

**Part of**: [DICOMKit CLI Tools Phase 7](../../CLI_TOOLS_PHASE7.md)  
**Tool #35**: dicom-cloud - Cloud Storage Integration  
**Status**: Phase A - Framework Complete, SDK Integration Planned
