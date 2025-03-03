# CLAUDE.md Guide for Bash Scripts Codebase

## Commands

- Install application service: `sudo ./Install_service.sh <JAR_FILE_PATH> <PROFILE> [PORT]`
  - Valid profiles: dev, test, prod
- Uninstall application service: `sudo ./uninstall_service.sh`

- Install PostgreSQL database: 
  - Basic: `sudo ./install_db.sh`
  - With options: `sudo ./install_db.sh -v 15 -d dbname -u username -p password -g postgres_password`
  - See all options: `./install_db.sh --help`

- Uninstall PostgreSQL database:
  - Basic: `sudo ./uninstall_db.sh`
  - With options: `sudo ./uninstall_db.sh -v 15 -d dbname -u username -p`
  - Complete removal: `sudo ./uninstall_db.sh --purge`
  - See all options: `./uninstall_db.sh --help`

- Check script syntax: `shellcheck <script_name>.sh`

## Code Style

- Scripts use `#!/bin/bash` shebang
- Use `set -e` for error handling
- Functions: snake_case naming convention
- Variables: UPPER_CASE for constants, lower_case for regular variables
- Always validate input parameters
- Use helper functions for logging: `log()`, `warn()`, `error_exit()`
- Include proper error handling with descriptive messages
- Document script purpose and usage at the top
- Group related commands into functions with descriptive names
- Use `sudo` when needed for privileged operations
- Always quote variable references: `"$variable"`
- Use descriptive echo statements for user feedback
- Indent with 2 spaces (not tabs)