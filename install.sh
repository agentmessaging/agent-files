#!/bin/bash
# =============================================================================
# AFP Installer - Agent Files Protocol
# =============================================================================
#
# Installs the AFP scripts so agents can share files through an S3-compatible
# store. AFP is self-contained; AMP is optional (it only supplies the manifest
# owner and the messages that carry references).
#
# Usage:
#   ./install.sh                  # Install to ~/.local/bin (default)
#   ./install.sh /usr/local/bin   # Install to a custom location
#
# =============================================================================

set -e

INSTALL_DIR="${1:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_SRC="${SCRIPT_DIR}/scripts"

# Remote install: when piped via curl, scripts/ won't exist locally.
# Download them from GitHub into a temp directory.
REMOTE_BASE="https://raw.githubusercontent.com/agentmessaging/agent-files/main/scripts"
TEMP_DIR=""
if [ ! -d "$SCRIPTS_SRC" ]; then
    TEMP_DIR=$(mktemp -d)
    SCRIPTS_SRC="$TEMP_DIR"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Agent Files Protocol (AFP) — Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

for tool in jq curl openssl; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${RED}Error: ${tool} is required but not installed.${NC}"
        echo "  Install: brew install ${tool} (macOS) or apt install ${tool} (Linux)"
        exit 1
    fi
done

if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
    echo -e "${RED}Error: shasum or sha256sum is required.${NC}"
    exit 1
fi

# curl 7.75 or newer is needed for --aws-sigv4
_curl_ver=$(curl --version 2>/dev/null | head -1 | awk '{print $2}')
_maj=${_curl_ver%%.*}
_min=${_curl_ver#*.}; _min=${_min%%.*}
if [ "$_maj" -lt 7 ] 2>/dev/null || { [ "$_maj" -eq 7 ] && [ "$_min" -lt 75 ]; } 2>/dev/null; then
    echo -e "${RED}Error: curl 7.75 or newer is required (found ${_curl_ver}).${NC}"
    echo "  Install: brew install curl (macOS) or update your distribution's curl"
    exit 1
fi

echo -e "  ${GREEN}Prerequisites OK${NC}"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Install scripts
echo "Installing AFP scripts to ${INSTALL_DIR}..."

SCRIPTS=(
    "afp-helper.sh"
    "afp-config.sh"
    "afp-put.sh"
    "afp-get.sh"
    "afp-ls.sh"
    "afp-link.sh"
    "afp-rm.sh"
    "afp-capabilities.sh"
)

for script in "${SCRIPTS[@]}"; do
    # Download from GitHub if not available locally (remote install via curl | bash)
    if [ ! -f "${SCRIPTS_SRC}/${script}" ] && [ -n "$TEMP_DIR" ]; then
        curl -fsSL "${REMOTE_BASE}/${script}" -o "${SCRIPTS_SRC}/${script}" 2>/dev/null || true
    fi

    if [ -f "${SCRIPTS_SRC}/${script}" ]; then
        cp "${SCRIPTS_SRC}/${script}" "${INSTALL_DIR}/${script}"
        chmod +x "${INSTALL_DIR}/${script}"
        # Symlink without .sh for convenience, like the amp-* scripts (afp-put -> afp-put.sh)
        if [ "$script" != "afp-helper.sh" ]; then
            ln -sf "$script" "${INSTALL_DIR}/${script%.sh}"
        fi
        echo -e "  ${GREEN}Installed${NC} ${script}"
    else
        echo -e "  ${RED}Missing${NC} ${script}"
    fi
done

# Cleanup temp directory
if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

echo ""

# Check PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "${YELLOW}Note: ${INSTALL_DIR} is not in your PATH.${NC}"
    echo ""
    echo "  Add it to your shell profile:"
    echo ""

    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        zsh)
            echo "    echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.zshrc"
            echo "    source ~/.zshrc"
            ;;
        bash)
            echo "    echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ~/.bashrc"
            echo "    source ~/.bashrc"
            ;;
        *)
            echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
            ;;
    esac
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}AFP installed successfully${NC}"
echo ""
echo "  Quick start:"
echo "    # 1. Add a space (an S3-compatible bucket)"
echo "    afp-config.sh add shared --endpoint http://host:3900 --bucket afp \\"
echo "        --region garage --access-key <key> --secret-file <file> --default"
echo ""
echo "    # 2. Store a file and get its reference"
echo "    afp-put.sh report.pdf"
echo ""
echo "    # 3. Fetch it, on this or another machine with the same space"
echo "    afp-get.sh afp://shared/2026/10/report.pdf"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
