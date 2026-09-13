#!/usr/bin/env bash
#
# install.sh — installe Obsidian, Terraform, AWS CLI, Google Cloud SDK, VS Code
# sur Linux (Debian/Ubuntu, Fedora/RHEL, Arch) et macOS (Homebrew),
# puis génère (si besoin) une clé SSH et l'affiche pour la configuration Git.
#
# Usage:
#   ./install.sh                     # installe tout + clone le repo + configure le vault Obsidian
#   ./install.sh --ssh-only          # ne fait que la clé SSH (pas d'install, pas de vault, pas de cloud)
#   ./install.sh --no-vault          # installe tout mais ne clone rien / pas de vault Obsidian
#   ./install.sh --vault-only        # pas d'install, juste clé SSH + git identity + clonage/config du vault
#   ./install.sh --cloud-only        # pas d'install/ssh/vault, juste configuration interactive AWS + GCP
#   ./install.sh --no-cloud          # installe/clone tout mais saute la configuration AWS/GCP
#   SSH_KEY_COMMENT="you@example.com" REPO_URL="git@github.com:user/repo.git" ./install.sh
#   GIT_USER_NAME="Ton Nom" GIT_USER_EMAIL="you@example.com" ./install.sh   # évite les prompts interactifs
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SSH_KEY_TYPE="ed25519"
SSH_KEY_COMMENT="${SSH_KEY_COMMENT:-ablaadem3@gmail.com}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_${SSH_KEY_TYPE}}"
REPO_URL="${REPO_URL:-git@github.com:Abla-Adem/sync-personal-doc.git}"
VAULT_PATH="${VAULT_PATH:-}"

SKIP_INSTALL=false
SKIP_SSH=false
SKIP_CLOUD=false
SKIP_VAULT=false
for arg in "$@"; do
  case "$arg" in
    --ssh-only)   SKIP_INSTALL=true; SKIP_CLOUD=true; SKIP_VAULT=true ;;
    --no-vault)   SKIP_VAULT=true ;;
    --vault-only) SKIP_INSTALL=true; SKIP_CLOUD=true ;;
    --cloud-only) SKIP_INSTALL=true; SKIP_SSH=true; SKIP_VAULT=true ;;
    --no-cloud)   SKIP_CLOUD=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m[+]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$1"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$1" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ $EUID -ne 0 ]] && have sudo; then
  SUDO="sudo"
else
  SUDO=""
fi

OS="$(uname -s)"
ARCH="$(uname -m)"
PKG_MGR="unknown"

detect_pkg_manager() {
  if [[ "$OS" == "Darwin" ]]; then
    PKG_MGR="brew"
  elif have apt-get; then
    PKG_MGR="apt"
  elif have dnf; then
    PKG_MGR="dnf"
  elif have pacman; then
    PKG_MGR="pacman"
  else
    PKG_MGR="unknown"
  fi
  log "Système détecté: $OS ($ARCH) — gestionnaire de paquets: $PKG_MGR"
}

# ---------------------------------------------------------------------------
# macOS: Homebrew
# ---------------------------------------------------------------------------
ensure_brew() {
  if ! have brew; then
    log "Homebrew non trouvé, installation..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  fi
}

# ---------------------------------------------------------------------------
# VS Code
# ---------------------------------------------------------------------------
install_vscode() {
  if have code; then log "VS Code déjà installé, skip."; return; fi
  log "Installation de VS Code..."
  case "$PKG_MGR" in
    brew)
      brew install --cask visual-studio-code
      ;;
    apt)
      $SUDO apt-get update -y
      $SUDO apt-get install -y wget gpg apt-transport-https
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
      $SUDO install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
        $SUDO tee /etc/apt/sources.list.d/vscode.list > /dev/null
      rm -f /tmp/packages.microsoft.gpg
      $SUDO apt-get update -y
      $SUDO apt-get install -y code
      ;;
    dnf)
      $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
      $SUDO tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      $SUDO dnf check-update -y || true
      $SUDO dnf install -y code
      ;;
    pacman)
      warn "Sur Arch, le paquet AUR 'visual-studio-code-bin' donne le vrai binaire Microsoft."
      if have yay; then
        yay -S --noconfirm visual-studio-code-bin
      else
        $SUDO pacman -S --noconfirm --needed code || warn "Installe un helper AUR (yay/paru) pour visual-studio-code-bin."
      fi
      ;;
    *)
      err "Gestionnaire de paquets non supporté pour VS Code."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Obsidian
# ---------------------------------------------------------------------------
install_obsidian() {
  if have obsidian; then log "Obsidian déjà installé, skip."; return; fi
  log "Installation d'Obsidian..."
  case "$PKG_MGR" in
    brew)
      brew install --cask obsidian
      ;;
    apt)
      if have snap; then
        $SUDO snap install obsidian --classic
      elif have flatpak; then
        $SUDO flatpak install -y flathub md.obsidian.Obsidian
      else
        local url
        url=$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
              | grep -oP '"browser_download_url":\s*"\K[^"]*\.deb(?=")' | grep amd64 | head -n1)
        [[ -z "$url" ]] && url=$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
              | grep -oP '"browser_download_url":\s*"\K[^"]*\.deb(?=")' | head -n1)
        curl -fL "$url" -o /tmp/obsidian.deb
        $SUDO apt-get install -y /tmp/obsidian.deb
        rm -f /tmp/obsidian.deb
      fi
      ;;
    dnf)
      if have flatpak; then
        $SUDO flatpak install -y flathub md.obsidian.Obsidian
      else
        local url
        url=$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest \
              | grep -oP '"browser_download_url":\s*"\K[^"]*\.rpm(?=")' | head -n1)
        curl -fL "$url" -o /tmp/obsidian.rpm
        $SUDO dnf install -y /tmp/obsidian.rpm
        rm -f /tmp/obsidian.rpm
      fi
      ;;
    pacman)
      if have flatpak; then
        $SUDO flatpak install -y flathub md.obsidian.Obsidian
      elif have yay; then
        yay -S --noconfirm obsidian
      else
        warn "Installe flatpak ou un helper AUR (yay/paru) pour Obsidian."
      fi
      ;;
    *)
      err "Gestionnaire de paquets non supporté pour Obsidian."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
install_terraform() {
  if have terraform; then log "Terraform déjà installé, skip."; return; fi
  log "Installation de Terraform..."
  case "$PKG_MGR" in
    brew)
      brew tap hashicorp/tap
      brew install hashicorp/tap/terraform
      ;;
    apt)
      $SUDO apt-get update -y
      $SUDO apt-get install -y gnupg software-properties-common wget
      wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /tmp/hashicorp.gpg
      $SUDO install -D -o root -g root -m 644 /tmp/hashicorp.gpg /etc/apt/keyrings/hashicorp.gpg
      rm -f /tmp/hashicorp.gpg
      echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs 2>/dev/null || echo stable) main" | \
        $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
      $SUDO apt-get update -y
      $SUDO apt-get install -y terraform
      ;;
    dnf)
      $SUDO dnf install -y dnf-plugins-core
      $SUDO dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
      $SUDO dnf install -y terraform
      ;;
    pacman)
      if ! $SUDO pacman -S --noconfirm --needed terraform 2>/dev/null; then
        warn "Paquet 'terraform' indisponible via pacman, téléchargement du binaire officiel..."
        local ver
        ver=$(curl -fsSL https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -oP '"tag_name":\s*"v\K[0-9.]+')
        curl -fL "https://releases.hashicorp.com/terraform/${ver}/terraform_${ver}_linux_amd64.zip" -o /tmp/terraform.zip
        $SUDO unzip -o /tmp/terraform.zip -d /usr/local/bin
        rm -f /tmp/terraform.zip
      fi
      ;;
    *)
      err "Gestionnaire de paquets non supporté pour Terraform."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# AWS CLI
# ---------------------------------------------------------------------------
install_awscli() {
  if have aws; then log "AWS CLI déjà installé, skip."; return; fi
  log "Installation de AWS CLI v2..."
  case "$PKG_MGR" in
    brew)
      brew install awscli
      ;;
    apt|dnf|pacman)
      local aws_arch pkg_url
      case "$ARCH" in
        x86_64) aws_arch="x86_64" ;;
        aarch64|arm64) aws_arch="aarch64" ;;
        *) err "Architecture non supportée pour AWS CLI: $ARCH"; return ;;
      esac
      pkg_url="https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip"
      curl -fL "$pkg_url" -o /tmp/awscliv2.zip
      unzip -qo /tmp/awscliv2.zip -d /tmp
      if [[ -x /usr/local/aws-cli/v2/current/bin/aws ]]; then
        $SUDO /tmp/aws/install --update
      else
        $SUDO /tmp/aws/install
      fi
      rm -rf /tmp/awscliv2.zip /tmp/aws
      ;;
    *)
      err "Gestionnaire de paquets non supporté pour AWS CLI."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Google Cloud SDK (gcloud)
# ---------------------------------------------------------------------------
install_gcloud() {
  if have gcloud; then log "gcloud CLI déjà installé, skip."; return; fi
  log "Installation de Google Cloud SDK..."
  case "$PKG_MGR" in
    brew)
      brew install --cask google-cloud-sdk
      ;;
    apt)
      $SUDO apt-get update -y
      $SUDO apt-get install -y apt-transport-https ca-certificates gnupg curl
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
        $SUDO gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
        $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
      $SUDO apt-get update -y
      $SUDO apt-get install -y google-cloud-cli
      ;;
    dnf)
      $SUDO tee /etc/yum.repos.d/google-cloud-sdk.repo > /dev/null <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
      $SUDO dnf install -y google-cloud-cli
      ;;
    pacman)
      warn "Utilisation du script d'installation officiel Google (hors gestionnaire de paquets)."
      curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
      ;;
    *)
      err "Gestionnaire de paquets non supporté pour gcloud, utilisation du script officiel."
      curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Clé SSH
# ---------------------------------------------------------------------------
generate_ssh_key() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ -f "$SSH_KEY_PATH" ]]; then
    log "Une clé SSH existe déjà à $SSH_KEY_PATH, elle ne sera pas écrasée."
  else
    log "Génération d'une nouvelle clé SSH ($SSH_KEY_TYPE)..."
    ssh-keygen -t "$SSH_KEY_TYPE" -C "$SSH_KEY_COMMENT" -f "$SSH_KEY_PATH" -N ""
  fi

  eval "$(ssh-agent -s)" > /dev/null 2>&1 || true
  ssh-add "$SSH_KEY_PATH" > /dev/null 2>&1 || true

  echo
  echo "=================================================================="
  echo " Clé publique SSH (à ajouter sur GitHub/GitLab/Bitbucket) :"
  echo "=================================================================="
  cat "${SSH_KEY_PATH}.pub"
  echo "=================================================================="
  echo
  echo "GitHub  -> https://github.com/settings/ssh/new"
  echo "GitLab  -> https://gitlab.com/-/profile/keys"
  echo
}

# ---------------------------------------------------------------------------
# Identité Git globale (user.name / user.email) — interactif avec défauts
# ---------------------------------------------------------------------------
configure_git_identity() {
  local current_name current_email default_name default_email name email

  current_name=$(git config --global user.name 2>/dev/null || true)
  current_email=$(git config --global user.email 2>/dev/null || true)

  default_name="${GIT_USER_NAME:-$current_name}"
  default_email="${GIT_USER_EMAIL:-${current_email:-$SSH_KEY_COMMENT}}"

  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    name="$GIT_USER_NAME"
  else
    read -rp "Nom Git (user.name) [défaut: ${default_name:-<vide, obligatoire>}] : " name
    name="${name:-$default_name}"
  fi

  if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    email="$GIT_USER_EMAIL"
  else
    read -rp "Email Git (user.email) [défaut: $default_email] : " email
    email="${email:-$default_email}"
  fi

  if [[ -z "$name" ]]; then
    warn "Aucun nom fourni, git config --global user.name laissé tel quel."
  else
    git config --global user.name "$name"
  fi
  git config --global user.email "$email"

  log "Git configuré : user.name=\"$(git config --global user.name 2>/dev/null)\", user.email=\"$(git config --global user.email)\""
}

# ---------------------------------------------------------------------------
# Configuration interactive AWS / GCP
# ---------------------------------------------------------------------------
ask_yes_no() {
  local prompt="$1" ans
  read -rp "$prompt [o/N] : " ans
  [[ "$ans" =~ ^[oOyY] ]]
}

configure_aws() {
  if ! have aws; then
    warn "AWS CLI non installé, configuration AWS ignorée."
    return
  fi
  if aws sts get-caller-identity > /dev/null 2>&1; then
    log "AWS CLI déjà configuré et fonctionnel (identité vérifiée), skip."
    return
  fi
  if ! ask_yes_no "Configurer AWS CLI maintenant (Access Key ID / Secret Access Key requis) ?"; then
    log "Configuration AWS ignorée. Relance plus tard avec: ./install.sh --cloud-only"
    return
  fi
  aws configure
  if aws sts get-caller-identity; then
    log "AWS configuré avec succès."
  else
    warn "La vérification AWS a échoué, vérifie tes identifiants (aws configure)."
  fi
}

configure_gcp() {
  if ! have gcloud; then
    warn "gcloud CLI non installé, configuration GCP ignorée."
    return
  fi
  if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    log "gcloud déjà authentifié, skip."
    return
  fi
  if ! ask_yes_no "Configurer gcloud (GCP) maintenant (connexion via navigateur + choix du projet) ?"; then
    log "Configuration GCP ignorée. Relance plus tard avec: ./install.sh --cloud-only"
    return
  fi
  gcloud init
}

# ---------------------------------------------------------------------------
# Attente : vérifie que la clé SSH est bien reconnue par l'hébergeur Git
# ---------------------------------------------------------------------------
test_ssh_auth() {
  local host="$1"
  local output
  output=$(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T "git@${host}" 2>&1) || true
  echo "$output" | grep -qiE "successfully authenticated|welcome to gitlab"
}

wait_for_git_ssh() {
  local host="$1"
  log "Attente de la configuration SSH pour $host (le script ne clonera qu'une fois l'auth réussie)..."
  until test_ssh_auth "$host"; do
    warn "Authentification SSH vers $host pas encore fonctionnelle."
    echo "  1) Copie la clé publique affichée ci-dessus (${SSH_KEY_PATH}.pub)"
    case "$host" in
      github.com) echo "  2) Ajoute-la sur https://github.com/settings/ssh/new" ;;
      gitlab.com) echo "  2) Ajoute-la sur https://gitlab.com/-/profile/keys" ;;
      *)          echo "  2) Ajoute-la dans les paramètres SSH de $host" ;;
    esac
    read -rp "Appuie sur [Entrée] une fois fait pour réessayer (ou tape 'skip' pour ignorer la vérification) : " ans
    if [[ "$ans" == "skip" ]]; then
      warn "Vérification SSH ignorée, le clonage risque d'échouer si la clé n'est pas configurée."
      return 0
    fi
  done
  log "Authentification SSH vers $host réussie."
}

# ---------------------------------------------------------------------------
# Coffre-fort Obsidian : clone le repo Git et le fait reconnaître comme vault
# ---------------------------------------------------------------------------
urlencode() {
  local s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:$i:1}"
    case "$c" in
      [a-zA-Z0-9.~_/-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

setup_obsidian_vault() {
  if [[ -z "$REPO_URL" ]]; then
    read -rp "URL du dépôt Git à cloner comme coffre-fort Obsidian (laisser vide pour ignorer) : " REPO_URL
  fi
  if [[ -z "$REPO_URL" ]]; then
    warn "Aucune URL fournie, étape du coffre-fort Obsidian ignorée."
    return
  fi

  if [[ "$REPO_URL" =~ ^(git@|ssh://git@) ]]; then
    local host
    host=$(echo "$REPO_URL" | sed -E 's#^(git@|ssh://git@)([^:/]+).*#\2#')
    wait_for_git_ssh "$host"
  else
    warn "URL non-SSH détectée, pas de vérification de clé SSH (Git pourra demander un identifiant/token)."
  fi

  local repo_name
  repo_name=$(basename -s .git "$REPO_URL")
  if [[ -z "$VAULT_PATH" ]]; then
    read -rp "Chemin local du coffre-fort [défaut: $HOME/Documents/$repo_name] : " VAULT_PATH
  fi
  VAULT_PATH="${VAULT_PATH:-$HOME/Documents/$repo_name}"

  if [[ -d "$VAULT_PATH/.git" ]]; then
    log "Le dépôt existe déjà dans $VAULT_PATH, mise à jour (git pull)..."
    git -C "$VAULT_PATH" pull
  else
    log "Clonage de $REPO_URL dans $VAULT_PATH..."
    mkdir -p "$(dirname "$VAULT_PATH")"
    git clone "$REPO_URL" "$VAULT_PATH"
  fi

  mkdir -p "$VAULT_PATH/.obsidian"
  log "Dossier .obsidian créé/présent : $VAULT_PATH reconnu comme coffre-fort Obsidian."

  local uri="obsidian://open?path=$(urlencode "$VAULT_PATH")"
  if [[ "$OS" == "Darwin" ]] && have open; then
    log "Ouverture du coffre-fort dans Obsidian..."
    open "$uri" || true
  elif have xdg-open; then
    log "Ouverture du coffre-fort dans Obsidian..."
    xdg-open "$uri" || true
  else
    warn "Impossible d'ouvrir Obsidian automatiquement depuis ce shell (pas de xdg-open/open, ex: WSL sans intégration GUI)."
  fi

  echo
  echo "Si Obsidian ne s'est pas ouvert automatiquement sur le bon coffre-fort :"
  echo "  Obsidian -> 'Open folder as vault' -> sélectionne : $VAULT_PATH"
  echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  detect_pkg_manager

  if [[ "$SKIP_INSTALL" == false ]]; then
    if [[ "$PKG_MGR" == "brew" ]]; then
      ensure_brew
    fi
    install_vscode
    install_obsidian
    install_terraform
    install_awscli
    install_gcloud
  fi

  if [[ "$SKIP_SSH" == false ]]; then
    generate_ssh_key
    configure_git_identity
  fi

  if [[ "$SKIP_CLOUD" == false ]]; then
    configure_aws
    configure_gcp
  fi

  if [[ "$SKIP_VAULT" == false ]]; then
    setup_obsidian_vault
  fi

  log "Terminé."
}

main "$@"
