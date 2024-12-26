# Bash Scripts Collection

A comprehensive collection of useful bash scripts for system administration, automation, and maintenance tasks.

## Author

Frederic Bourouliou

## Overview

This repository contains a collection of bash scripts designed to automate various system administration tasks, maintenance operations, and routine procedures. Each script is designed to be modular, configurable, and easy to use.

## Scripts List

1. **backup.sh**
   - Automated backup script for directories and databases
   - Supports MySQL and PostgreSQL databases
   - Uses rsync/scp for remote backups

2. **log_cleaner.sh**
   - Automated log cleaning and archiving
   - Configurable retention periods
   - Compression of archived logs

3. **web_deploy.sh**
   - Web application deployment automation
   - Git integration
   - Dependencies management
   - Cache management

4. **service_monitor.sh**
   - Service health monitoring
   - Email/SMS alerts
   - Support for systemctl services
   - Port monitoring

5. **dir_sync.sh**
   - Directory synchronization using rsync
   - Support for local and remote directories
   - Configurable sync options

6. **disk_alert.sh**
   - Disk usage monitoring
   - Configurable threshold alerts
   - Email notifications

7. **server_setup.sh**
   - Initial server configuration
   - Package installation
   - Firewall setup
   - User management

8. **backup_rotation.sh**
   - Backup retention management
   - Configurable retention periods
   - Automated cleanup

9. **media_processor.sh**
   - Batch image/video processing
   - Support for ImageMagick and FFmpeg
   - Format conversion and optimization

10. **security_audit.sh**
    - Quick security checks
    - Configuration verification
    - Package security audit

11. **system_cleanup.sh**
    - System maintenance and cleanup
    - Package cache cleanup
    - Temporary files management

12. **system_update.sh**
    - System-wide package updates
    - Support for apt/yum/dnf/brew
    - Update reporting
    - Pre/Post update scripts
    - System snapshots

13. **file_search.sh**
    - Advanced file search capabilities
    - Content search support
    - Multiple export formats (CSV, JSON)
    - Configurable search patterns

14. **network_test.sh**
    - Network connectivity testing
    - Bandwidth measurement
    - Port scanning
    - DNS resolution testing
    - Detailed reporting

15. **process_monitor.sh**
    - Process monitoring and management
    - CPU and memory usage tracking
    - Automatic process restart
    - Historical metrics collection
    - Daily reporting

16. **ssl_check.sh**
    - SSL certificate monitoring
    - Expiration alerts
    - Chain validation
    - Security strength assessment
    - Detailed reporting

17. **db_backup.sh**
    - Database backup automation
    - Support for MySQL, PostgreSQL, MongoDB, SQLite
    - Compression and encryption
    - Remote storage sync
    - Backup verification

18. **log_manager.sh**
    - Centralized log management
    - Log rotation and archiving
    - Log analysis and reporting
    - Space management
    - Pattern-based analysis

19. **cron_manager.sh**
    - Centralized cron job management
    - Job validation and verification
    - Backup and restore
    - Template support
    - Status monitoring

20. **service_manager.sh**
    - Service lifecycle management
    - Health monitoring
    - Automatic restart
    - Resource usage tracking
    - Dependency management

## Installation

1. Clone the repository:
```bash
git clone [repository-url]
cd bash_scripts
```

2. Make scripts executable:
```bash
chmod +x *.sh
```

3. Configure the scripts:
```bash
# Edit the config files in the config/ directory
# Set up your environment variables
```

## Usage

Each script can be run independently. Basic usage:

```bash
./script_name.sh [options]
```

For detailed usage of each script, use the -h or --help option:

```bash
./script_name.sh --help
```

## Configuration

- Configuration files are stored in the `config/` directory
- Each script has its own configuration file (e.g., `backup.conf`, `network_test.conf`)
- Environment variables can be set in `.env` file
- Each script has its own configuration options

## Directory Structure

```
bash_scripts/
├── README.md
├── *.sh
├── config/
│   ├── backup.conf
│   ├── network_test.conf
│   ├── process_monitor.conf
│   └── ...
├── logs/
├── backups/
├── reports/
├── status/
├── templates/
└── archives/
```

## Requirements

- Bash shell (4.0 or later recommended)
- Core utilities (rsync, ssh, etc.)
- Specific requirements are listed in each script's header
- Additional tools as needed (e.g., mysqldump, pg_dump for database scripts)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. 