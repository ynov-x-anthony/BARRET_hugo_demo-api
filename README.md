# demo-api – Hugo Barret

Fil rouge des quêtes Docker : une mini-API « catalogue » (Node + Express) avec une base PostgreSQL, que je fais évoluer quête après quête. Le starter vient de [ynov-x-anthony/docker-demo-api-starter](https://github.com/ynov-x-anthony/docker-demo-api-starter).

## Lancer la stack (Compose)

### Prérequis

- Docker Desktop (ou Docker Engine) avec **Compose v2** : `docker compose version` doit répondre.
- Ports **8080** (API) et **8081** (Adminer) libres, ou à changer dans `.env`.

### Démarrage

```bash
# 1. Les variables (utilisateur, base, ports)
cp .env.example .env

# 2. Le mot de passe de la base, en secret (dossier ignoré par Git)
mkdir -p secrets
echo "un-mot-de-passe-solide" > secrets/db_password.txt

# 3. Build + démarrage
docker compose up -d --build
```

Sous PowerShell, l'étape 2 donne : `New-Item -ItemType Directory -Force secrets; Set-Content secrets\db_password.txt "un-mot-de-passe-solide" -NoNewline`.

### URLs

| Service | URL |
|---|---|
| API | http://localhost:8080 (`/health`, `/ready`, `/products`) |
| Adminer | http://localhost:8081 : système **PostgreSQL**, serveur `db`, utilisateur `demo`, mot de passe = contenu de `secrets/db_password.txt`, base `demo` |

### Ce que j'ai testé

Commande : `docker compose up -d --build`, puis :

```
$ docker compose ps
NAME                 IMAGE                COMMAND                  SERVICE   STATUS                    PORTS
demo-api-adminer-1   adminer:4            "entrypoint.sh docke…"   adminer   Up 22 seconds             0.0.0.0:8081->8080/tcp
demo-api-api-1       demo-api-api         "docker-entrypoint.s…"   api       Up 16 seconds (healthy)   0.0.0.0:8080->3000/tcp
demo-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        Up 22 seconds (healthy)   5432/tcp

$ curl -s localhost:8080/products
[{"id":3,"name":"T-shirt conteneur",...},{"id":2,"name":"Mug Docker",...},{"id":1,"name":"Sticker Demo",...}]

$ curl -s -X POST -H 'content-type: application/json' -d '{"name":"Gourde","price_cents":900}' localhost:8080/products
{"id":4,"name":"Gourde","price_cents":900,"created_at":"2026-10-09T08:07:20.294Z"}

$ docker compose down && docker compose up -d
$ curl -s localhost:8080/products
[{"id":4,"name":"Gourde",...},{"id":3,"name":"T-shirt conteneur",...},...]
```

La Gourde survit au `down` / `up` : les données sont dans le volume `pgdata`, que `down` ne supprime pas.

### Arrêter / repartir de zéro

```bash
docker compose down      # supprime conteneurs + réseaux, GARDE les données
docker compose down -v   # supprime aussi le volume pgdata : base vide, init.sql rejoué au prochain up
```

## Comment c'est construit

- **4 services** : `api` (buildée depuis `api/Dockerfile.multi`), `notifier` (buildé depuis `./notifier`), `db` (`postgres:16-alpine`), `adminer` (`adminer:4`).
- **Réseaux** : `front` (api) et `back` (api, notifier, db, adminer). Ni la base ni `notifier` n'ont de `ports:` : ils ne sont joignables que depuis `back`.
- **notifier** : un second service métier, avec son propre `package.json`, son propre Dockerfile (multi-étapes, non-root, HEALTHCHECK) et sa propre image. Après chaque `POST /products`, l'API l'appelle sur `http://notifier:4000/notify`, en best-effort : l'appel part après la réponse 201, avec un timeout de 2 s, et une panne de notifier ne fait jamais échouer la création du produit (juste un `notify failed` dans les logs de l'API).
- **Ordre de démarrage** : `db` a un healthcheck `pg_isready`, et `api` attend `condition: service_healthy`. Le healthcheck teste en TCP (`-h 127.0.0.1`) pour ne pas valider le serveur temporaire que postgres lance pendant `init.sql`.
- **Variables** : `.env` sert à l'interpolation `${...}` dans `compose.yml`. Il n'est pas commité, `.env.example` l'est.
- **Mot de passe en secret** : `secrets/db_password.txt` est monté dans `/run/secrets/db_password`.
  - Postgres le lit via `POSTGRES_PASSWORD_FILE`.
  - L'API (dont `db.js` attend `PGPASSWORD`) le lit au démarrage : `command: sh -c 'PGPASSWORD="$(cat /run/secrets/db_password)" exec node server.js'`. Le `exec` garde `node` en PID 1.
  - Résultat : le mot de passe n'apparaît pas dans `docker inspect`.

## CI/CD (`.github/workflows/ci.yml`)

- **Job `image`, en matrice `api` / `notifier`** : chaque service est buildé, scanné par Trivy (HIGH/CRITICAL, `ignore-unfixed`) et, sur un tag `v*`, publié sur `ghcr.io/ynov-x-anthony/barret_hugo_demo-api/<service>:<tag>`. La gate Trivy est bloquante sur les tags. On pousse l'image qui vient d'être scannée, pas un nouveau build.
- **Job `deploy`** (après les deux jobs `image`, seulement sur les tags `v*`) : `docker compose pull` des images publiées puis `docker compose up -d --no-build`, puis vérification de bout en bout (`/ready`, un `POST /products`, et la notification dans les logs de notifier).
- **Le déploiement est simulé sur le runner GitHub** (pas de serveur disponible) : même mécanique qu'en SSH sur une VM, où `.env` et le secret existeraient déjà. Ici le job les crée, avec un mot de passe aléatoire.
- `compose.yml` nomme les images `${IMAGE_PREFIX}/<service>:${IMAGE_TAG}` : `demo-api/<service>:local` en local, l'image GHCR du tag au déploiement.

Pour déployer une version : `git tag v1.5.1 && git push origin v1.5.1`.

## Les autres fichiers des quêtes

| Fichier | Quête |
|---|---|
| `api/Dockerfile` | Le Dockerfile, puis Dockerfile et sécurité (non-root, HEALTHCHECK) |
| `api/Dockerfile.multi`, `api/Dockerfile.naive` | Builds multi-étapes et secrets |
| `volumes_hugo_barret.sh` | Les volumes |
| `reseaux_hugo_barret.sh` | Les réseaux |
| `compose.yml`, `.env.example` | Compose |
| `.github/workflows/ci.yml`, `scans/` | Analyse de vulnérabilité avec Trivy |
| `notifier/`, `compose.yml`, `ci.yml` (matrice + deploy) | Microservices et déploiement continu |

Les routes de l'API : `GET /`, `/version`, `/health` (liveness), `/ready` (teste la base), `GET /products`, `POST /products` avec `{ "name": "...", "price_cents": 1234 }`.
