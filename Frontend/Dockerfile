# syntax=docker/dockerfile:1

##########
# Build stage: Vite production build
##########
FROM node:20-alpine AS build
WORKDIR /app

# VITE_* vars are baked into the bundle at build time
ARG VITE_API_URL
ARG VITE_SOCKET_URL
ARG VITE_BACKEND_V4_URL
ARG VITE_CRYPTO_PASSWORD
ARG VITE_PASSWORD_IV
ARG VITE_IS_ON_PREMISE=true
ARG VITE_SHOW_EMP_AI_ASSISTANT=false
ARG VITE_ADDON_SUPERADMIN_ORG_ID

ENV VITE_API_URL=$VITE_API_URL \
    VITE_SOCKET_URL=$VITE_SOCKET_URL \
    VITE_BACKEND_V4_URL=$VITE_BACKEND_V4_URL \
    VITE_CRYPTO_PASSWORD=$VITE_CRYPTO_PASSWORD \
    VITE_PASSWORD_IV=$VITE_PASSWORD_IV \
    VITE_IS_ON_PREMISE=$VITE_IS_ON_PREMISE \
    VITE_SHOW_EMP_AI_ASSISTANT=$VITE_SHOW_EMP_AI_ASSISTANT \
    VITE_ADDON_SUPERADMIN_ORG_ID=$VITE_ADDON_SUPERADMIN_ORG_ID

COPY package.json ./
# no lockfile in repo -> npm install; legacy-peer-deps for the mixed dep tree
RUN npm install --legacy-peer-deps
COPY . .
RUN npm run build

##########
# Runtime: nginx static
##########
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
