ARG BASE_IMAGE=node:22-bookworm
FROM ${BASE_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends strace curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY experiments ./experiments
COPY scripts ./scripts

# Nuxt の実験はビルドまで済ませておく
RUN cd experiments/nuxt && npm ci --no-audit --no-fund && npx nuxt build

ENV IN_DOCKER=yes
CMD ["bash", "scripts/run-all.sh"]
