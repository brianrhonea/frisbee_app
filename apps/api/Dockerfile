# syntax=docker/dockerfile:1.7
#
# The Stall 10 API container (Cloud Run). Build from the repo root, which is
# the build context (see /.dockerignore):
#
#   docker build -f apps/api/Dockerfile -t stall10-api .                  # API (default)
#   docker build -f apps/api/Dockerfile --target media -t stall10-media . # + ffmpeg
#
# Stages:
#   build    installs the workspace, builds @stall10/shared and @stall10/api,
#            and `pnpm deploy`s the API with production dependencies only.
#   runtime  slim Node with just that output, as the non-root `node` user.
#   media    runtime + ffmpeg, for the video-transcode Cloud Run job
#            (ARCHITECTURE.md §6). Same code; the job overrides the command
#            (e.g. `node dist/transcode.js` once it exists).
#   api      the default target: runtime, serving HTTP on $PORT.

ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS build
ENV CI=true PNPM_HOME=/pnpm PATH=/pnpm:$PATH
# Same pnpm as package.json's packageManager.
RUN npm install -g pnpm@11.13.1 && pnpm config set store-dir /pnpm/store
WORKDIR /repo

# Manifests first, so the dependency layer is cached until they change.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json apps/api/
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile --filter "@stall10/api..."

COPY packages/shared packages/shared
COPY apps/api apps/api
RUN pnpm --filter @stall10/shared build \
 && pnpm --filter @stall10/api build
# --legacy: the workspace doesn't use injected workspace packages.
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm --filter @stall10/api deploy --prod --legacy /out

FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --from=build --chown=node:node /out/package.json ./
COPY --from=build --chown=node:node /out/node_modules ./node_modules
COPY --from=build --chown=node:node /out/dist ./dist
USER node
EXPOSE 8080
# Exec form: node is PID 1 and gets Cloud Run's SIGTERM (src/shutdown.ts).
CMD ["node", "dist/server.js"]

FROM runtime AS media
USER root
# Debian's ffmpeg has libx264, AAC and HEVC decoding (for HEIC/HEIF and
# iPhone video); libheif-examples adds heif-convert for HEIC stills.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg libheif-examples \
 && rm -rf /var/lib/apt/lists/*
USER node

FROM runtime AS api
