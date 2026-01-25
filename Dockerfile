# Build stage: Download and extract PMD
FROM alpine:3.19 AS pmd-builder

ARG PMD_VERSION=7.7.0

RUN apk add --no-cache wget unzip && \
    wget https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-bin-${PMD_VERSION}.zip && \
    unzip pmd-bin-${PMD_VERSION}.zip && \
    rm pmd-bin-${PMD_VERSION}.zip && \
    mv pmd-bin-${PMD_VERSION} /pmd

# Runtime stage: Eclipse Temurin Java 21 + Reviewdog
FROM eclipse-temurin:21-alpine

ARG REVIEWDOG_VERSION=v0.21.0

# Install reviewdog
RUN wget -O - -q https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin/ ${REVIEWDOG_VERSION}

# Install git (required for reviewdog)
RUN apk add --no-cache git

# Copy PMD from build stage
COPY --from=pmd-builder /pmd /pmd

# Set PMD environment variables
ENV PMD_HOME=/pmd
ENV PATH="${PMD_HOME}/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
