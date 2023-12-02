FROM node:lts-slim AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

ENV SECRET_GITHUB_BEARER_TOKEN ""
ENV SECRET_GITLAB_BEARER_TOKEN ""
ENV SECRET_PROXYCURL_BEARER_TOKEN ""
# JSON array
ENV SECRET_ADMIN_IPS '[]'
ENV PUBLIC_NETLIFY_SITE_ID "0afd9771-2b63-4228-9750-56921d8247a6"
ENV PUBLIC_GITLAB_API_ENDPOINT "https://gitlab.com/api/graphql"
ENV PUBLIC_GITHUB_API_ENDPOINT "https://api.github.com/graphql"
ENV PUBLIC_PROXYCURL_API_ENDPOINT "https://nubela.co/proxycurl/api/v2"
ENV PUBLIC_HYGRAPH_API_ENDPOINT "https://api-eu-central-1-shared-euc1-02.hygraph.com/v2/cl9bfrahc3vlz01t60835c8hx/master"
ENV PUBLIC_LINKEDIN_GIST_ID "ff093380f245a9ecd280d1b2aaa17aa7"
ENV PUBLIC_GIT_REPO_ID "sachahjkl/sacha.house"

RUN corepack enable

COPY . /app
WORKDIR /app

FROM base AS prod-deps
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --prod --frozen-lockfile

FROM base AS build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
RUN pnpm run build

FROM base

ENV NODE_ENV=production

COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/build /app/build

EXPOSE 3000
CMD [ "pnpm", "start" ]