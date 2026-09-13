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

## [`ansible/`](./ansible) — parité complète, testée avec un run réel complet

Un playbook Ansible qui reprend **toutes** les fonctions du script bash (mêmes outils, mêmes flags via des variables `-e`). Le run par défaut complet (avec un vrai `sudo`, fourni par l'utilisateur dans un terminal séparé) a été exécuté de bout en bout avec succès (`failed=0`) : Obsidian, Docker, `unzip`, AWS CLI, Helm et jq réellement installés. Huit bugs réels ont été trouvés et corrigés au fil de ces tests. `--with-extras` et la configuration cloud avec de vrais identifiants restent les seuls chemins non exercés.

→ **[Voir `ansible/README.md`](./ansible/README.md)** pour le détail de ce qui a été testé, les bugs trouvés, et la table de correspondance des flags.

## Lequel choisir ?

Les deux ont maintenant tourné pour de vrai avec succès sur la même machine. `bash/install.sh` reste le choix par défaut (zéro dépendance, plus simple à lire/modifier) ; `ansible/` convient si tu gères déjà un parc de machines avec Ansible ou préfères ce style déclaratif.
