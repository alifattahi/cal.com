FROM node:18 as builder

WORKDIR /calcom

ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG CALCOM_TELEMETRY_DISABLED
ARG DATABASE_URL
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret
ARG MAX_OLD_SPACE_SIZE=4096

ENV NEXT_PUBLIC_WEBAPP_URL=http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER \
    NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
    CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
    DATABASE_URL=$DATABASE_URL \
    NEXTAUTH_SECRET=${NEXTAUTH_SECRET} \
    CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY} \
    NODE_OPTIONS=--max-old-space-size=${MAX_OLD_SPACE_SIZE}

COPY package.json yarn.lock .yarnrc.yml playwright.config.ts turbo.json git-init.sh git-setup.sh ./
COPY .yarn ./.yarn
COPY apps ./apps
COPY packages ./packages
COPY tests ./tests

RUN yarn config set httpTimeout 1200000 && \ 
    npx turbo prune --scope=@calcom/web --scope=@calcom/api --docker && \
    yarn install && \
    yarn db-deploy && \
    yarn --cwd packages/prisma seed-app-store

RUN yarn turbo run build --filter=@calcom/web --filter=@calcom/api

# RUN yarn plugin import workspace-tools && \
#     yarn workspaces focus --all --production
RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache

FROM node:18 as builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000

ENV NODE_ENV production

COPY package.json .yarnrc.yml yarn.lock turbo.json ./
COPY .yarn ./.yarn
COPY --from=builder /node_modules ./node_modules
COPY --from=builder /packages ./packages
COPY --from=builder /apps ./apps
COPY --from=builder /packages/prisma/schema.prisma ./prisma/schema.prisma
COPY scripts scripts

# Save value used during this build stage. If NEXT_PUBLIC_WEBAPP_URL and BUILT_NEXT_PUBLIC_WEBAPP_URL differ at
# run-time, then start.sh will find/replace static values again.
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

RUN scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}

FROM node:18 as runner


WORKDIR /calcom
COPY --from=builder-two /calcom ./
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

ENV NODE_ENV production
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD wget --spider http://localhost:3000 || exit 1

CMD ["/calcom/scripts/start.sh"]