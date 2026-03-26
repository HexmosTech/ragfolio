#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Linux one-line developer toolchain installer.
#
# Installs Python 3.12.10 + uv, Git, nvm, Node.js 22.22.0,
# and generates an RSA 4096-bit SSH key pair.
#
# Usage:
#   bash <(curl -fsSL 'https://<host>/install.sh')
#   bash <(curl -fsSL 'https://<host>/install.sh') --email user@example.com
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

log_step()  { echo "[Step $1] $2"; }
log_ok()    { echo "[OK] $1"; }
log_skip()  { echo "[SKIP] $1 - $2"; }
log_warn()  { echo "[WARN] $1"; }
log_fatal() { echo "[ERROR] $1"; exit 1; }

# ---------------------------------------------------------------------------
# OS guard — Linux only
# ---------------------------------------------------------------------------

if [[ "$(uname -s)" != "Linux" ]]; then
    log_fatal "This script supports Linux only. Detected: $(uname -s)"
fi

# ---------------------------------------------------------------------------
# Distro-aware package installer helper
# ---------------------------------------------------------------------------

pkg_install() {
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y "$@"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "$@"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "$@"
    else
        log_fatal "No supported package manager found (apt-get, dnf, yum)."
    fi
}

# ---------------------------------------------------------------------------
# Shell rc file detection — writes to the correct config for bash/zsh/profile
# ---------------------------------------------------------------------------

get_shell_rc_files() {
    local files=()
    local user_shell
    user_shell="$(basename "${SHELL:-/bin/bash}")"

    case "$user_shell" in
        zsh)  [[ -f "$HOME/.zshrc" ]]  && files+=("$HOME/.zshrc")  || files+=("$HOME/.zshrc") ;;
        bash) [[ -f "$HOME/.bashrc" ]] && files+=("$HOME/.bashrc") || files+=("$HOME/.bashrc") ;;
        *)    files+=("$HOME/.profile") ;;
    esac

    # Also pick up the other common rc if it exists (covers users who switch shells)
    [[ "$user_shell" != "bash" ]] && [[ -f "$HOME/.bashrc" ]] && files+=("$HOME/.bashrc")
    [[ "$user_shell" != "zsh"  ]] && [[ -f "$HOME/.zshrc" ]]  && files+=("$HOME/.zshrc")

    echo "${files[@]}"
}

# Append lines to all detected rc files if a marker string is not already present.
# Usage: append_to_rc "MARKER_STRING" "line1" "line2" ...
append_to_rc() {
    local marker="$1"; shift
    local rc_files
    read -ra rc_files <<< "$(get_shell_rc_files)"

    for rc in "${rc_files[@]}"; do
        if ! grep -q "$marker" "$rc" 2>/dev/null; then
            for line in "$@"; do
                echo "$line" >> "$rc"
            done
            echo "  -> Updated $rc"
        fi
    done
}

# ---------------------------------------------------------------------------
# Email validation and sanitization
# ---------------------------------------------------------------------------

validate_email() {
    [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

sanitize_email() {
    echo "$1" | tr '<>:"/\|?*' '-'
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

EMAIL=""
for arg in "$@"; do
    case "$arg" in
        --email=*) EMAIL="${arg#--email=}" ;;
    esac
done

# ---------------------------------------------------------------------------
# Email collection
# ---------------------------------------------------------------------------

if [[ -z "$EMAIL" ]]; then
    while true; do
        read -rp "Enter your email address which you used for creating github account: " EMAIL
        if validate_email "$EMAIL"; then
            break
        fi
        echo "[ERROR] Invalid email address. Please try again."
    done
else
    if ! validate_email "$EMAIL"; then
        log_fatal "Invalid email address: '$EMAIL'"
    fi
fi

RAW_EMAIL="$EMAIL"
SANITIZED_EMAIL="$(sanitize_email "$EMAIL")"

# ---------------------------------------------------------------------------
# Step 1 — Install curl
# ---------------------------------------------------------------------------

install_curl() {
    log_step 1 "Installing curl"

    if command -v curl &>/dev/null; then
        log_skip "curl" "already installed"
        return 0
    fi

    if pkg_install curl; then
        log_ok "curl installed"
    else
        log_warn "curl installation failed"
    fi
}

# ---------------------------------------------------------------------------
# Step 2 — Install Python 3.12.10 + uv
# ---------------------------------------------------------------------------

install_python() {
    log_step 2 "Installing Python 3.12.10 + uv"

    local current_ver=""
    if command -v python3 &>/dev/null; then
        current_ver="$(python3 --version 2>&1 | awk '{print $2}')"
    elif command -v python &>/dev/null; then
        current_ver="$(python --version 2>&1 | awk '{print $2}')"
    fi

    if [[ "$current_ver" == "3.12.10" ]]; then
        log_skip "Python" "3.12.10 already installed"
    else
        echo "Installing pyenv build dependencies..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
                libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
                libncurses5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
                libffi-dev liblzma-dev
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y gcc gcc-c++ make openssl-devel zlib-devel \
                bzip2-devel readline-devel sqlite-devel wget curl llvm \
                ncurses-devel xz-devel tk-devel libxml2-devel libxmlsec1-devel \
                libffi-devel
        elif command -v yum &>/dev/null; then
            sudo yum install -y gcc gcc-c++ make openssl-devel zlib-devel \
                bzip2-devel readline-devel sqlite-devel wget curl llvm \
                ncurses-devel xz-devel tk-devel libxml2-devel libxmlsec1-devel \
                libffi-devel
        fi

        echo "Installing pyenv..."
        if [[ -d "$HOME/.pyenv" ]]; then
            echo "pyenv already exists. Updating..."
            (cd "$HOME/.pyenv" && git pull)
        else
            git clone https://github.com/pyenv/pyenv.git "$HOME/.pyenv"
        fi

        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"

        append_to_rc "PYENV_ROOT" \
            'export PYENV_ROOT="$HOME/.pyenv"' \
            'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' \
            'eval "$(pyenv init -)"'

        echo "Installing Python 3.12.10 via pyenv..."
        if pyenv install 3.12.10; then
            pyenv global 3.12.10
            pyenv rehash
            log_ok "Python 3.12.10 installed"
        else
            log_warn "Python 3.12.10 installation failed"
            return 1
        fi
    fi

    echo "Installing uv..."
    if pip install uv 2>/dev/null || pip3 install uv 2>/dev/null; then
        log_ok "uv installed"
    else
        log_warn "uv installation failed"
    fi
}

# ---------------------------------------------------------------------------
# Step 3 — Install Git
# ---------------------------------------------------------------------------

install_git() {
    log_step 3 "Installing Git"

    if command -v git &>/dev/null; then
        log_skip "Git" "already installed ($(git --version))"
        return 0
    fi

    if pkg_install git; then
        log_ok "Git installed"
    else
        log_warn "Git installation failed"
    fi
}

# ---------------------------------------------------------------------------
# Step 3.5 — Configure Git
# ---------------------------------------------------------------------------

configure_git() {
    log_step 3.5 "Configuring Git"

    local name="${1%%@*}"

    echo "Setting git global user.name to: $name"
    git config --global user.name "$name"

    echo "Setting git global user.email to: $1"
    git config --global user.email "$1"

    log_ok "Git configured"
}

# ---------------------------------------------------------------------------
# Step 4 — Install nvm + Node.js 22.22.0
# ---------------------------------------------------------------------------

install_nvm_and_node() {
    log_step 4 "Installing nvm and Node.js 22.22.0"

    export NVM_DIR="$HOME/.nvm"

    if [[ -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        log_skip "nvm" "already installed"
    else
        echo "Installing nvm..."
        if [[ -d "$NVM_DIR" ]]; then
            rm -rf "$NVM_DIR"
        fi
        git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        log_ok "nvm installed"
    fi

    append_to_rc "NVM_DIR" \
        'export NVM_DIR="$HOME/.nvm"' \
        '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' \
        '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

    if nvm list 2>/dev/null | grep -q "22\.22\.0"; then
        log_skip "Node.js" "22.22.0 already installed"
    else
        echo "Installing Node.js 22.22.0 via nvm..."
        if nvm install 22.22.0; then
            log_ok "Node.js 22.22.0 installed"
        else
            log_warn "Node.js 22.22.0 installation failed"
            return 1
        fi
    fi

    nvm use 22.22.0
    nvm alias default 22.22.0
    log_ok "Node.js 22.22.0 active"
}

# ---------------------------------------------------------------------------
# Step 5 — Generate SSH key pair
# ---------------------------------------------------------------------------

generate_ssh_key() {
    local email="$1"
    local sanitized="$2"

    log_step 5 "Generating SSH key pair"

    local ssh_dir="$HOME/.ssh"
    local private_key="$ssh_dir/id-rsa-$sanitized"
    local public_key="$private_key.pub"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if ! command -v ssh-keygen &>/dev/null; then
        log_fatal "ssh-keygen is not available on PATH. Please install OpenSSH and try again."
    fi

    if [[ -f "$private_key" ]]; then
        log_skip "SSH key" "key file already exists at $private_key"
    else
        if ! ssh-keygen -t rsa -b 4096 -C "$email" -f "$private_key" -N ""; then
            log_fatal "ssh-keygen failed"
        fi
        log_ok "SSH key pair generated at $private_key"
    fi

    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)" 2>/dev/null || true
    ssh-add "$private_key" 2>/dev/null && log_ok "SSH key added to agent" || log_warn "Could not add key to ssh-agent"

    local ssh_config="$ssh_dir/config"
    local config_block
    config_block=$(cat <<SSHEOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id-rsa-$sanitized
    IdentitiesOnly yes
SSHEOF
)

    if [[ ! -f "$ssh_config" ]]; then
        echo "$config_block" > "$ssh_config"
        chmod 600 "$ssh_config"
        log_ok "SSH config file created at $ssh_config"
    elif ! grep -q "Host github.com" "$ssh_config"; then
        printf '\n%s\n' "$config_block" >> "$ssh_config"
        log_ok "GitHub entry added to SSH config"
    else
        log_skip "SSH config" "GitHub entry already exists"
    fi

    echo ""
    echo "Your public SSH key ($public_key):"
    cat "$public_key"
}

# ---------------------------------------------------------------------------
# Main installation pipeline
# ---------------------------------------------------------------------------

install_curl
install_python
install_git
configure_git "$RAW_EMAIL"
install_nvm_and_node
generate_ssh_key "$RAW_EMAIL" "$SANITIZED_EMAIL"

echo ""
log_ok "All steps completed successfully."
echo ""
echo "IMPORTANT: Close this terminal and open a new shell for all PATH changes to take effect."
echo "Then verify the installation by running:"
echo "  curl --version"
echo "  python3 --version"
echo "  git --version"
echo "  nvm --version"
echo "  node --version"
echo ""
exit 0
