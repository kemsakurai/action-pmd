# Build stage: Download and extract PMD
FROM alpine:3.19 AS pmd-builder

ARG PMD_VERSION=7.20.0

# hadolint ignore=DL3018
RUN apk add --no-cache wget unzip && \
    wget -O /tmp/pmd.zip "https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip" && \
    unzip /tmp/pmd.zip -d /tmp && \
    mv /tmp/pmd-bin-${PMD_VERSION} /pmd && \
    rm /tmp/pmd.zip

# Runtime stage: Eclipse Temurin Java 21 + Reviewdog
FROM eclipse-temurin:21-alpine

ARG REVIEWDOG_VERSION=v0.21.0

# Install reviewdog
# hadolint ignore=DL4006,SC2086
RUN wget -O - -q https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin/ ${REVIEWDOG_VERSION}

# Install git (required for reviewdog)
# hadolint ignore=DL3018
RUN apk add --no-cache git

# Copy PMD from build stage
COPY --from=pmd-builder /pmd /pmd

# Set PMD environment variables
ENV PMD_HOME=/pmd
ENV PATH="${PMD_HOME}/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
