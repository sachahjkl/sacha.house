[English](README.md) | [Français](README.fr.md)

# sacha.house

Site personnel et blog basé sur le système de fichiers, construit avec Go, templ, Datastar et Tailwind CSS.

## Architecture

- `cmd/sacha-house/` contient le point d'entrée du serveur.
- `internal/app/` contient les routes HTTP et l'assemblage de l'application.
- `internal/web/` contient les composants templ et les fichiers `*_templ.go` générés.
- `internal/auth/`, `internal/blog/`, `internal/paste/` et `internal/projects/` contiennent les services métier.
- `internal/web/static/` contient les ressources statiques intégrées et le code Datastar pour le navigateur.
- `styles/app.css` est la source Tailwind.
- `data/blog/` contient les articles du blog et les médias.

Le binaire Go intègre les ressources statiques. Le serveur utilise les réponses SSE de Datastar pour la navigation et les interactions d'administration.

## Prérequis

Utilisez l'environnement de développement Nix pour obtenir Go, Bun, just, watchexec et Git :

```bash
nix develop
```

L'environnement installe les dépendances JavaScript depuis `bun.lock`. Il crée aussi `config.json` depuis l'exemple si nécessaire.

## Développement

Démarrez l'outil de surveillance du développement :

```bash
just dev
```

L'outil surveille les fichiers Go, templ, JavaScript et CSS. Il régénère les ressources, recompile et redémarre le serveur avec `-dev`.

Exécutez les tâches de génération séparément si nécessaire :

```bash
just templates
just css
```

## Compilation Et Tests

Compilez un binaire de version dans `bin/release/sacha.house` :

```bash
just build release
```

Exécutez tous les tests Go :

```bash
just test
```

Construisez le paquet Nix, l'artefact Linux statique ou l'image de conteneur :

```bash
nix build .#default
nix build .#linuxBinary
nix build .#dockerImage
```

Nix construit un binaire statique avec `CGO_ENABLED=0`. Il injecte la version et le hash du commit avec les options de l'éditeur de liens Go.

## Configuration

Définissez `CONFIG_PATH` avec le chemin de la configuration JSON. Le chemin par défaut est `config.json`.

Utilisez `config.example.json` comme configuration de base. Les champs importants sont :

- `ADMIN_PASSWORD_HASH` : hash Argon2id du mot de passe d'administration.
- `ADMIN_PASSWORD_PEPPER` : valeur secrète utilisée pour le hachage et la vérification du mot de passe.
- `GITHUB_BEARER_TOKEN` : jeton GitHub utilisé pour lire les dépôts publics, les métadonnées des projets et les commits de la branche par défaut.
- `WEBAUTHN_CREDENTIALS_FILE` : chemin accessible en écriture pour le stockage des passkeys.
- `WEBAUTHN_RP_ID` : identifiant de la partie de confiance WebAuthn.
- `WEBAUTHN_RP_ORIGINS` : origines WebAuthn autorisées.
- `PASTE_ENABLED` : active les textes GitHub Gist chiffrés sous `/admin/pastes`.
- `PASTE_SECRETS_FILE` : chemin du jeton Gist et du trousseau de clés de chiffrement.
- `PASTE_MAX_BODY_BYTES` : taille maximale du corps en clair, de 1024 à 1048576 octets.
- `PASTE_MAX_LIST_ITEMS` : nombre maximal de Gists examinés, de 1 à 500.

`PASSWORD_SALT` est obsolète. Renommez-le en `ADMIN_PASSWORD_PEPPER` avant le déploiement.

Le format du hash de mot de passe Go diffère du format Odin. Générez un nouveau hash avec `--hash-password` avant le déploiement.

Le conteneur utilise `/data` comme volume accessible en écriture. Il lit `/data/config.json` avec `CONFIG_PATH`.

### Secrets Des Textes Gist Chiffrés

Créez le fichier de secrets avant d'activer les textes. L'application ne génère jamais ce fichier.

```json
{
  "github_gist_token": "github_pat_or_classic_token",
  "active_key_id": "2026-07",
  "keys": [
    { "id": "2026-07", "key_hex": "64-lowercase-hex-characters" }
  ]
}
```

Générez une clé avec `openssl rand -hex 32`. Accordez au jeton GitHub les droits de lecture et d'écriture sur les Gists.

Les nouveaux textes et les modifications utilisent `active_key_id`. Ajoutez une nouvelle clé et redémarrez avant la rotation des textes existants.

Conservez les anciennes clés tant qu'un texte indique leur ID. Si vous perdez une clé, ses textes chiffrés deviennent irrécupérables.

Les Gists secrets GitHub ne sont pas répertoriés, mais ils ne sont pas privés. GitHub conserve le texte chiffré et peut conserver les anciennes révisions.

Conservez le fichier de secrets hors du dépôt et de l'image. Limitez son accès au compte du serveur avec le mode `0600`.

## Licence

MIT
