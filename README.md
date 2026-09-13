# `install.sh` — Documentation détaillée

Script bash unique (`install.sh`) qui installe un environnement de dev complet sur **Linux** (Debian/Ubuntu, Fedora/RHEL, Arch) et **macOS** (Homebrew), génère une clé SSH, attend que Git soit configuré, puis clone un dépôt et le configure comme coffre-fort Obsidian.

## Sommaire

1. [Vue d'ensemble du flux](#vue-densemble-du-flux)
2. [Options de la ligne de commande](#options-de-la-ligne-de-commande)
3. [Variables d'environnement](#variables-denvironnement)
4. [Détail technique par étape](#détail-technique-par-étape)
5. [Cas d'usage](#cas-dusage)
6. [Limitations connues](#limitations-connues)

---

## Vue d'ensemble du flux

```
main()
 ├─ detect_pkg_manager()        → détermine OS + gestionnaire de paquets
 ├─ (si installs pas sautés)
 │   ├─ ensure_brew()           → macOS seulement
 │   ├─ install_vscode()
 │   ├─ install_obsidian()
 │   ├─ install_terraform()
 │   ├─ install_awscli()
 │   └─ install_gcloud()
 ├─ generate_ssh_key()          → toujours exécuté
 └─ (si vault pas sauté)
     └─ setup_obsidian_vault()
         ├─ wait_for_git_ssh()  → boucle bloquante tant que l'auth SSH échoue
         └─ git clone + mkdir .obsidian + ouverture Obsidian
```

Chaque fonction d'installation est **idempotente** : elle vérifie d'abord si l'outil est déjà présent (`have <commande>`) et fait `return` immédiatement si oui — on peut relancer le script sans rien casser.

---

## Options de la ligne de commande

| Flag | Effet |
|---|---|
| *(aucun)* | Installe tout, génère la clé SSH, clone le repo et configure le vault |
| `--ssh-only` | Saute les installations **et** le vault : ne fait que la clé SSH |
| `--no-vault` | Fait les installations et la clé SSH, mais saute le clonage/vault |
| `--vault-only` | Saute les installations : ne fait que la clé SSH + clonage/vault |

En interne (install.sh:25-33), ces flags positionnent deux booléens :

```bash
SKIP_INSTALL=false
SKIP_VAULT=false
```

`main()` (install.sh:433-454) lit ensuite ces deux variables pour décider quels blocs exécuter.

---

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `SSH_KEY_COMMENT` | `helpjudesavetheworld@gmail.com` | Commentaire embarqué dans la clé SSH (généralement ton email) |
| `SSH_KEY_PATH` | `~/.ssh/id_ed25519` | Emplacement de la clé privée/publique |
| `REPO_URL` | *(vide → prompt interactif)* | URL du dépôt Git à cloner comme coffre-fort |
| `VAULT_PATH` | *(vide → prompt, puis `~/Documents/<nom-du-repo>`)* | Dossier local du vault |

Exemple pour tout piloter sans aucune interaction :

```bash
SSH_KEY_COMMENT="moi@exemple.com" \
REPO_URL="git@github.com:user/repo.git" \
VAULT_PATH="$HOME/Documents/mon-vault" \
./install.sh
```

---

## Détail technique par étape

### 1. Détection de l'OS et du gestionnaire de paquets — `detect_pkg_manager()`

```bash
OS="$(uname -s)"        # "Darwin" ou "Linux"
ARCH="$(uname -m)"      # "x86_64", "arm64", "aarch64"...
```

Puis, plutôt que de deviner la distribution par son nom, le script teste la **présence du binaire** du gestionnaire de paquets (`have apt-get`, `have dnf`, `have pacman`) — ça marche donc aussi sur les dérivés (Mint, Pop!_OS, CentOS, Manjaro...) sans liste exhaustive de distros. Résultat stocké dans `PKG_MGR` : `brew` / `apt` / `dnf` / `pacman` / `unknown`.

### 2. `SUDO` conditionnel

```bash
if [[ $EUID -ne 0 ]] && have sudo; then SUDO="sudo"; else SUDO=""; fi
```

Toutes les commandes d'installation système sont préfixées par `$SUDO` — vide si le script tourne déjà en root (conteneur), sinon `sudo`.

### 3. Installation de chaque outil

Chaque fonction (`install_vscode`, `install_obsidian`, `install_terraform`, `install_awscli`, `install_gcloud`) suit le même patron :

```bash
install_X() {
  if have X; then log "déjà installé, skip."; return; fi
  case "$PKG_MGR" in
    brew)   ... ;;
    apt)    ... ;;
    dnf)    ... ;;
    pacman) ... ;;
    *)      err "non supporté" ;;
  esac
}
```

Méthode utilisée par outil et par OS :

| Outil | macOS (brew) | Debian/Ubuntu (apt) | Fedora (dnf) | Arch (pacman) |
|---|---|---|---|---|
| **VS Code** | `brew install --cask visual-studio-code` | Dépôt officiel Microsoft (clé GPG + `apt` repo) | Dépôt `.repo` Microsoft | `pacman -S code` (build OSS) ou AUR `visual-studio-code-bin` via `yay` |
| **Obsidian** | `brew install --cask obsidian` | `snap`, sinon `flatpak`, sinon `.deb` téléchargé depuis la dernière release GitHub | `flatpak`, sinon `.rpm` GitHub | `flatpak`, sinon AUR via `yay` |
| **Terraform** | `brew install hashicorp/tap/terraform` | Dépôt officiel HashiCorp | Dépôt officiel HashiCorp | `pacman -S terraform`, fallback binaire zip officiel |
| **AWS CLI v2** | `brew install awscli` | Installeur officiel AWS (`awscliv2.zip`) | idem | idem |
| **gcloud (GCP)** | `brew install --cask google-cloud-sdk` | Dépôt officiel `packages.cloud.google.com` | Dépôt `.repo` Google | Script officiel `sdk.cloud.google.com` (pas de paquet natif fiable) |

Points notables :
- **VS Code/apt** (install.sh:89-99) : télécharge la clé GPG Microsoft, la place dans `/etc/apt/keyrings/`, ajoute la ligne `deb [...] https://packages.microsoft.com/repos/code stable main`, puis `apt-get install code`.
- **Obsidian** n'a pas de dépôt officiel Linux : le script essaie dans l'ordre `snap` → `flatpak` → téléchargement direct du `.deb`/`.rpm` le plus récent via l'API GitHub (`api.github.com/repos/obsidianmd/obsidian-releases/releases/latest`).
- **AWS CLI** (install.sh:226-254) détecte l'architecture (`x86_64` vs `aarch64`) pour choisir le bon zip, et utilise `--update` si une install précédente est détectée dans `/usr/local/aws-cli/v2/current/bin/aws`.
- **gcloud sur Arch/unknown** : pas de paquet pacman officiel fiable, donc bascule sur le script d'installation officiel Google en une ligne.

### 4. Génération de la clé SSH — `generate_ssh_key()` (install.sh:302-330)

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[[ -f "$SSH_KEY_PATH" ]] || ssh-keygen -t ed25519 -C "$SSH_KEY_COMMENT" -f "$SSH_KEY_PATH" -N ""
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"
cat "${SSH_KEY_PATH}.pub"   # affichage
```

- **Ne jamais écraser une clé existante** : si le fichier existe déjà, le script log un message et passe directement à l'affichage.
- La clé est chargée dans `ssh-agent` pour que Git puisse s'en servir immédiatement.
- Affiche la clé publique + les liens directs GitHub/GitLab + les commandes `git config --global user.name/email` prêtes à copier.

### 5. Attente de la configuration Git — `test_ssh_auth()` / `wait_for_git_ssh()` (install.sh:335-360)

C'est le mécanisme qui **bloque le script tant que la clé n'est pas ajoutée** sur l'hébergeur :

```bash
test_ssh_auth() {
  local host="$1"
  output=$(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T "git@${host}" 2>&1) || true
  echo "$output" | grep -qiE "successfully authenticated|welcome to gitlab"
}
```

- `-T` : ouvre une session SSH sans shell interactif (comportement standard pour tester l'auth Git).
- `-o BatchMode=yes` : interdit toute demande de mot de passe interactive, échoue proprement si la clé n'est pas reconnue.
- `-o StrictHostKeyChecking=accept-new` : accepte automatiquement la clé d'hôte au premier contact (pas de prompt `yes/no`).
- Le test réussit si la sortie contient `"successfully authenticated"` (GitHub) ou `"welcome to gitlab"` (GitLab).

```bash
wait_for_git_ssh() {
  until test_ssh_auth "$host"; do
    # affiche les instructions (lien vers la page SSH keys de l'hébergeur)
    read -rp "Appuie sur [Entrée] une fois fait pour réessayer (ou 'skip') : " ans
    [[ "$ans" == "skip" ]] && return 0
  done
}
```

Boucle `until` : tant que `test_ssh_auth` échoue, le script **attend une action humaine** (ajouter la clé sur GitHub/GitLab), puis retente à chaque appui sur Entrée. Taper `skip` sort de la boucle sans garantie (le clonage suivant pourra échouer si la clé n'est vraiment pas configurée).

### 6. Configuration du coffre-fort Obsidian — `setup_obsidian_vault()` (install.sh:377-428)

Étapes dans l'ordre :

1. **Récupère l'URL du repo** (`$REPO_URL` ou prompt). Vide → étape entièrement sautée.
2. **Détecte le protocole** : si l'URL commence par `git@` ou `ssh://git@`, extrait le nom d'hôte par regex (`sed -E 's#^(git@|ssh://git@)([^:/]+).*#\2#'`) et appelle `wait_for_git_ssh` dessus. Sinon (HTTPS), avertit que Git pourra demander un identifiant/token.
3. **Détermine le dossier local** : `$VAULT_PATH` ou prompt, défaut `~/Documents/<nom-du-repo>` (nom extrait via `basename -s .git`).
4. **Clone ou met à jour** :
   ```bash
   if [[ -d "$VAULT_PATH/.git" ]]; then git -C "$VAULT_PATH" pull
   else git clone "$REPO_URL" "$VAULT_PATH"; fi
   ```
   → relancer le script sur un vault déjà cloné fait un simple `pull`, pas de re-clone.
5. **Marque le dossier comme vault Obsidian** : `mkdir -p "$VAULT_PATH/.obsidian"`. C'est la seule condition nécessaire pour qu'Obsidian reconnaisse un dossier comme coffre-fort — pas besoin de fichiers de config particuliers, Obsidian les crée à la première ouverture.
6. **Tente d'ouvrir Obsidian automatiquement** via l'URI officiel `obsidian://open?path=<chemin encodé>`, déclenché par `open` (macOS) ou `xdg-open` (Linux avec environnement graphique). La fonction `urlencode()` (install.sh:365-375) encode caractères par caractère (garde lettres/chiffres/`.~_/-`, encode le reste en `%XX`) pour gérer les chemins avec espaces ou accents.
7. Si aucun outil d'ouverture n'est disponible (ex: WSL sans intégration GUI), affiche simplement le chemin et l'instruction manuelle *"Open folder as vault"*.

---

## Cas d'usage

**Tout installer d'un coup, sans interaction :**
```bash
SSH_KEY_COMMENT="toi@exemple.com" \
REPO_URL="git@github.com:user/vault.git" \
./install.sh
```

**Juste régénérer/afficher la clé SSH :**
```bash
./install.sh --ssh-only
```

**Outils déjà installés, juste cloner le vault :**
```bash
REPO_URL="git@github.com:user/vault.git" ./install.sh --vault-only
```

**Installer les outils sans toucher à un vault Git :**
```bash
./install.sh --no-vault
```

---

## Limitations connues

- **WSL sans intégration GUI** : `xdg-open`/`open` absents → pas d'ouverture automatique d'Obsidian, seulement le clonage + la préparation du dossier `.obsidian`.
- **Arch Linux** : VS Code (build MS), Obsidian et parfois Terraform n'ont pas de paquet officiel dans les dépôts standards — le script recommande/utilise `yay`/`paru` (AUR) ou `flatpak` en fallback, mais ne les installe pas lui-même.
- **`test_ssh_auth`** dépend du texte retourné par le serveur SSH de l'hébergeur (`successfully authenticated` / `welcome to gitlab`) — un hébergeur Git auto-hébergé (Gitea, Bitbucket Server...) avec un message différent ne sera pas reconnu automatiquement ; utiliser `skip` dans ce cas.
- Le script suppose une **architecture x86_64 ou arm64/aarch64** pour AWS CLI ; toute autre architecture fait échouer `install_awscli` proprement (message d'erreur, pas de crash).
