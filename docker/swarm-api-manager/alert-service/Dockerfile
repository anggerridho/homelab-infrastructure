FROM node:20-alpine
WORKDIR /app
RUN npm init -y && npm install express node-telegram-bot-api@0.66.0
COPY server.js .
EXPOSE 3001
CMD ["node", "server.js"]
