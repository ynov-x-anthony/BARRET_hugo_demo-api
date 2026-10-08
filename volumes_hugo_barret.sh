#!/usr/bin/env bash
# Quête "Les volumes" : prouver que les données de PostgreSQL survivent
# à la suppression du conteneur grâce au named volume demo_pgdata.
# A lancer depuis la racine du repo demo-api (Git Bash / WSL sous Windows).

set -euo pipefail

# Git Bash convertit les chemins qui commencent par / (ex : /var/lib/...)
# en chemins Windows, ce qui casse les -v. Sans effet sous Linux / macOS.
export MSYS_NO_PATHCONV=1

# Chemin absolu du repo, au format que Docker Desktop comprend sous Windows
# (C:/Users/...) ; sous Linux / macOS, pwd -W n'existe pas et on prend pwd.
REPO_DIR="$(pwd -W 2>/dev/null || pwd)"

NET=demo_net
VOL=demo_pgdata

lancer_db() {
  docker run -d --name demo-db --network "$NET" \
    -v "$VOL":/var/lib/postgresql/data \
    -v "$REPO_DIR/db/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
    -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
    postgres:16-alpine > /dev/null
}

attendre_db() {
  # -h 127.0.0.1 : on teste en TCP. Au premier démarrage, l'image lance un
  # serveur temporaire (socket Unix seulement) pour jouer init.sql ; sans -h,
  # pg_isready dirait "prêt" trop tôt.
  echo -n "Attente de PostgreSQL"
  until docker exec demo-db pg_isready -U demo -h 127.0.0.1 > /dev/null 2>&1; do
    echo -n "."
    sleep 1
  done
  echo " OK"
}

attendre_api() {
  until curl -s localhost:8080/ready | grep -q READY; do sleep 1; done
}

echo "=== 1. Build de l'image de l'API"
docker build -q -t demo-api:1.0 ./api

echo "=== 2. Réseau et volume"
docker network create "$NET" > /dev/null
docker volume create "$VOL"

echo "=== 3. Base de données (1er démarrage, init.sql joué)"
lancer_db
attendre_db

echo "=== 4. API"
docker run -d --name api -p 8080:3000 --network "$NET" -e PGHOST=demo-db demo-api:1.0 > /dev/null
attendre_api

echo "=== 5. Ajout d'un produit"
# Le JSON passe par un pipe (--data-binary @-) et pas en argument : sous
# Windows, curl reçoit ses arguments en Windows-1252 et le "é" arrive cassé.
printf '%s' '{"name":"Casquette Démo","price_cents":1200}' |
  curl -s -X POST -H 'content-type: application/json' --data-binary @- localhost:8080/products
echo

echo "--- Produits AVANT suppression de la base :"
curl -s localhost:8080/products
echo

echo "=== 6. Suppression du conteneur demo-db puis recréation sur le même volume"
docker rm -f demo-db > /dev/null
lancer_db
attendre_db
docker restart api > /dev/null
attendre_api

echo "--- Produits APRÈS recréation de la base :"
curl -s localhost:8080/products
echo

echo "=== 7. Vérifications finales"
docker volume ls | grep "$VOL"
if curl -s localhost:8080/products | grep -q "Casquette Démo"; then
  echo "OK : « Casquette Démo » a survécu à la suppression du conteneur"
else
  echo "ECHEC : le produit a disparu"
fi

echo "=== 8. Nettoyage (le volume est gardé pour prouver la persistance)"
docker rm -f api demo-db > /dev/null
docker network rm "$NET" > /dev/null
echo "Conteneurs et réseau supprimés, volume $VOL conservé."
# Pour tout effacer, données comprises :
# docker volume rm demo_pgdata
