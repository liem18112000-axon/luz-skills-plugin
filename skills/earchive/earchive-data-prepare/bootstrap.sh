#!/usr/bin/env bash
# Verify deps + install where possible. Exit 0 if ready, 1 with instructions otherwise.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SKILL_DIR/_lib"

have() { command -v "$1" >/dev/null 2>&1; }

install_node() {
    echo "[bootstrap] node not found — attempting install ..."
    if have winget; then
        winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements && return 0
    fi
    if have brew; then
        brew install node && return 0
    fi
    if have apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y -qq nodejs npm && return 0
    fi
    if have dnf; then
        sudo dnf install -y nodejs npm && return 0
    fi
    if have pacman; then
        sudo pacman -S --noconfirm nodejs npm && return 0
    fi
    echo "[bootstrap] could not auto-install node — install manually from https://nodejs.org" >&2
    return 1
}

# 1. node
if ! have node; then
    install_node || exit 1
    if ! have node; then
        echo "[bootstrap] node still not on PATH after install — open a new shell and retry" >&2
        exit 1
    fi
fi

# 2. kubectl
if ! have kubectl; then
    echo "[bootstrap] kubectl not on PATH. Install via:" >&2
    echo "             - Windows: winget install Kubernetes.kubectl"      >&2
    echo "             - macOS:   brew install kubectl"                   >&2
    echo "             - Linux:   https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/" >&2
    exit 1
fi

# 3. mongodb npm package
if [ ! -d "$LIB_DIR/node_modules/mongodb" ]; then
    echo "[bootstrap] installing mongodb npm package ..."
    (cd "$LIB_DIR" && npm install --no-audit --no-fund --silent) || {
        echo "[bootstrap] npm install failed" >&2
        exit 1
    }
fi

echo "[bootstrap] all deps present"
