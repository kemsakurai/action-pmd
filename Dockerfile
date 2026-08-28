# syntax=docker/dockerfile:1

# Build stage: Download and extract PMD
FROM alpine:3.22@sha256:310c62b5e7ca5b08167e4384c68db0fd2905dd9c7493756d356e893909057601 AS pmd-builder

ARG PMD_VERSION=7.28.0-SNAPSHOT

# hadolint ignore=DL3018
RUN apk add --no-cache wget unzip && \
    wget --progress=dot:giga -O /tmp/pmd.zip "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" && \
    unzip /tmp/pmd.zip -d /tmp && \
    mv /tmp/pmd-bin-${PMD_VERSION} /pmd && \
    rm /tmp/pmd.zip

# Build stage: Download reviewdog binary from immutable release asset
FROM alpine:3.22@sha256:310c62b5e7ca5b08167e4384c68db0fd2905dd9c7493756d356e893909057601 AS reviewdog-builder

ARG REVIEWDOG_VERSION=v0.21.0
ARG TARGETARCH

# hadolint ignore=DL3018
RUN apk add --no-cache wget tar && \
    set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) REVIEWDOG_ARCH="x86_64" ;; \
      arm64) REVIEWDOG_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    REVIEWDOG_VERSION_NO_V="${REVIEWDOG_VERSION#v}"; \
    wget --progress=dot:giga -O /tmp/reviewdog.tar.gz "https://github.com/reviewdog/reviewdog/releases/download/${REVIEWDOG_VERSION}/reviewdog_${REVIEWDOG_VERSION_NO_V}_Linux_${REVIEWDOG_ARCH}.tar.gz" && \
    tar -xzf /tmp/reviewdog.tar.gz -C /tmp reviewdog && \
    chmod +x /tmp/reviewdog

# Runtime stage: Eclipse Temurin Java 21 JRE + PMD + Reviewdog
FROM eclipse-temurin:21-jre-alpine@sha256:704db3c40204a44f471191446ddd9cda5d60dab40f0e15c6507b815ed897238b

# Install runtime dependency required by reviewdog for diff/filter operations
# hadolint ignore=DL3018
RUN apk add --no-cache git

# Copy PMD from build stage
COPY --from=pmd-builder /pmd /pmd

# Copy reviewdog binary from build stage
COPY --from=reviewdog-builder /tmp/reviewdog /usr/local/bin/reviewdog

# Set PMD environment variables
ENV PMD_HOME=/pmd
ENV PATH="${PMD_HOME}/bin:/usr/local/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
