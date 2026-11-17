FROM node:20-alpine

WORKDIR /app

# Dependencies (wird gecached wenn package.json sich nicht ändert)
COPY package*.json ./
RUN npm install

# Code (wird bei jeder Änderung überschrieben durch Volume)
COPY . .

EXPOSE 3000

# Produktionsverhalten: ohne TOTP_ENCRYPTION_KEY/BACKUP_CODE_PEPPER bricht der Start ab (gewollt).
# docker-compose startet derzeit nur db + mailhog; Backend lokal via `npm run dev` (NODE_ENV=development).
CMD ["npm", "start"]