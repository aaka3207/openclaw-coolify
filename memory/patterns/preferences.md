# User Preferences

### Direct action over planning
- **Date**: 2026-02-21
- **Status**: PREFER
- **Context**: All tasks
- **Detail**: User prefers concise instructions and direct action. Avoid lengthy explanations or formal planning overhead.

### Root user for container
- **Date**: 2026-02-21
- **Status**: PREFER
- **Context**: Docker container runtime
- **Detail**: Container runs as root. Non-root was attempted but reverted due to HDD permission issues. Do not attempt non-root again.

### Pin versions in Dockerfile
- **Date**: 2026-02-21
- **Status**: PREFER
- **Context**: Dockerfile, package installs
- **Detail**: HDD server is slow. Pin all install versions to avoid unnecessary downloads on rebuild. Include checksums where possible.

### sudo required for docker
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: SSH commands to 192.168.1.100
- **Detail**: User ameer is not in docker group. All docker commands need sudo.

### chown -R causes HDD stalls
- **Date**: 2026-02-21
- **Status**: AVOID
- **Context**: Container bootstrap, large volume directories
- **Detail**: Recursive chown on large HDD dirs causes long stalls. Use non-recursive for top-level dirs only.
