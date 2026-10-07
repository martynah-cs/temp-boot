#!/usr/bin/env bash
# Installs mise, git, docker and the AWS CLI.
# Supports macOS (Homebrew) and Debian/Ubuntu (apt). Safe to re-run.
set -euo pipefail

log() { printf '==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# Prints 1 or 2. WSL2 runs a real Linux kernel (version string contains "WSL2").
wsl_version() {
  if grep -qi 'wsl2' /proc/version 2>/dev/null || [[ -d /run/WSL ]]; then
    echo 2
  else
    echo 1
  fi
}

# Share Windows Git Credential Manager and keep line endings sane across the boundary.
configure_wsl_git() {
  local gcm="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
  if [[ -x "$gcm" ]] && ! git config --global --get credential.helper >/dev/null; then
    log "Using Windows Git Credential Manager"
    git config --global credential.helper "\"$gcm\""
  fi
  git config --global --get core.autocrlf >/dev/null || git config --global core.autocrlf input
}

install_macos() {
  if ! have brew; then
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  have mise || { log "Installing mise"; brew install mise; }
  have git  || { log "Installing git"; brew install git; }
  have aws  || { log "Installing AWS CLI"; brew install awscli; }

  if ! have docker && [[ ! -d /Applications/Docker.app ]]; then
    log "Installing Docker Desktop"
    brew install --cask docker
  fi
}

install_debian() {
  local sudo_cmd=""
  [[ $EUID -ne 0 ]] && sudo_cmd="sudo"

  $sudo_cmd apt-get update
  $sudo_cmd apt-get install -y ca-certificates curl gnupg unzip

  have git || { log "Installing git"; $sudo_cmd apt-get install -y git; }

  if have docker; then
    :
  elif is_wsl && [[ -d "/mnt/c/Program Files/Docker/Docker" ]]; then
    log "Docker Desktop found on Windows but not integrated with this distro"
    log "Enable it in Docker Desktop: Settings > Resources > WSL integration > ${WSL_DISTRO_NAME:-this distro}"
  else
    if is_wsl && [[ "$(wsl_version)" == "1" ]]; then
      echo "WSL1 cannot run Docker. Convert with: wsl --set-version ${WSL_DISTRO_NAME:-<distro>} 2" >&2
      exit 1
    fi
    log "Installing Docker Engine"
    curl -fsSL https://get.docker.com | $sudo_cmd sh
    if [[ $EUID -ne 0 ]]; then
      $sudo_cmd usermod -aG docker "$USER"
      log "Log out and back in for docker group membership to apply"
    fi
    if is_wsl; then
      if [[ -d /run/systemd/system ]]; then
        $sudo_cmd systemctl enable --now docker
      else
        log "systemd is not enabled in this distro. Add to /etc/wsl.conf:"
        log "  [boot]"
        log "  systemd=true"
        log "then run 'wsl --shutdown' from Windows. Starting dockerd via service for now"
        $sudo_cmd service docker start || true
      fi
    fi
  fi

  if is_wsl; then
    configure_wsl_git
  fi

  if ! have aws; then
    log "Installing AWS CLI v2"
    local arch tmp
    arch="$(uname -m)"
    tmp="$(mktemp -d)"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$tmp/awscliv2.zip"
    unzip -q "$tmp/awscliv2.zip" -d "$tmp"
    $sudo_cmd "$tmp/aws/install" --update
    rm -rf "$tmp"
  fi

  if ! have mise; then
    log "Installing mise"
    curl -fsSL https://mise.run | sh
    log "Add 'eval \"\$(~/.local/bin/mise activate bash)\"' to your shell profile"
  fi
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)
    if is_wsl; then
      log "WSL detected (distro: ${WSL_DISTRO_NAME:-unknown}, WSL$(wsl_version))"
      if [[ "$PWD" == /mnt/* ]]; then
        log "Warning: working under /mnt/c is slow. Keep repos in the Linux filesystem (~/)"
      fi
    fi
    if have apt-get; then
      install_debian
    else
      echo "Unsupported Linux distribution (apt-get not found)" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

log "Installed versions"
for cmd in mise git docker aws; do
  if have "$cmd"; then
    printf '%-6s ' "$cmd"
    case "$cmd" in
      mise)   mise --version ;;
      git)    git --version ;;
      docker) docker --version ;;
      aws)    aws --version ;;
    esac
  else
    printf '%-6s not on PATH yet\n' "$cmd"
  fi
done

if [[ "$(uname -s)" == "Darwin" ]]; then
  log "Open Docker Desktop once to finish setup"
fi
log "To activate mise in zsh, add: eval \"\$(mise activate zsh)\" to ~/.zshrc"
