# Ansible — parité complète avec `bash/install.sh`

[← Retour au README principal](../README.md) — l'option testée et recommandée reste [`bash/`](../bash).

Ce dossier reprend **toutes** les fonctions de `bash/install.sh` : VS Code, Obsidian, Terraform, AWS CLI + boto3, gcloud + SDK Python GCP, Docker, kubectl, Helm, jq, Claude Code CLI, les 6 outils optionnels (`yq`, `k9s`, `kubectx`, `gh`, `direnv`, `shellcheck`), la génération de clé SSH, l'identité git, la configuration AWS/GCP, et le clonage/configuration du coffre-fort Obsidian.

**✅ Testé en conditions réelles, run complet par défaut réussi.** `ansible` a été installé sans `sudo` (`pip install --user --break-system-packages`, même technique que le fallback PEP 668 du script bash). Avec `sudo` fourni par l'utilisateur dans un vrai terminal (obligatoire, cf. [Limites](#limites-réelles-de-cette-implémentation)) :

- `ansible-lint` sur l'ensemble du playbook : 0 erreur de module/paramètre invalide (uniquement des nitpicks de style — noms de tâches, casse).
- `-e ssh_only=true`, `-e vault_only=true`, `-e extras_only=true -e extras_only_list=gh,xyz` : exécutions réelles réussies (`failed=0`), voir détails plus bas.
- Les 7 combinaisons de flags vérifiées une par une : la traduction en `skip_install`/`skip_ssh`/`skip_cloud`/`skip_vault` correspond exactement à la logique bash.
- **Run par défaut complet** (`ansible-playbook playbook.yml --ask-become-pass`, aucun flag) : `ok=81, changed=7, failed=0`. Obsidian, Docker, `unzip`, AWS CLI, Helm et jq **réellement installés** sur une vraie machine (VS Code, Terraform et gcloud étaient déjà présents, correctement détectés et skippés) ; utilisateur ajouté au groupe `docker` ; SDK Python AWS/GCP installés ; configuration AWS proposée puis déclinée proprement ; gcloud déjà authentifié détecté ; vault cloné/à jour ; résumé des outils optionnels manquants affiché correctement.

Cinq bugs réels ont été trouvés et corrigés grâce à ces tests (voir plus bas), dont deux découverts uniquement lors du run complet avec `sudo` fourni par l'utilisateur.

**Ce qui reste non testé** : `--with-extras` (installation réelle de `yq`/`k9s`/`kubectx`/`direnv`/`shellcheck` via Ansible — leur logique équivalente a été validée côté bash, mais pas via les tâches Ansible elles-mêmes) et `cloud_aws.yml`/`cloud_gcp.yml` avec de vrais identifiants renseignés.

## Installation et lancement

```bash
pip install ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbook.yml --ask-become-pass
```

## Correspondance flags bash ↔ variables Ansible

| bash/install.sh | Ansible (`-e ...`) |
|---|---|
| `./install.sh` | `ansible-playbook playbook.yml --ask-become-pass` |
| `./install.sh --ssh-only` | `-e ssh_only=true` |
| `./install.sh --vault-only` | `-e vault_only=true` |
| `./install.sh --cloud-only` | `-e cloud_only=true` |
| `./install.sh --no-vault` | `-e no_vault=true` |
| `./install.sh --no-cloud` | `-e no_cloud=true` |
| `./install.sh --with-extras` | `-e with_extras=true` |
| `./install.sh --extras-only` | `-e extras_only=true` (un prompt `pause` demande les noms, séparés par des virgules, ou `all`) |
| `./install.sh --extras-only=yq,gh` | `-e extras_only=true -e extras_only_list=yq,gh` |
| `SSH_KEY_COMMENT=...` | `-e ssh_key_comment=...` (dans `group_vars/all.yml` ou en `-e`) |
| `REPO_URL=...` | `-e repo_url=...` |
| `VAULT_PATH=...` | `-e vault_path=...` |
| `GIT_USER_NAME=...` / `GIT_USER_EMAIL=...` | Réponds directement aux prompts `pause` de `git_identity.yml`, ou pré-configure `git config --global` avant de lancer |

Ces flags de haut niveau (`ssh_only`, `vault_only`, `cloud_only`, `extras_only`, `no_vault`, `no_cloud`) sont traduits en quatre booléens `skip_install`/`skip_ssh`/`skip_cloud`/`skip_vault` dans les `pre_tasks` de `playbook.yml`, exactement comme le `case "$arg"` en tête de `bash/install.sh`.

## Organisation des fichiers

```
group_vars/all.yml   → équivalent des variables de config + OPTIONAL_TOOLS du script bash
playbook.yml          → orchestrateur (équivalent de main())
tasks/
  ensure_brew.yml         → ensure_brew()
  vscode.yml              → install_vscode()
  obsidian.yml            → install_obsidian()
  terraform.yml           → install_terraform()
  awscli.yml              → install_awscli()
  ensure_pip3.yml         → ensure_pip3() (inclus par aws_sdk.yml et gcp_sdk.yml)
  aws_sdk.yml             → install_aws_sdk() (boto3)
  gcloud.yml              → install_gcloud()
  gcp_sdk.yml             → install_gcp_sdk()
  docker.yml              → install_docker()
  kubectl.yml             → install_kubectl()
  helm.yml                → install_helm()
  jq.yml                  → install_jq()
  claude_code.yml         → ensure_npm() + install_claude_code()
  optional_tool_install.yml → install_optional_tool() + install_yq/k9s/kubectx/gh/direnv/shellcheck()
  extras_only.yml         → select_extras_interactive() + run_extras_only()
  optional_tools_summary.yml → print_optional_tools_summary()
  ssh_key.yml             → generate_ssh_key()
  git_identity.yml        → configure_git_identity()
  cloud_aws.yml           → configure_aws()
  cloud_gcp.yml           → configure_gcp()
  vault.yml               → setup_obsidian_vault() + urlencode()
  wait_for_git_ssh.yml    → test_ssh_auth() + wait_for_git_ssh()
```

Chaque fichier porte en commentaire la fonction bash dont il est l'équivalent — pour comparer, ouvre les deux côte à côte.

## Différences de fond (pas des oublis, des limites réelles d'Ansible)

### `aws configure` et `gcloud init` ne peuvent pas être pilotés tels quels

Ansible exécute les modules `command`/`shell` avec **stdin fermé**, même en connexion locale — un assistant interactif qui attend une frappe clavier (`aws configure`, `gcloud init`) ne peut donc pas recevoir de saisie par ce biais, contrairement au script bash qui les lance directement dans le terminal de l'utilisateur.

- **`cloud_aws.yml`** contourne le problème en écrivant **directement** `~/.aws/credentials` et `~/.aws/config` via des prompts `pause` (Access Key ID, Secret Access Key masqué avec `echo: false`, région) — fonctionnellement équivalent, et plus idiomatique en Ansible (déclaratif) que piloter un assistant CLI.
- **`cloud_gcp.yml`** ne peut pas faire la même chose : `gcloud init` déclenche un flux OAuth navigateur multi-étapes (ouvrir une URL, coller un code, choisir un projet) qu'aucun templating de fichier ne remplace. La tâche se contente donc de vérifier l'état et d'inviter à lancer `gcloud init` **toi-même**, dans un vrai terminal, après le playbook.

### Le menu numéroté de `--extras-only` devient une liste de noms

Le script bash affiche un menu `1) yq  2) k9s  3) kubectx...` et accepte `2,4`. Ansible n'a pas de primitive de menu numéroté interactif — `extras_only.yml` utilise un `pause` qui demande directement les **noms** (`yq,gh` ou `all`), ce qui revient au même fonctionnellement mais change la saisie attendue.

### La boucle d'attente SSH interactive n'a pas de primitive native

`wait_for_git_ssh.yml` reconstruit le pattern "teste, si ça échoue attends une action humaine, puis retente" de bash **par un `include_tasks` récursif** (le fichier s'inclut lui-même) combiné à `pause` — Ansible n'offre rien de plus direct pour ce cas précis (`until`/`retries` fait du polling automatique sans pause interactive, ce qui n'est pas le même comportement).

## Bugs trouvés (et corrigés) en testant réellement

Aucun n'était visible à la simple lecture — la valeur d'un test réel par rapport à une relecture :

1. **`ansible.builtin.unarchive` n'a pas de paramètre `include`** (trouvé en relisant, avant même de tester) — utilisé pour n'extraire qu'un seul binaire d'une archive tar.gz (k9s, kubectx). Corrigé en extrayant dans `/tmp` puis en copiant le binaire voulu vers `/usr/local/bin`.
2. **`ansible.builtin.apt_key` est déprécié** (trouvé en relisant) — remplacé par le téléchargement + `gpg --dearmor` vers un keyring, avec `signed-by=` dans la ligne `deb`, comme le fait déjà le script bash.
3. **Le `Gathering Facts` implicite héritait de `become: true`** (trouvé en exécutant `-e ssh_only=true` : `sudo: a password is required` dès la première tâche, alors que ce mode ne devrait avoir besoin d'aucun privilège). Corrigé avec `gather_facts: false` + une tâche `ansible.builtin.setup` explicite en `become: false`.
4. **`ssh -T ... | grep -q` échoue à tort** (trouvé en exécutant `-e vault_only=true` : la boucle d'attente SSH bouclait indéfiniment alors que l'authentification GitHub fonctionne bel et bien sur cette machine). `grep -q` sort dès son premier match, le `SIGPIPE` envoyé à `ssh` remonte comme un échec via `pipefail`. Corrigé en capturant la sortie dans une variable avant de la grepper — exactement ce que fait déjà `test_ssh_auth()` en bash, qui n'a jamais eu ce problème.
5. **`obsidian.yml` cherchait un `.deb`/`.rpm` dans `/releases/latest`**, qui peut pointer sur une release mobile-only sans installeur desktop (vérifié en conditions réelles côté script bash : c'était le cas au moment du test — même bug, même cause, deux implémentations). Corrigé pour chercher dans les releases récentes (`/releases?per_page=10`) via `map(attribute='assets') | flatten | selectattr(...)`, validé avec un test Ansible isolé qui retourne bien la bonne URL.
6. **`obsidian.yml` : le check `which snap`/`which flatpak` (en boucle) n'avait pas `become: false`**, trouvé lors du **run complet réel avec vrai `sudo`** : ce `become` superflu dans une tâche en `loop` a fait planter tout le run avec `Duplicate become password prompt encountered waiting for become success`. Corrigé en ajoutant `become: false` (ce check ne nécessite aucun privilège).
7. **`ansible.builtin.unarchive` échoue bel et bien sans `unzip`/`zipinfo` installé** — contrairement à ce qu'affirmait une version précédente de ce README. Trouvé lors du même run complet réel : `awscli.yml` plantait avec *"Unable to find required 'unzip' or 'unzip' binary in the path"*. Ajout d'un `ensure_unzip.yml` (même patron que `ensure_pip3.yml`), inclus par `awscli.yml` et le fallback Arch de `terraform.yml`.
8. **`cloud_aws.yml` n'affichait aucun message quand l'utilisateur décline la configuration AWS** (trouvé en observant le run complet réel — l'utilisateur a répondu "non" et rien ne s'est affiché). Ajouté un message "Configuration AWS ignorée. Relance plus tard avec: -e cloud_only=true", comme le fait `configure_aws()` en bash.

## Ce qui est réellement plus simple qu'en bash

- **Idempotence native** : `ansible.builtin.package`, `apt`, `dnf`, `pacman`, `homebrew` savent déjà s'il y a un changement à faire — pas besoin du `if have X; then return; fi` répété dans chaque fonction bash (on garde quand même une vérification `which` explicite dans ce playbook, pour rester lisible en parallèle du script bash).
- **`ansible.builtin.git`** gère nativement clone-ou-pull en une seule tâche (`update: true`), alors que `setup_obsidian_vault()` en bash teste `[[ -d "$VAULT_PATH/.git" ]]` à la main.
- **`community.crypto.openssh_keypair`** ne régénère jamais une clé existante, sans code de vérification manuel.
- **Un dry-run gratuit** : `ansible-playbook playbook.yml --check --ask-become-pass` (avec les limites habituelles du mode check sur les tâches `shell`/`command`, qui ne sont jamais simulées).

## Limites réelles de cette implémentation

- **`--with-extras` (installation réelle des 6 outils optionnels via Ansible) et `cloud_aws.yml`/`cloud_gcp.yml` avec de vrais identifiants** n'ont pas encore été exercés — voir l'avertissement en haut. Huit bugs réels ayant déjà été trouvés en testant le reste, il n'est pas exclu qu'il en reste ici aussi.
- **`ansible.builtin.package` ne gère pas Homebrew** : chaque tâche multi-OS a une branche `homebrew`/`homebrew_cask` dédiée à côté du module générique pour Linux.
- Suppose une architecture `x86_64`/`aarch64`/`arm64`, comme le script bash.
- `community.general.flatpak` suppose que le remote `flathub` est déjà configuré sur la machine (le script bash fait la même hypothèse).
- Les modules `ansible.builtin.dnf`/`yum_repository`/`rpm_key` couvrent Fedora/RHEL récents ; pas testés sur d'anciennes versions.
