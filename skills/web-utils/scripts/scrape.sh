#!/bin/bash

# Configuration
MODE="${1:-auto}"
URL="${2}"
ANYCRAWL_URL="${ANYCRAWL_API_URL:-http://anycrawldocker:13939}"
SCRIPT_DIR="$(dirname "$0")"

# Fallback Usage
if [ -z "$URL" ] && [[ "$MODE" == http* ]]; then
    # Handle if user swapped args: scrape.sh <url>
    URL="$MODE"
    MODE="auto"
fi

if [ -z "$URL" ]; then
    echo "Usage: $0 [--mode auto|curl|hyper|browser-use|botasaurus|anycrawl] <url>"
    exit 1
fi

# ----------------------------
# SSRF Protection
# ----------------------------
validate_url() {
    local url="$1"

    # Must start with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "ERROR: Only http:// and https:// URLs are allowed" >&2
        return 1
    fi

    # Extract hostname
    local host
    host=$(echo "$url" | sed -E 's|https?://([^/:]+).*|\1|')

    # Block internal Docker service names
    local blocked_hosts="docker-proxy registry searxng localhost openclaw anycrawldocker"
    for blocked in $blocked_hosts; do
        if [ "$host" = "$blocked" ]; then
            echo "ERROR: Access to internal service '$host' is blocked" >&2
            return 1
        fi
    done

    # Block loopback and metadata IPs directly in URL
    if echo "$host" | grep -qE '^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|169\.254\.|0\.|localhost)'; then
        echo "ERROR: Access to private/internal IP range is blocked" >&2
        return 1
    fi

    # Resolve hostname and check for private IPs
    local resolved_ip
    resolved_ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1)

    if [ -n "$resolved_ip" ]; then
        if echo "$resolved_ip" | grep -qE '^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|169\.254\.|0\.)'; then
            echo "ERROR: URL resolves to private/internal IP ($resolved_ip)" >&2
            return 1
        fi
    fi

    return 0
}

# Validate before any scraping
if ! validate_url "$URL"; then
    exit 1
fi

echo "Scraping Target: $URL (Mode: $MODE)" >&2

run_curl() {
    echo "Trying Curl..." >&2
    curl -sL \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) width=1920 height=1080" \
        --max-time 10 \
        "$URL"
}

run_hyper() {
    echo "Trying HyperAgent (Bun)..." >&2
    if [ -n "$OPENAI_API_KEY" ]; then
        bun "$SCRIPT_DIR/scrape_hyperagent.ts" "$URL"
    else
        echo "Skipping HyperAgent (OPENAI_API_KEY missing)" >&2
        return 1
    fi
}

run_browser_use() {
    echo "Trying Browser-Use (Python)..." >&2
    if [ -n "$OPENAI_API_KEY" ]; then
        # Ensure playwright is usable
        export PLAYWRIGHT_BROWSERS_PATH=${XDG_CACHE_HOME:-/data/.cache}/ms-playwright
        python3 "$SCRIPT_DIR/scrape_browser_use.py" "$URL"
    else
        echo "Skipping Browser-Use (OPENAI_API_KEY missing)" >&2
        return 1
    fi
}

run_botasaurus() {
    echo "Trying Botasaurus..." >&2
    python3 "$SCRIPT_DIR/scrape_botasaurus.py" "$URL"
}

run_anycrawl() {
    echo "Trying AnyCrawl Service..." >&2
    ENCODED_URL=$(echo "$URL" | jq -sRr @uri)
    curl -s "${ANYCRAWL_URL}/?url=${ENCODED_URL}"
}

# Execution Logic
if [ "$MODE" == "auto" ]; then
    # Cascade: Curl -> Hyper -> BrowserUse -> Botasaurus
    OUT=$(run_curl)
    if [ -n "$OUT" ] && [ "${#OUT}" -gt 500 ]; then echo "$OUT"; exit 0; fi
    
    # If Curl fails/blocks (short content), try Hyper
    run_hyper || run_browser_use || run_botasaurus
    
else
    # Explicit Mode
    case $MODE in
        --mode) 
            # Recursion for safety if args were weird
            "$0" "$3" "$4" 
            ;;
        curl) run_curl ;;
        hyper|hyperagent) run_hyper ;;
        browser-use|browser_use) run_browser_use ;;
        botasaurus) run_botasaurus ;;
        anycrawl) run_anycrawl ;;
        *) echo "Unknown mode: $MODE"; exit 1 ;;
    esac
fi
