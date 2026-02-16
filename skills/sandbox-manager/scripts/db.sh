#!/bin/bash
set -e

# Configuration
DB_PATH="${OPENCLAW_STATE_DIR:-/data/.openclaw}/sandboxes.db"
mkdir -p "$(dirname "$DB_PATH")"

# Initialize Schema
init_db() {
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS sandboxes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE,
    stack TEXT,
    port INTEGER,
    tunnel_url TEXT,
    volume_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
}

# Sanitize a value for safe SQL string interpolation
# Escapes single quotes by doubling them (SQL standard)
sanitize_sql() {
    local input="$1"
    if printf '%s' "$input" | grep -qP '[\x00-\x08\x0b\x0c\x0e-\x1f]' 2>/dev/null; then
        echo "ERROR: Input contains invalid characters" >&2
        return 1
    fi
    printf '%s' "${input//\'/\'\'}"
}

# Validate identifier (container names, stack names)
# Only alphanumeric, hyphens, underscores, dots allowed
validate_identifier() {
    local input="$1"
    local label="${2:-identifier}"
    if [[ ! "$input" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        echo "ERROR: Invalid $label: '$input'. Only alphanumeric, hyphens, underscores, dots allowed." >&2
        return 1
    fi
    if [[ ${#input} -gt 128 ]]; then
        echo "ERROR: $label too long (max 128 chars)" >&2
        return 1
    fi
}

# Validate that a value is a positive integer (for ports)
validate_port() {
    local input="$1"
    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid port number: '$input'" >&2
        return 1
    fi
}

# Helper to run queries
query_db() {
    sqlite3 "$DB_PATH" "$1"
}

# Run init if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_db
    echo "Database initialized at $DB_PATH"
fi
