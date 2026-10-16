# syntax=docker/dockerfile:1
# Multi-target Dockerfile for all EmpMonitor backend services.
# Build context MUST be ./Backend because several services require the shared
# module at ../config/config.js via relative path (e.g. require('../../../config/config')).

##########
# Base image with shared config module
##########
FROM node:20-alpine AS base
WORKDIR /app
COPY config ./config

##########
# admin - main REST API (Express) :3000
##########
FROM base AS admin
COPY admin/package*.json ./admin/
RUN cd admin && npm install --omit=dev --legacy-peer-deps
COPY admin ./admin
WORKDIR /app/admin
EXPOSE 3000
CMD ["node", "adminApi.js"]

##########
# desktop - agent-facing REST API (Express) :3002
##########
FROM base AS desktop
COPY desktop/package*.json ./desktop/
RUN cd desktop && npm install --omit=dev --legacy-peer-deps
COPY desktop ./desktop
WORKDIR /app/desktop
EXPOSE 3002
CMD ["node", "desktopApi.js"]

##########
# cronjobs - scheduled jobs :3003
##########
FROM base AS cronjobs
COPY cronjobs/package*.json ./cronjobs/
RUN cd cronjobs && npm install --omit=dev --legacy-peer-deps
COPY cronjobs ./cronjobs
WORKDIR /app/cronjobs
EXPOSE 3003
CMD ["node", "cronService.js"]

##########
# productivity_report - reports API :3005
##########
FROM base AS productivity_report
COPY productivity_report/package*.json ./productivity_report/
RUN cd productivity_report && npm install --omit=dev --legacy-peer-deps
COPY productivity_report ./productivity_report
WORKDIR /app/productivity_report
EXPOSE 3005
CMD ["node", "productivity_report_api.js"]

##########
# web-socket-server - SockJS notifications :8080
##########
FROM base AS web-socket-server
COPY web-socket-server/package*.json ./web-socket-server/
RUN cd web-socket-server && npm install --omit=dev --legacy-peer-deps
COPY web-socket-server ./web-socket-server
WORKDIR /app/web-socket-server
EXPOSE 8080
CMD ["node", "server.js"]

##########
# remote_socket - remote/live agent socket
##########
FROM base AS remote_socket
COPY remote_socket/package*.json ./remote_socket/
RUN cd remote_socket && npm install --omit=dev --legacy-peer-deps
COPY remote_socket ./remote_socket
WORKDIR /app/remote_socket
EXPOSE 5003
CMD ["node", "server.js"]

##########
# realtime - realtime agent data via Redis pub/sub
##########
FROM base AS realtime
COPY realtime/package*.json ./realtime/
RUN cd realtime && npm install --omit=dev --legacy-peer-deps
COPY realtime ./realtime
WORKDIR /app/realtime
EXPOSE 5004
CMD ["node", "server.js"]

##########
# store-logs-api - NestJS ingestion API :3001 (build step required)
##########
FROM base AS store-logs-api
COPY store-logs-api/package*.json ./store-logs-api/
RUN cd store-logs-api && npm install --legacy-peer-deps
COPY store-logs-api ./store-logs-api
RUN cd store-logs-api && npm run build
WORKDIR /app/store-logs-api
EXPOSE 3001
CMD ["node", "dist/main.js"]

##########
# migrations - one-off DB init job
# Inherits store-logs-api image (has sequelize-cli + migrate-mongo + built dist)
# and adds the SQL-dump/mongo-seed migration service.
##########
FROM store-logs-api AS migrations
WORKDIR /app
COPY migrations/package*.json ./migrations/
RUN cd migrations && npm install --omit=dev --legacy-peer-deps
COPY migrations ./migrations
COPY docker/migrate.sh ./migrate.sh
RUN chmod +x ./migrate.sh
CMD ["sh", "./migrate.sh"]
