# Démo Ansible

[← Retour au README principal](../README.md) — pour l'option recommandée, voir [`bash/`](../bash).

Ce dossier montre à quoi ressemblerait **une partie** de `install.sh` (dans [`bash/`](../bash)) réécrite en Ansible — pas une réécriture complète (voir [Limites](#limites-de-cette-démo)).

## Lancer

```bash
pip install ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass
```

`--ask-become-pass` demande ton mot de passe sudo une seule fois au début, contrairement au script bash où chaque `$SUDO apt-get ...` peut redemander.

## Différences concrètes avec `install.sh`

| | `install.sh` (bash) | `playbook.yml` (Ansible) |
|---|---|---|
| Détection OS | `uname -s` + `have apt-get/dnf/pacman` à la main | `ansible_facts['os_family']` fourni automatiquement |
| Installer un paquet simple (jq, direnv...) | `case "$PKG_MGR" in apt) ...; dnf) ...; pacman) ...; esac` (4 branches) | `ansible.builtin.package: name: jq` (1 tâche, le module choisit apt/dnf/pacman tout seul — **sauf macOS**, voir plus bas) |
| Idempotence | Manuelle : `if have code; then ... return; fi` dans chaque fonction | Native : chaque module Ansible sait déjà s'il y a un changement à faire ou non |
| Clé SSH | `ssh-keygen` + vérif manuelle du fichier existant | `community.crypto.openssh_keypair` (idempotent nativement) |
| Config git | `git config --global ...` appelé directement | `community.general.git_config` (déclaratif) |
| Sortie/logs | `log()`/`warn()`/`err()` maison | Sortie standard d'Ansible (`ok`/`changed`/`failed` par tâche), + `--check` pour un dry-run gratuit |

## Limites de cette démo

- **Couverture partielle** : seuls jq/direnv/shellcheck, VS Code, Docker (cask macOS), la clé SSH, l'identité git et le clone du vault sont représentés. Obsidian (hors macOS), Terraform, AWS CLI, gcloud, kubectl, Helm, boto3, le SDK GCP, `--extras-only`, etc. ne sont pas repris — ils suivraient le même principe mais alourdiraient l'exemple.
- **`ansible.builtin.package` ne couvre pas macOS** : ce module générique sait choisir entre apt/dnf/pacman/yum tout seul, mais pas Homebrew (qui n'est pas un gestionnaire "système"). Il faut donc explicitement `community.general.homebrew`/`homebrew_cask` pour macOS, comme dans le playbook.
- **Pas d'attente interactive** : le script bash a `wait_for_git_ssh()` qui bloque et boucle tant que la clé SSH n'est pas ajoutée sur GitHub. Ansible n'a pas d'équivalent naturel à ce pattern "attends une action humaine puis retente" — il faudrait un module `pause` + une boucle `until`, moins naturel qu'en bash.
- **Dépendance de départ** : il faut Python + Ansible déjà installés avant de pouvoir lancer quoi que ce soit, alors que `install.sh` ne dépend que de bash (déjà présent partout).
- **Un run réel demanderait des credentials** (`--ask-become-pass`, clé SSH GitHub déjà configurée pour le clone) — cette démo n'a pas été exécutée.
