# dev-env-installer

Provisionne un poste de dev complet (VS Code, Obsidian, Terraform, AWS CLI, gcloud, Docker, kubectl, Helm, jq, Claude Code CLI, SDK Python...), génère une clé SSH, configure git, et clone/configure un coffre-fort Obsidian.

Deux implémentations, au choix :

## [`bash/`](./bash) — le script à utiliser (recommandé)

Un script `install.sh` autonome, sans dépendance (juste bash). C'est celui qui a été testé et qui fonctionne réellement.

→ **[Voir `bash/README.md`](./bash/README.md)** pour la doc complète (flags, variables, détail de chaque étape).

```bash
curl -fsSL https://raw.githubusercontent.com/Abla-Adem/dev-env-installer/main/bash/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

## [`ansible/`](./ansible) — parité complète, non testée

Un playbook Ansible qui reprend **toutes** les fonctions du script bash (mêmes outils, mêmes flags via des variables `-e`). **N'a jamais été exécuté** (pas d'accès root disponible pour installer Ansible dans l'environnement où il a été écrit) — relu à la main, modules vérifiés un par un, mais aucune garantie qu'il tourne sans accroc du premier coup.

→ **[Voir `ansible/README.md`](./ansible/README.md)** pour la table de correspondance des flags et les quelques différences de fond (assistants interactifs AWS/GCP notamment).

## Lequel choisir ?

- **Tu veux que ça marche, maintenant** → `bash/install.sh`. C'est celui qui a réellement tourné, dont les bugs trouvés en testant ont été corrigés.
- **Tu gères déjà un parc de machines avec Ansible, ou tu préfères ce style** → `ansible/`, mais lance-le d'abord sur une machine sacrifiable et relis `ansible/README.md` avant de t'y fier.
