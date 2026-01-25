# Build stage: Download and extract PMD
FROM alpine:3.19 AS pmd-builder

ARG PMD_VERSION=7.20.0

# hadolint ignore=DL3018
RUN apk add --no-cache wget unzip && \
    wget --progress=dot:giga -O /tmp/pmd.zip "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" && \
    unzip /tmp/pmd.zip -d /tmp && \
    mv /tmp/pmd-bin-${PMD_VERSION} /pmd && \
    rm /tmp/pmd.zip

# Runtime stage: Eclipse Temurin Java 21 + Reviewdog
FROM eclipse-temurin:21-alpine

ARG REVIEWDOG_VERSION=v0.21.0

# Install git and dependencies (required for reviewdog)
# hadolint ignore=DL3018
RUN apk add --no-cache git wget

# Install reviewdog
# hadolint ignore=DL4006,SC2086
RUN set -ex && \
    wget -O - --progress=dot:giga https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin/ ${REVIEWDOG_VERSION} && \
    reviewdog --version

# Copy PMD from build stage
COPY --from=pmd-builder /pmd /pmd

# Set PMD environment variables
ENV PMD_HOME=/pmd
ENV PATH="${PMD_HOME}/bin:/usr/local/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
