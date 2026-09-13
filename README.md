# `install.sh` — Documentation détaillée

Script bash unique (`install.sh`) qui installe un environnement de dev complet sur **Linux** (Debian/Ubuntu, Fedora/RHEL, Arch) et **macOS** (Homebrew), génère une clé SSH, attend que Git soit configuré, puis clone un dépôt et le configure comme coffre-fort Obsidian.

## Sommaire

1. [Vue d'ensemble du flux](#vue-densemble-du-flux)
2. [Options de la ligne de commande](#options-de-la-ligne-de-commande)
3. [Variables d'environnement](#variables-denvironnement)
4. [Détail technique par étape](#détail-technique-par-étape)
5. [Cas d'usage](#cas-dusage)
6. [Installation sur une nouvelle machine](#installation-sur-une-nouvelle-machine)
7. [Limitations connues](#limitations-connues)

---

## Vue d'ensemble du flux

```
main()
 ├─ detect_pkg_manager()        → détermine OS + gestionnaire de paquets
 ├─ (si installs pas sautés: SKIP_INSTALL)
 │   ├─ ensure_brew()           → macOS seulement
 │   ├─ install_vscode()
 │   ├─ install_obsidian()
 │   ├─ install_terraform()
 │   ├─ install_awscli()
 │   ├─ install_aws_sdk()       → boto3 (Python)
 │   ├─ install_gcloud()
 │   ├─ install_gcp_sdk()       → google-api-python-client + google-auth (Python)
 │   ├─ install_docker()
 │   ├─ install_kubectl()
 │   ├─ install_helm()
 │   ├─ install_jq()
 │   ├─ install_claude_code()   → npm, installe Node.js si besoin
 │   └─ (si --with-extras) install_optional_tool() pour chaque OPTIONAL_TOOLS
 ├─ (si ssh pas sauté: SKIP_SSH)
 │   ├─ generate_ssh_key()
 │   └─ configure_git_identity()
 ├─ (si cloud pas sauté: SKIP_CLOUD)
 │   ├─ configure_aws()
 │   └─ configure_gcp()
 ├─ (si vault pas sauté: SKIP_VAULT)
 │   └─ setup_obsidian_vault()
 │       ├─ wait_for_git_ssh()  → boucle bloquante tant que l'auth SSH échoue
 │       └─ git clone + mkdir .obsidian + ouverture Obsidian
 └─ (si installs pas sautés) print_optional_tools_summary()
     → liste les outils optionnels encore manquants, avec description
```

Chaque fonction d'installation est **idempotente** : elle vérifie d'abord si l'outil est déjà présent (`have <commande>`) et fait `return` immédiatement si oui — on peut relancer le script sans rien casser.

---

## Options de la ligne de commande

| Flag | Effet |
|---|---|
| *(aucun)* | Installe tout, génère la clé SSH, configure git, configure AWS/GCP, clone le repo et configure le vault, puis liste les outils optionnels manquants |
| `--ssh-only` | Saute installations, cloud et vault : ne fait que la clé SSH + identité git |
| `--no-vault` | Fait tout le reste, mais saute le clonage/vault |
| `--vault-only` | Saute installations et cloud : ne fait que la clé SSH + identité git + clonage/vault |
| `--cloud-only` | Saute installations, ssh et vault : ne fait que la configuration interactive AWS + GCP |
| `--no-cloud` | Fait tout le reste, mais saute la configuration AWS/GCP |
| `--with-extras` | En plus d'un run normal, installe aussi tous les outils optionnels (`yq`, `k9s`, `kubectx`, `gh`, `direnv`, `shellcheck`) |

En interne, ces flags positionnent cinq booléens :

```bash
SKIP_INSTALL=false
SKIP_SSH=false
SKIP_CLOUD=false
SKIP_VAULT=false
WITH_EXTRAS=false
```

`main()` lit ensuite ces variables pour décider quels blocs exécuter.

---

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `SSH_KEY_COMMENT` | `ablaadem3@gmail.com` | Commentaire embarqué dans la clé SSH (généralement ton email) |
| `SSH_KEY_PATH` | `~/.ssh/id_ed25519` | Emplacement de la clé privée/publique |
| `REPO_URL` | `git@github.com:Abla-Adem/sync-personal-doc.git` | URL du dépôt Git à cloner comme coffre-fort (surchargeable) |
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

Chaque fonction (`install_vscode`, `install_obsidian`, `install_terraform`, `install_awscli`, `install_gcloud`, `install_docker`, `install_kubectl`, `install_helm`, `install_jq`, `install_claude_code`) suit le même patron :

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
| **Docker** | `brew install --cask docker` | Script officiel `get.docker.com` | Script officiel `get.docker.com` | `pacman -S docker docker-compose` |
| **kubectl** | `brew install kubectl` | Binaire officiel `dl.k8s.io` (version stable, arch détectée) | idem | idem |
| **Helm** | `brew install helm` | Script officiel `get-helm-3` | idem | idem |
| **jq** | `brew install jq` | `apt-get install jq` | `dnf install jq` | `pacman -S jq` |
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` (Node.js via `brew install node` si absent) | idem (Node.js via `apt-get install nodejs npm` si absent) | idem (`dnf`) | idem (`pacman`) |

Points notables :
- **VS Code/apt** (install.sh:111-121) : télécharge la clé GPG Microsoft, la place dans `/etc/apt/keyrings/`, ajoute la ligne `deb [...] https://packages.microsoft.com/repos/code stable main`, puis `apt-get install code`.
- **Obsidian** n'a pas de dépôt officiel Linux : le script essaie dans l'ordre `snap` → `flatpak` → téléchargement direct du `.deb`/`.rpm` le plus récent via l'API GitHub (`api.github.com/repos/obsidianmd/obsidian-releases/releases/latest`).
- **Docker/Linux** : après installation, le script active/démarre le service (`systemctl enable --now docker`) et ajoute l'utilisateur courant au groupe `docker` (`usermod -aG docker`) pour éviter d'avoir à préfixer chaque commande par `sudo` — un déconnexion/reconnexion (ou reboot) est nécessaire pour que ce changement de groupe prenne effet.
- **kubectl** n'a pas de paquet universellement à jour dans les dépôts distro par défaut : le script télécharge directement le binaire officiel correspondant à la dernière version stable (`dl.k8s.io/release/stable.txt`) et à l'architecture détectée (`amd64`/`arm64`), comme pour AWS CLI.
- **Helm** utilise le script d'installation officiel du projet (`get-helm-3`), qui gère lui-même la détection d'architecture et les droits d'écriture dans `/usr/local/bin`.
- **AWS CLI** (install.sh:278-306) détecte l'architecture (`x86_64` vs `aarch64`) pour choisir le bon zip, et utilise `--update` si une install précédente est détectée dans `/usr/local/aws-cli/v2/current/bin/aws`.
- **gcloud sur Arch/unknown** : pas de paquet pacman officiel fiable, donc bascule sur le script d'installation officiel Google en une ligne.
- **Claude Code CLI** dépend de Node.js/npm : `ensure_npm()` l'installe automatiquement si absent, avant de lancer `npm install -g @anthropic-ai/claude-code` (sans `sudo` sur macOS où `brew` gère déjà les permissions npm, avec `sudo` sur Linux où npm système écrit dans `/usr/lib/node_modules`).

### 4. SDK Python (AWS et GCP) — `install_aws_sdk()` / `install_gcp_sdk()`

Ces deux fonctions installent des **bibliothèques Python**, pas des CLI — utile pour scripter l'infra en Python plutôt qu'en bash pur.

- **`ensure_pip3()`** : installe `python3-pip` (apt/dnf), `python-pip` (pacman) ou `brew install python` si `pip3` est absent.
- **`pip_install()`** : wrapper autour de `pip3 install --user`. Sur Debian/Ubuntu récents (PEP 668), un `pip install` système est bloqué avec l'erreur `externally-managed-environment` — la fonction détecte ce cas précis dans la sortie d'erreur et relance automatiquement avec `--break-system-packages`.
- **`install_aws_sdk()`** : vérifie `python3 -c "import boto3"`, sinon installe `boto3` (le SDK AWS officiel pour Python).
- **`install_gcp_sdk()`** : vérifie `import googleapiclient`, sinon installe `google-api-python-client google-auth google-auth-httplib2 google-auth-oauthlib`. Il n'existe pas d'équivalent pip unique à `boto3` côté Google (les libs `google-cloud-*` sont éclatées par service) — ce paquet couvre l'accès générique aux API Google, à compléter au besoin avec une lib spécifique (`google-cloud-storage`, `google-cloud-compute`, ...).

### 5. Outils optionnels — `OPTIONAL_TOOLS`, `install_optional_tool()`, `print_optional_tools_summary()`

Six outils utiles mais non indispensables, **jamais installés par défaut** :

| Outil | Description | Méthode d'installation |
|---|---|---|
| `yq` | Équivalent de `jq` pour YAML | Binaire GitHub `mikefarah/yq` (Linux) / `brew install yq` |
| `k9s` | TUI pour naviguer/débugger un cluster Kubernetes | Binaire GitHub `derailed/k9s` / `brew install k9s` |
| `kubectx` | Bascule rapide de contexte/namespace K8s (inclut `kubens`) | Binaires GitHub `ahmetb/kubectx` / `brew install kubectx` |
| `gh` | CLI officiel GitHub | Dépôt officiel `cli.github.com` (apt/dnf), `pacman -S github-cli`, `brew install gh` |
| `direnv` | Variables d'environnement automatiques par dossier | Paquet natif (apt/dnf/pacman) / `brew install direnv` |
| `shellcheck` | Linter bash/shell | Paquet natif (`ShellCheck` sur dnf) / `brew install shellcheck` |

- Deux façons de les obtenir : `./install.sh --with-extras` (installe les six immédiatement) ou individuellement plus tard en appelant la fonction correspondante.
- **`print_optional_tools_summary()`** tourne à la toute fin d'un run normal (pas en `--ssh-only`/`--vault-only`/`--cloud-only`) : elle boucle sur `OPTIONAL_TOOLS`, ne garde que ceux pour lesquels `have <commande>` échoue, et affiche leur nom + description + rappel de `--with-extras` — uniquement s'il en manque au moins un.

### 6. Génération de la clé SSH — `generate_ssh_key()` (install.sh:658-682)

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

### 7. Attente de la configuration Git — `test_ssh_auth()` / `wait_for_git_ssh()` (install.sh:769-794)

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

### 8. Configuration interactive AWS / GCP — `configure_aws()` / `configure_gcp()`

Pensées pour être relancées seules, une fois que tu as reçu tes accès (clé AWS, compte GCP) sans devoir tout réinstaller (`./install.sh --cloud-only`).

- **`configure_aws()`** : si `aws` n'est pas installé, skip avec un avertissement. Sinon, teste d'abord `aws sts get-caller-identity` — si ça répond, des identifiants valides existent déjà, skip. Sinon, demande confirmation (`ask_yes_no`) puis lance `aws configure` (le propre flux interactif d'AWS : Access Key ID, Secret Access Key, région par défaut, format de sortie), et revérifie l'identité juste après pour confirmer que ça marche.
- **`configure_gcp()`** : si `gcloud` n'est pas installé, skip. Sinon, teste `gcloud auth list --filter=status:ACTIVE` — un compte déjà actif fait skip. Sinon, demande confirmation puis lance `gcloud init` (connexion via navigateur + sélection du projet GCP).
- **`ask_yes_no()`** : petit helper (`read -rp "... [o/N] : "` + regex `^[oOyY]`) réutilisé pour ces deux confirmations.

Ni l'une ni l'autre ne stocke de secret dans le script : `aws configure` écrit dans `~/.aws/credentials`, `gcloud init` gère son propre stockage — comportement natif des CLI, pas géré par `install.sh`.

### 9. Configuration du coffre-fort Obsidian — `setup_obsidian_vault()` (install.sh:811-862)

Étapes dans l'ordre :

1. **Récupère l'URL du repo** (`$REPO_URL`, par défaut `git@github.com:Abla-Adem/sync-personal-doc.git`, ou prompt si explicitement vidé). Vide → étape entièrement sautée.
2. **Détecte le protocole** : si l'URL commence par `git@` ou `ssh://git@`, extrait le nom d'hôte par regex (`sed -E 's#^(git@|ssh://git@)([^:/]+).*#\2#'`) et appelle `wait_for_git_ssh` dessus. Sinon (HTTPS), avertit que Git pourra demander un identifiant/token.
3. **Détermine le dossier local** : `$VAULT_PATH` ou prompt, défaut `~/Documents/<nom-du-repo>` (nom extrait via `basename -s .git`).
4. **Clone ou met à jour** :
   ```bash
   if [[ -d "$VAULT_PATH/.git" ]]; then git -C "$VAULT_PATH" pull
   else git clone "$REPO_URL" "$VAULT_PATH"; fi
   ```
   → relancer le script sur un vault déjà cloné fait un simple `pull`, pas de re-clone.
5. **Marque le dossier comme vault Obsidian** : `mkdir -p "$VAULT_PATH/.obsidian"`. C'est la seule condition nécessaire pour qu'Obsidian reconnaisse un dossier comme coffre-fort — pas besoin de fichiers de config particuliers, Obsidian les crée à la première ouverture.
6. **Tente d'ouvrir Obsidian automatiquement** via l'URI officiel `obsidian://open?path=<chemin encodé>`, déclenché par `open` (macOS) ou `xdg-open` (Linux avec environnement graphique). La fonction `urlencode()` (install.sh:799-809) encode caractères par caractère (garde lettres/chiffres/`.~_/-`, encode le reste en `%XX`) pour gérer les chemins avec espaces ou accents.
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

**Configurer AWS/GCP une fois les accès reçus, sans rien réinstaller :**
```bash
./install.sh --cloud-only
```

**Tout faire sauf la configuration cloud (à faire plus tard) :**
```bash
./install.sh --no-cloud
```

**Tout installer, y compris les outils optionnels :**
```bash
./install.sh --with-extras
```

---

## Installation sur une nouvelle machine

La procédure est **la même** que sur la première machine, avec un point important : **une clé SSH par machine**. On ne recopie jamais une clé privée d'un PC à l'autre — chaque nouvelle machine génère la sienne, qu'on ajoute ensuite en tant que clé *supplémentaire* sur GitHub (les anciennes clés restent valides).

1. **Récupérer le script** sur la nouvelle machine (`git`/`curl` sont presque toujours déjà présents sur Linux/macOS) :
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Abla-Adem/dev-env-installer/main/install.sh -o install.sh
   chmod +x install.sh
   ```

2. **Lancer le script** — l'URL du coffre-fort est déjà en valeur par défaut (`git@github.com:Abla-Adem/sync-personal-doc.git`), donc un simple `./install.sh` suffit. Pour cloner un autre dépôt, surcharger `REPO_URL` :
   ```bash
   ./install.sh
   # ou pour un autre dépôt :
   REPO_URL="git@github.com:<user>/<autre-repo>.git" ./install.sh
   ```

3. Le script génère une **nouvelle** clé SSH (propre à cette machine, puisque `~/.ssh/id_ed25519` n'existe pas encore dessus) et l'affiche.

4. **Ajouter cette nouvelle clé publique** sur https://github.com/settings/ssh/new (elle s'ajoute à côté des clés des autres machines, sans rien remplacer).

5. Le script **attend automatiquement** que l'authentification SSH fonctionne (boucle `wait_for_git_ssh`), puis clone le coffre-fort et le configure pour Obsidian dès que c'est bon.

En résumé : même script, même flux, mais **une clé SSH distincte générée et ajoutée à GitHub pour chaque machine**.

---

## Limitations connues

- **WSL sans intégration GUI** : `xdg-open`/`open` absents → pas d'ouverture automatique d'Obsidian, seulement le clonage + la préparation du dossier `.obsidian`.
- **Arch Linux** : VS Code (build MS), Obsidian et parfois Terraform n'ont pas de paquet officiel dans les dépôts standards — le script recommande/utilise `yay`/`paru` (AUR) ou `flatpak` en fallback, mais ne les installe pas lui-même.
- **`test_ssh_auth`** dépend du texte retourné par le serveur SSH de l'hébergeur (`successfully authenticated` / `welcome to gitlab`) — un hébergeur Git auto-hébergé (Gitea, Bitbucket Server...) avec un message différent ne sera pas reconnu automatiquement ; utiliser `skip` dans ce cas.
- Le script suppose une **architecture x86_64 ou arm64/aarch64** pour AWS CLI ; toute autre architecture fait échouer `install_awscli` proprement (message d'erreur, pas de crash).
- **kubectl, yq, k9s, kubectx** récupèrent toujours la **dernière version stable/release** sur Linux (pas de version épinglée) — un run répété à des dates différentes peut installer des versions différentes.
- **Docker/groupe `docker`** : l'ajout au groupe ne prend effet qu'après déconnexion/reconnexion (ou reboot) ; tant que ce n'est pas fait, les commandes `docker` nécessitent `sudo` dans la même session.
- **Claude Code CLI** dépend de Node.js/npm : sur Linux, `npm install -g` avec `sudo` installe dans les répertoires système, ce qui n'est pas la pratique recommandée par npm à long terme (préférer un gestionnaire de version Node comme `nvm` pour éviter `sudo npm install -g` en usage courant), mais reste la méthode la plus simple pour un script d'installation automatisé.
- **`pip_install`** utilise `--user`, donc les binaires installés (`boto3` n'a pas de binaire CLI, mais d'autres libs pourraient en avoir) se retrouvent dans `~/.local/bin`, qu'il faut avoir dans son `PATH`.
