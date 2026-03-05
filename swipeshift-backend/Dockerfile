FROM node:20-alpine

WORKDIR /app

# Dependencies (wird gecached wenn package.json sich nicht ändert)
COPY package*.json ./
RUN npm install

# Code (wird bei jeder Änderung überschrieben durch Volume)
COPY . .

EXPOSE 3000

# Wird von docker-compose überschrieben
CMD ["npm", "start"]