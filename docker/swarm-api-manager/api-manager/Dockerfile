FROM node:20-alpine
RUN apk add --no-cache docker-cli
WORKDIR /app
RUN npm init -y && npm install express
COPY server.js .
EXPOSE 3000
CMD ["node", "server.js"]
