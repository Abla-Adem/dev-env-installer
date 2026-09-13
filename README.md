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

## [`ansible/`](./ansible) — démo, pour comparaison

Un playbook Ansible qui réécrit **une partie** du script bash en version déclarative, pour montrer à quoi ça ressemblerait avec un outil différent. **N'a pas été exécuté en conditions réelles** et ne couvre pas tous les outils.

→ **[Voir `ansible/README.md`](./ansible/README.md)** pour le détail et un tableau comparatif bash vs Ansible.

## Lequel choisir ?

- **Tu veux juste que ça marche, maintenant, sans rien installer d'autre au préalable** → `bash/install.sh`.
- **Tu es curieux de voir comment ce serait en Ansible, ou tu gères déjà un parc de machines avec Ansible** → regarde `ansible/`, mais attends-toi à devoir le compléter/tester avant de t'en servir pour de vrai.
