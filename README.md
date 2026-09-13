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

## [`ansible/`](./ansible) — parité complète, partiellement testée

Un playbook Ansible qui reprend **toutes** les fonctions du script bash (mêmes outils, mêmes flags via des variables `-e`). Installé sans `sudo` pour le tester : `ansible-lint` ne signale aucune erreur de module, et les modes `ssh_only`/`vault_only`/`extras_only` ont réellement tourné avec succès (`failed=0`) — trois vrais bugs ont été trouvés et corrigés au passage. Les chemins d'installation de paquets (`sudo` requis) n'ont en revanche pas pu être exécutés dans cet environnement.

→ **[Voir `ansible/README.md`](./ansible/README.md)** pour le détail de ce qui a été testé, les bugs trouvés, et la table de correspondance des flags.

## Lequel choisir ?

- **Tu veux que ça marche, maintenant** → `bash/install.sh`. Entièrement testé, bugs trouvés en cours de route corrigés.
- **Tu gères déjà un parc de machines avec Ansible, ou tu préfères ce style** → `ansible/`, partiellement testé (voir son README) — lance-le sur une machine sacrifiable avant de t'y fier pour de vrai.
