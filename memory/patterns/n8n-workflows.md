# n8n Workflow Patterns

### API authentication
- **Date**: 2026-02-21
- **Status**: WORKS
- **Context**: n8n API calls
- **Detail**: N8N_API_KEY is stored in /data/.openclaw/credentials/N8N_API_KEY (file, not env var). Read from file before API calls.

### Webhook to OpenClaw
- **Date**: 2026-02-22
- **Status**: WORKS
- **Context**: n8n triggering OpenClaw actions
- **Detail**: n8n sends POST to OpenClaw hooks endpoint. Hooks token required in Authorization header. Session key prefixed with "hook:" for isolation. Confirmed working at 17:37 UTC 2026-02-22.

### Credential isolation pattern
- **Date**: 2026-02-21
- **Status**: PREFER
- **Context**: Any external service credentials
- **Detail**: Write credential to /data/.openclaw/credentials/<NAME> file, chmod 600, then unset from env. Read from file when needed.

### n8n internal API URL
- **Date**: 2026-02-22
- **Status**: WORKS
- **Context**: API calls from within openclaw container
- **Detail**: Use http://n8n-zwsw8co4okwkwowk04ko04sg:5678/api/v1 for internal access. n8n-specialist agent has this pre-configured.
