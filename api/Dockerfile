# Version précise de Node, pour savoir exactement ce qui tourne
FROM node:22.11-alpine

WORKDIR /app

# Dépendances d'abord (cache), fichiers donnés à l'utilisateur node
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev

# Puis le code
COPY --chown=node:node server.js db.js ./

# Le conteneur vérifie tout seul que l'API répond
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# On quitte root juste avant de lancer l'app
USER node

EXPOSE 3000

CMD ["node", "server.js"]
