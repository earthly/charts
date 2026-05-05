#!/usr/bin/env bash
#
# Creates a GitHub App for Lunar using the manifest flow.
#
# Usage:
#   ./scripts/create-github-app.sh [--org <org-name>] [--github-url <url>]
#
# Options:
#   --org          GitHub organization to own the app (omit for personal account)
#   --github-url   GitHub base URL (default: https://github.com, use for GHES)

set -euo pipefail

GITHUB_URL="https://github.com"
ORG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org)
            ORG="$2"
            shift 2
            ;;
        --github-url)
            GITHUB_URL="${2%/}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

for cmd in curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

if [[ -n "$ORG" ]]; then
    CREATION_URL="${GITHUB_URL}/organizations/${ORG}/settings/apps/new"
else
    CREATION_URL="${GITHUB_URL}/settings/apps/new"
fi

TMPDIR=$(mktemp -d)

# Find a free port for the callback server.
CALLBACK_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
CALLBACK_URL="http://127.0.0.1:${CALLBACK_PORT}/callback"

# The manifest defines the GitHub App's permissions, events, and metadata.
# These are the minimum permissions required for Lunar to operate.
MANIFEST=$(python3 -c "
import json
print(json.dumps({
    'name': 'Lunar',
    'url': 'https://earthly.dev/lunar',
    'redirect_url': '${CALLBACK_URL}',
    'hook_attributes': {
        'url': 'https://example.com/placeholder',
        'active': False,
    },
    'public': False,
    'default_permissions': {
        'actions': 'read',
        'checks': 'write',
        'contents': 'read',
        'metadata': 'read',
        'pull_requests': 'write',
        'repository_hooks': 'write',
        'organization_hooks': 'write',
    },
    'default_events': [
        'push',
        'pull_request',
        'workflow_run',
    ],
}))
")

# Start a callback server that captures the code from GitHub's redirect.
# Loops until a valid code is received, ignoring stray requests (e.g. favicon).
python3 - "$CALLBACK_PORT" "$TMPDIR" <<'PYSERVER' &
import sys, os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

code_file = os.path.join(sys.argv[2], "code")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        code = parse_qs(urlparse(self.path).query).get("code", [None])[0]
        if code:
            with open(code_file, "w") as f:
                f.write(code)
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h2>GitHub App created. You can close this tab.</h2></body></html>")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass

server = HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
while not os.path.exists(code_file):
    server.handle_request()
PYSERVER
CALLBACK_PID=$!
trap 'rm -rf "$TMPDIR"; kill "$CALLBACK_PID" 2>/dev/null || true' EXIT

# Create a temporary HTML file that auto-submits the manifest to GitHub.
FORM_FILE="${TMPDIR}/form.html"
cat > "$FORM_FILE" <<FORMHTML
<html>
<body>
<form id="f" method="post" action="${CREATION_URL}?state=lunar-setup">
<input type="hidden" name="manifest" />
</form>
<script>
document.querySelector('input[name=manifest]').value = JSON.stringify(${MANIFEST});
document.getElementById('f').submit();
</script>
</body>
</html>
FORMHTML

echo ""
echo "Opening browser to create the GitHub App..."
echo ""

if command -v xdg-open &>/dev/null; then
    xdg-open "file://${FORM_FILE}" 2>/dev/null || true
elif command -v open &>/dev/null; then
    open "file://${FORM_FILE}" || true
else
    echo "Open this file in your browser: file://${FORM_FILE}"
fi

echo "After reviewing the app settings, click \"Create GitHub App\"."
echo "Waiting..."

# Wait for the callback server to receive the code.
while [[ ! -f "${TMPDIR}/code" ]]; do
    if ! kill -0 "$CALLBACK_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done

if [[ ! -f "${TMPDIR}/code" ]]; then
    echo "Error: did not receive a response from GitHub." >&2
    exit 1
fi

CODE=$(cat "${TMPDIR}/code")

# Exchange the temporary code for the app credentials.
API_URL="${GITHUB_URL}/api/v3"
if [[ "$GITHUB_URL" == "https://github.com" ]]; then
    API_URL="https://api.github.com"
fi

RESPONSE=$(curl -sS -X POST \
    -H "Accept: application/vnd.github+json" \
    "${API_URL}/app-manifests/${CODE}/conversions")

APP_ID=""
APP_NAME=""
APP_SLUG=""
WEBHOOK_SECRET=""
PEM=""
eval "$(echo "$RESPONSE" | python3 -c "
import sys, json, shlex
d = json.load(sys.stdin)
print(f'APP_ID={shlex.quote(str(d.get(\"id\", \"\")))}')
print(f'APP_NAME={shlex.quote(str(d.get(\"name\", \"\")))}')
print(f'APP_SLUG={shlex.quote(str(d.get(\"slug\", d.get(\"name\", \"\"))))}')
print(f'WEBHOOK_SECRET={shlex.quote(str(d.get(\"webhook_secret\", \"\")))}')
pem = d.get('pem', '')
print(f'PEM={shlex.quote(pem)}')
" 2>/dev/null)"

if [[ -z "$APP_ID" || -z "$PEM" ]]; then
    echo "Error: failed to create GitHub App. Response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

PEM_BASE64=$(printf '%s' "$PEM" | base64 -w0 2>/dev/null || printf '%s' "$PEM" | base64 | tr -d '\n')

# Save the private key to a file the user can keep.
PEM_FILE="lunar-github-app-${APP_ID}.pem"
printf '%s' "$PEM" > "$PEM_FILE"
chmod 600 "$PEM_FILE"

if [[ -n "$ORG" ]]; then
    INSTALL_URL="${GITHUB_URL}/organizations/${ORG}/settings/apps/${APP_SLUG}/installations"
else
    INSTALL_URL="${GITHUB_URL}/settings/apps/${APP_SLUG}/installations"
fi

cat <<EOF

============================================
 GitHub App created successfully!
============================================

  App name:  ${APP_NAME}
  App ID:    ${APP_ID}

--------------------------------------------
 Next steps
--------------------------------------------

1. Install the app on your organization:
   ${INSTALL_URL}

2. After installing, note the installation ID from the URL:
   .../installations/<id>

3. Set these environment variables on Hub:

   HUB_GITHUB_APP_ID=${APP_ID}
   HUB_GITHUB_APP_INSTALL_ID=<installation-id-from-step-2>
   HUB_GITHUB_APP_PRIVATE_KEY=${PEM_BASE64}
   HUB_GITHUB_WEBHOOK_SECRET=${WEBHOOK_SECRET}

--------------------------------------------
 Private Key
--------------------------------------------
 Base64 (for HUB_GITHUB_APP_PRIVATE_KEY): shown above
 Raw PEM saved to: $(pwd)/${PEM_FILE}

 Keep this safe — it cannot be retrieved from GitHub again.

EOF
