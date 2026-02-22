# Sandbox Creation Patterns

### Basic sandbox creation
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: Creating new project sandboxes
- **Detail**: Use `create_sandbox.sh --stack nextjs --title "name"`. Input validation rejects SQL injection attempts and invalid characters.

### Docker socket proxy restrictions
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: Sandbox Docker operations
- **Detail**: Docker socket proxy allows CONTAINERS + IMAGES + VOLUMES only. EXEC and global POST are disabled. Cannot docker exec from within the container.

### Container ID validation
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: Recovery scripts
- **Detail**: recover_sandbox.sh validates container IDs match openclaw naming pattern before any operations.

### Sandbox base images pre-built
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: Sandbox startup
- **Detail**: openclaw-sandbox:bookworm-slim and openclaw-sandbox-browser:bookworm-slim are pre-built in bootstrap. Check existence before creating.
