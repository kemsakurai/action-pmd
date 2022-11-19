FROM openjdk:17-alpine

ENV REVIEWDOG_VERSION=v0.14.1

RUN wget -O - -q https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin/ ${REVIEWDOG_VERSION}

RUN wget -q https://github.com/pmd/pmd/releases/download/pmd_releases%2F6.51.0/pmd-bin-6.51.0.zip
RUN unzip pmd-bin-6.51.0.zip

RUN apk add --no-cache git

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
