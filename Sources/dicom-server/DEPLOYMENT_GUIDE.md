# dicom-server Production Deployment Guide

> M4 implementation status (24 October 2026): the supported indexed mode is
> `--database filesystem`, with durable Part 10 files and complete startup reindex.
> SQLite and PostgreSQL options/URLs are refused. SQL deployment examples below
> are historical proposals, not executable supported configurations. Use the
> [current server README](README.md) for startup and migration instructions.

This historical deployment guide includes proposed production configurations;
M4 qualifies local process restart behavior, not production-scale deployment.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Security](#security)
5. [Deployment Patterns](#deployment-patterns)
6. [Monitoring](#monitoring)
7. [Troubleshooting](#troubleshooting)
8. [Performance Tuning](#performance-tuning)

## System Requirements

### Minimum Requirements
- **CPU**: 2 cores
- **RAM**: 2GB
- **Storage**: 100GB+ (depends on study volume)
- **OS**: macOS 14+ or Linux with Swift 6+ runtime

### Recommended for Production
- **CPU**: 4-8 cores
- **RAM**: 8-16GB
- **Storage**: 500GB-2TB SSD
- **Network**: 1Gbps dedicated connection
- **OS**: Ubuntu 22.04 LTS or macOS 14+

### Storage Planning

Calculate storage requirements based on study volume:
- **CT**: ~100-300MB per study
- **MRI**: ~50-200MB per study
- **CR/DR**: ~10-50MB per study
- **US**: ~5-20MB per study

**Example**: 100 studies/day × 150MB average × 365 days = ~5.5TB/year

## Installation

### Option 1: From Source

```bash
# Clone repository
git clone https://github.com/Raster-Lab/DICOMKit.git
cd DICOMKit

# Build release binary
swift build -c release --product dicom-server

# Install
sudo cp .build/release/dicom-server /usr/local/bin/
```

### Option 2: Homebrew (Planned)

```bash
brew install raster-lab/dicomkit/dicom-server
```

### Option 3: Docker (Planned)

```bash
docker pull rasterlab/dicom-server:latest
```

## Configuration

### Configuration File

Create `/etc/dicom-server/config.json`:

```json
{
  "aeTitle": "HOSPITAL_PACS",
  "port": 11112,
  "dataDirectory": "/var/lib/dicom-server/data",
  "databaseURL": "",
  "maxConcurrentConnections": 50,
  "maxPDUSize": 65536,
  "allowedCallingAETitles": [
    "CT_SCANNER_1",
    "CT_SCANNER_2",
    "MR_SCANNER_1",
    "WORKSTATION_1",
    "WORKSTATION_2"
  ],
  "blockedCallingAETitles": [
    "OLD_DEVICE",
    "DECOMMISSIONED"
  ],
  "verbose": false,
  "enableTLS": false
}
```

### Directory Structure

```bash
# Create required directories
sudo mkdir -p /var/lib/dicom-server/data
sudo mkdir -p /etc/dicom-server
sudo mkdir -p /var/log/dicom-server

# Set permissions
sudo chown -R dicom:dicom /var/lib/dicom-server
sudo chown -R dicom:dicom /var/log/dicom-server
sudo chmod 750 /var/lib/dicom-server
sudo chmod 750 /var/log/dicom-server
```

### User Setup

```bash
# Create dedicated user
sudo useradd -r -s /bin/false -m -d /var/lib/dicom-server dicom

# Add to required groups
sudo usermod -aG dicom dicom
```

## Security

### Network Security

#### Firewall Configuration

```bash
# Ubuntu/Debian (ufw)
sudo ufw allow from 10.0.0.0/8 to any port 11112 proto tcp comment 'DICOM Server'
sudo ufw enable

# RHEL/CentOS (firewalld)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port protocol="tcp" port="11112" accept'
sudo firewall-cmd --reload
```

#### Network Isolation

- Deploy on isolated medical network (VLAN)
- Use VPN for remote access
- Never expose directly to internet
- Implement network segmentation

### Access Control

#### AE Title Whitelisting

Always use AE title whitelisting in production:

```json
{
  "allowedCallingAETitles": [
    "CT1", "CT2", "MR1", "WORKSTATION1"
  ]
}
```

#### File Permissions

```bash
# DICOM data files
sudo chmod 600 /var/lib/dicom-server/data/**/*.dcm

# Configuration files
sudo chmod 640 /etc/dicom-server/config.json
sudo chown root:dicom /etc/dicom-server/config.json
```

### TLS/SSL Configuration (Phase D - Planned)

For encrypted connections (planned for v1.5+):

```json
{
  "enableTLS": true,
  "tlsCertificate": "/etc/dicom-server/certs/server.crt",
  "tlsPrivateKey": "/etc/dicom-server/certs/server.key"
}
```

Generate self-signed certificate for testing:
```bash
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes
```

### Data Protection

#### PHI Security

- **No PHI in logs**: Disable verbose mode in production
- **Encrypt at rest**: Use filesystem encryption (LUKS, FileVault)
- **Secure backups**: Encrypt backup archives
- **Access logging**: Monitor all access to DICOM files

#### HIPAA Compliance Checklist

- [ ] Access controls implemented (AE title whitelist)
- [ ] Audit logging enabled
- [ ] Physical security of server hardware
- [ ] Encrypted network connections (TLS)
- [ ] Encrypted data at rest
- [ ] Backup and disaster recovery plan
- [ ] Incident response procedures
- [ ] Regular security audits

## Deployment Patterns

### Pattern 1: Single Server (Small Clinic)

```
[Modalities] --DICOM--> [dicom-server] --Storage--> [Local Disk]
                              |
                         [Workstations]
```

**Configuration:**
- 1 server with 4-8 cores, 8-16GB RAM
- Local SSD storage
- In-memory database (current implementation)
- 10-50 concurrent connections

### Pattern 2: Server with NAS (Medium Practice)

```
[Modalities] --DICOM--> [dicom-server] --NFS/SMB--> [NAS Storage]
                              |
                         [Workstations]
```

**Configuration:**
- Application server: 8 cores, 16GB RAM
- NAS: 10TB+ RAID-6 storage
- Future: SQLite database on NAS
- 20-100 concurrent connections

### Pattern 3: Load Balanced (Large Hospital) - Future

```
                    [Load Balancer]
                     /           \
[Modalities] --> [Server 1]   [Server 2] --> [Shared Storage (SAN)]
                     \           /              [PostgreSQL Database]
                    [Workstations]
```

**Configuration:**
- 2+ application servers
- Shared SAN storage
- PostgreSQL database cluster
- 100+ concurrent connections

## Monitoring

### System Monitoring

#### CPU and Memory

```bash
# Install monitoring tools
sudo apt install htop iotop sysstat

# Monitor in real-time
htop
iotop -o
```

#### Disk Usage

```bash
# Check DICOM data directory
du -sh /var/lib/dicom-server/data/*

# Monitor disk I/O
iostat -x 5
```

#### Network

```bash
# Monitor network traffic
sudo iftop -i eth0 -f "port 11112"

# Check connections
sudo netstat -an | grep 11112
```

### Application Monitoring

#### Statistics Collection

Use the `stats` command (planned enhancement):
```bash
dicom-server stats --port 11112 --verbose
```

#### Log Monitoring

```bash
# Tail server logs
tail -f /var/log/dicom-server/server.log

# Monitor for errors
grep ERROR /var/log/dicom-server/server.log
```

### Alerting

Set up alerts for:
- **Disk space**: <20% free
- **Connection failures**: >5% failure rate
- **Store failures**: >1% failure rate
- **High latency**: >500ms average C-STORE time
- **Service down**: No C-ECHO response

## Troubleshooting

### Common Issues

#### 1. Connection Refused

**Symptoms:**
```
Error: Connection refused
```

**Solutions:**
- Check server is running: `ps aux | grep dicom-server`
- Check port is listening: `sudo netstat -tulpn | grep 11112`
- Check firewall: `sudo ufw status`
- Check AE title whitelist configuration

#### 2. Out of Disk Space

**Symptoms:**
- C-STORE failures
- Slow performance

**Solutions:**
```bash
# Check disk usage
df -h /var/lib/dicom-server

# Clean old studies (if retention policy allows)
find /var/lib/dicom-server/data -type f -mtime +365 -delete

# Archive to tape/cloud
```

#### 3. Too Many Open Files

**Symptoms:**
```
Error: Too many open files
```

**Solutions:**
```bash
# Check limits
ulimit -n

# Increase limits (add to /etc/security/limits.conf)
dicom soft nofile 65536
dicom hard nofile 65536

# Restart server
```

#### 4. Slow Performance

**Symptoms:**
- High C-STORE latency (>1 second)
- Connection timeouts

**Solutions:**
- Check CPU: `top`
- Check I/O: `iostat -x 5`
- Check network: `iftop`
- Reduce max connections
- Upgrade storage to SSD
- Add more RAM

### Debug Mode

Enable verbose logging for troubleshooting:

```json
{
  "verbose": true
}
```

**Warning**: Do not enable in production due to PHI logging risk.

## Performance Tuning

### System Tuning

#### Linux Kernel Parameters

Add to `/etc/sysctl.conf`:
```conf
# Increase network buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Increase file handles
fs.file-max = 2097152

# TCP tuning
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
```

Apply changes:
```bash
sudo sysctl -p
```

#### Storage Optimization

```bash
# Use deadline scheduler for SSDs
echo deadline | sudo tee /sys/block/sda/queue/scheduler

# Disable access time updates
# Add to /etc/fstab:
/dev/sda1 /var/lib/dicom-server ext4 defaults,noatime 0 2
```

### Application Tuning

#### Connection Settings

For high-traffic sites:
```json
{
  "maxConcurrentConnections": 100,
  "maxPDUSize": 131072
}
```

#### Process Management

Use systemd for automatic restart:

Create `/etc/systemd/system/dicom-server.service`:
```ini
[Unit]
Description=DICOM PACS Server
After=network.target

[Service]
Type=simple
User=dicom
Group=dicom
WorkingDirectory=/var/lib/dicom-server
ExecStart=/usr/local/bin/dicom-server start --config /etc/dicom-server/config.json
Restart=always
RestartSec=10
StandardOutput=append:/var/log/dicom-server/server.log
StandardError=append:/var/log/dicom-server/error.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/dicom-server /var/log/dicom-server

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable dicom-server
sudo systemctl start dicom-server
sudo systemctl status dicom-server
```

## Backup and Recovery

### Backup Strategy

#### Daily Backups

```bash
#!/bin/bash
# /usr/local/bin/backup-dicom.sh

BACKUP_DIR="/mnt/backup/dicom"
DATE=$(date +%Y%m%d)

# Backup DICOM data
tar -czf $BACKUP_DIR/data-$DATE.tar.gz /var/lib/dicom-server/data

# Backup configuration
tar -czf $BACKUP_DIR/config-$DATE.tar.gz /etc/dicom-server

# Rotate old backups (keep 30 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
```

#### Disaster Recovery

1. **Install server software**
2. **Restore configuration**: `tar -xzf config-YYYYMMDD.tar.gz -C /`
3. **Restore data**: `tar -xzf data-YYYYMMDD.tar.gz -C /`
4. **Start server**: `sudo systemctl start dicom-server`
5. **Verify**: Test with C-ECHO and C-FIND

### Retention Policy

Define and document:
- **Active studies**: Keep online for X months
- **Archive studies**: Move to tape/cloud after X months
- **Deleted studies**: Retention policy per regulations

## Support and Resources

- **Documentation**: See README.md and inline help
- **Issue Tracker**: https://github.com/Raster-Lab/DICOMKit/issues
- **DICOM Standard**: https://www.dicomstandard.org/

---

**Version**: 1.0.0 (Phase D)  
**Last Updated**: February 2026
