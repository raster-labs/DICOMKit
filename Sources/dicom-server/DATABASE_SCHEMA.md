# Database Schema Documentation for dicom-server

These SQL schemas are design proposals. No SQLite/PostgreSQL database is created
or migrated by the server. As of M4 (24 October 2026), the supported durable mode
is `filesystem://`, rebuilt from Part 10 files before listening. See the
[current server README](README.md) for migration guidance.

## Overview

The proposed metadata index describes two future database backends:
- **SQLite**: Lightweight, file-based database suitable for small to medium deployments (<100K studies)
- **PostgreSQL**: Full-featured relational database for large-scale deployments (>100K studies)

Both backends share the same logical schema design with minor syntax differences.

## Schema Design

The schema follows the DICOM information model hierarchy:
- **Patient** → **Study** → **Series** → **Instance**

### Tables

#### 1. patients

Stores patient-level information.

**SQLite:**
```sql
CREATE TABLE patients (
    patient_id TEXT PRIMARY KEY,
    patient_name TEXT,
    patient_birth_date TEXT,
    patient_sex TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_name ON patients(patient_name);
```

**PostgreSQL:**
```sql
CREATE TABLE patients (
    patient_id VARCHAR(64) PRIMARY KEY,
    patient_name VARCHAR(255),
    patient_birth_date DATE,
    patient_sex CHAR(1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_name ON patients(patient_name);
```

#### 2. studies

Stores study-level information.

**SQLite:**
```sql
CREATE TABLE studies (
    study_instance_uid TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    study_date TEXT,
    study_time TEXT,
    study_description TEXT,
    accession_number TEXT,
    referring_physician_name TEXT,
    study_id TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
);

CREATE INDEX idx_studies_patient ON studies(patient_id);
CREATE INDEX idx_studies_date ON studies(study_date);
CREATE INDEX idx_studies_accession ON studies(accession_number);
```

**PostgreSQL:**
```sql
CREATE TABLE studies (
    study_instance_uid VARCHAR(64) PRIMARY KEY,
    patient_id VARCHAR(64) NOT NULL,
    study_date DATE,
    study_time TIME,
    study_description TEXT,
    accession_number VARCHAR(64),
    referring_physician_name VARCHAR(255),
    study_id VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
);

CREATE INDEX idx_studies_patient ON studies(patient_id);
CREATE INDEX idx_studies_date ON studies(study_date);
CREATE INDEX idx_studies_accession ON studies(accession_number);
```

#### 3. series

Stores series-level information.

**SQLite:**
```sql
CREATE TABLE series (
    series_instance_uid TEXT PRIMARY KEY,
    study_instance_uid TEXT NOT NULL,
    series_number TEXT,
    series_description TEXT,
    modality TEXT,
    series_date TEXT,
    series_time TEXT,
    body_part_examined TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (study_instance_uid) REFERENCES studies(study_instance_uid) ON DELETE CASCADE
);

CREATE INDEX idx_series_study ON series(study_instance_uid);
CREATE INDEX idx_series_modality ON series(modality);
```

**PostgreSQL:**
```sql
CREATE TABLE series (
    series_instance_uid VARCHAR(64) PRIMARY KEY,
    study_instance_uid VARCHAR(64) NOT NULL,
    series_number INTEGER,
    series_description TEXT,
    modality VARCHAR(16),
    series_date DATE,
    series_time TIME,
    body_part_examined VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (study_instance_uid) REFERENCES studies(study_instance_uid) ON DELETE CASCADE
);

CREATE INDEX idx_series_study ON series(study_instance_uid);
CREATE INDEX idx_series_modality ON series(modality);
```

#### 4. instances

Stores instance-level information and file paths.

**SQLite:**
```sql
CREATE TABLE instances (
    sop_instance_uid TEXT PRIMARY KEY,
    series_instance_uid TEXT NOT NULL,
    sop_class_uid TEXT,
    instance_number TEXT,
    file_path TEXT NOT NULL,
    file_size INTEGER,
    transfer_syntax_uid TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (series_instance_uid) REFERENCES series(series_instance_uid) ON DELETE CASCADE
);

CREATE INDEX idx_instances_series ON instances(series_instance_uid);
CREATE INDEX idx_instances_sop_class ON instances(sop_class_uid);
CREATE INDEX idx_instances_file_path ON instances(file_path);
```

**PostgreSQL:**
```sql
CREATE TABLE instances (
    sop_instance_uid VARCHAR(64) PRIMARY KEY,
    series_instance_uid VARCHAR(64) NOT NULL,
    sop_class_uid VARCHAR(64),
    instance_number INTEGER,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    transfer_syntax_uid VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (series_instance_uid) REFERENCES series(series_instance_uid) ON DELETE CASCADE
);

CREATE INDEX idx_instances_series ON instances(series_instance_uid);
CREATE INDEX idx_instances_sop_class ON instances(sop_class_uid);
CREATE INDEX idx_instances_file_path ON instances(file_path);
```

### Full-Text Search (Optional)

For advanced search capabilities, create full-text search indexes:

**PostgreSQL:**
```sql
-- Create full-text search indexes
CREATE INDEX idx_patients_name_fts ON patients USING gin(to_tsvector('english', patient_name));
CREATE INDEX idx_studies_desc_fts ON studies USING gin(to_tsvector('english', study_description));
CREATE INDEX idx_series_desc_fts ON series USING gin(to_tsvector('english', series_description));
```

**SQLite:**
```sql
-- SQLite FTS5 virtual tables
CREATE VIRTUAL TABLE patients_fts USING fts5(
    patient_id UNINDEXED,
    patient_name,
    content=patients,
    content_rowid=rowid
);

-- Triggers to keep FTS in sync
CREATE TRIGGER patients_fts_insert AFTER INSERT ON patients BEGIN
    INSERT INTO patients_fts(patient_id, patient_name) VALUES (new.patient_id, new.patient_name);
END;
```

## Migration from In-Memory to Persistent Storage

### Steps:

1. **Export current in-memory data** (if any):
   - Stop the server
   - The current implementation does not persist data, so no export is needed

2. **Initialize the database**:
   ```bash
   # For SQLite:
   sqlite3 /var/lib/dicom-server/dicom.db < schema_sqlite.sql
   
   # For PostgreSQL:
   psql -U dicom -d pacsdb < schema_postgresql.sql
   ```

3. **Update configuration**:
   ```json
   {
     "databaseURL": "sqlite:///var/lib/dicom-server/dicom.db"
   }
   ```
   
   Or for PostgreSQL:
   ```json
   {
     "databaseURL": "postgres://dicom:password@localhost/pacsdb"
   }
   ```

4. **Implement DatabaseManager persistence** (code changes required):
   - Add SQLite or PostgreSQL Swift package dependency
   - Implement `insert`, `update`, `delete` operations
   - Replace in-memory dictionaries with database queries

### Code Changes Required

The current `DatabaseManager.swift` uses in-memory dictionaries:
```swift
private var patientIndex: [String: [DICOMMetadata]] = [:]
private var studyIndex: [String: [DICOMMetadata]] = [:]
// etc.
```

For persistence, this needs to be replaced with actual database operations using a Swift database library like:
- **SQLite.swift** - Type-safe SQLite wrapper
- **GRDB.swift** - Full-featured SQLite toolkit with migrations
- **PostgreSQLKit** - Async PostgreSQL driver for Vapor/SwiftNIO

## Performance Considerations

### SQLite
- **Recommended for**: <100K studies, single-server deployments
- **Pros**: No external dependencies, simple setup, adequate performance
- **Cons**: Limited concurrent write performance, no network access
- **Tuning**:
  ```sql
  PRAGMA journal_mode = WAL;  -- Write-Ahead Logging
  PRAGMA synchronous = NORMAL;
  PRAGMA cache_size = -64000;  -- 64MB cache
  PRAGMA temp_store = MEMORY;
  ```

### PostgreSQL
- **Recommended for**: >100K studies, multi-server deployments, high concurrency
- **Pros**: Excellent concurrent performance, advanced features, network access
- **Cons**: Requires separate PostgreSQL server, more complex setup
- **Tuning**:
  ```conf
  shared_buffers = 256MB
  effective_cache_size = 1GB
  maintenance_work_mem = 64MB
  checkpoint_completion_target = 0.9
  wal_buffers = 16MB
  default_statistics_target = 100
  random_page_cost = 1.1
  effective_io_concurrency = 200
  ```

## Future Enhancements (v1.5+)

- **Connection pooling**: Reuse database connections for better performance
- **Prepared statements**: Improve query performance and security
- **Transactions**: Ensure ACID compliance for multi-instance operations
- **Migrations**: Schema versioning and automatic upgrades
- **Backup/restore**: Automated backup and recovery tools
- **Replication**: Multi-server deployments with read replicas
- **Partitioning**: Partition large tables by date for better performance

## References

- DICOM Standard PS3.3 - Information Object Definitions
- DICOM Standard PS3.4 - Service Class Specifications (C-FIND query models)
- SQLite Documentation: https://www.sqlite.org/docs.html
- PostgreSQL Documentation: https://www.postgresql.org/docs/
