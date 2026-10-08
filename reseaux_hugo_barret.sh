#!/usr/bin/env bash
# Quête "Les réseaux" : la base n'est joignable que par l'API.
#   demo_front : demo-api (+ le conteneur de test)
#   demo_back  : demo-api + demo-db
# A lancer depuis la racine du repo demo-api (Git Bash / WSL sous Windows).

set -euo pipefail

# Git Bash : pas de conversion des chemins /... en chemins Windows
export MSYS_NO_PATHCONV=1
REPO_DIR="$(pwd -W 2>/dev/null || pwd)"

# Nettoyage à la fin, même si une commande échoue en route
nettoyer() {
  echo "=== Nettoyage"
  docker rm -f demo-api demo-db > /dev/null 2>&1 || true
  docker network rm demo_front demo_back > /dev/null 2>&1 || true
  echo "Conteneurs et réseaux supprimés."
}
trap nettoyer EXIT

afficher_ips() {
  docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}  {{$net}} : {{$conf.IPAddress}}{{"\n"}}{{end}}' "$1"
}

echo "=== 1. Build de l'image"
docker build -q -t demo-api:1.0 ./api

echo "=== 2. Réseaux"
docker network create demo_front > /dev/null
docker network create demo_back > /dev/null
docker network ls --filter name=demo_

echo "=== 3. Base : demo_back uniquement, aucun port publié"
docker run -d --name demo-db --network demo_back \
  -v "$REPO_DIR/db/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
  -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
  postgres:16-alpine > /dev/null
echo -n "Attente de PostgreSQL"
until docker exec demo-db pg_isready -U demo -h 127.0.0.1 > /dev/null 2>&1; do
  echo -n "."
  sleep 1
done
echo " OK"

echo "=== 4. API : demo_front + demo_back, publiée sur 8080"
docker run -d --name demo-api --network demo_front -p 8080:3000 -e PGHOST=demo-db demo-api:1.0 > /dev/null
docker network connect demo_back demo-api
until curl -s localhost:8080/ready | grep -q READY; do sleep 1; done
docker ps --filter name=demo- --format 'table {{.Names}}\t{{.Ports}}'

echo
echo "=== 5. demo-api résout demo-db par son nom"
docker exec demo-api getent hosts demo-db

echo
echo "=== 6. Un conteneur tiers sur demo_front seulement ne joint PAS demo-db"
echo "--- par son nom :"
if docker run --rm --network demo_front alpine:3.20 nc -zv -w 3 demo-db 5432; then
  echo "PROBLÈME : demo-db est joignable depuis demo_front"
else
  echo "-> échec attendu : le nom demo-db n'existe pas sur demo_front"
fi
# Le nom ne se résout pas, mais est-ce juste le DNS ? On essaie l'IP directement.
DB_IP="$(docker inspect -f '{{.NetworkSettings.Networks.demo_back.IPAddress}}' demo-db)"
echo "--- par son IP ($DB_IP) :"
if docker run --rm --network demo_front alpine:3.20 nc -zv -w 3 "$DB_IP" 5432; then
  echo "PROBLÈME : demo-db est joignable par IP depuis demo_front"
else
  echo "-> échec attendu : aucun réseau commun, demo-db est injoignable même par IP"
fi

echo
echo "=== 7. Adresses IPv4 par réseau"
echo "demo-db :"
afficher_ips demo-db
echo "demo-api :"
afficher_ips demo-api

echo "=== 8. L'API répond (produits de init.sql)"
curl -s localhost:8080/products
echo
