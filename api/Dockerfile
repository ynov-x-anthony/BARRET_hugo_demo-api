# Image de base Node légère, version épinglée
FROM node:22-alpine

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que
# package.json / package-lock.json ne bougent pas
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Puis le code, qui change plus souvent
COPY server.js db.js ./

EXPOSE 3000

CMD ["node", "server.js"]
