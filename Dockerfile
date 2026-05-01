FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl git g++ make wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/factor/factor.git && \
    cd factor && \
    git checkout cd14ceed53f6f9a43bbd3aec3950d8beb5439ed8
WORKDIR /opt/factor
RUN ./build.sh update

# Remove files not needed at runtime
RUN rm -rf .git build vm src misc Factor.app \
    factor.image.fresh boot.*.image libfactor.a libfactor-ffi-test.so \
    extra GNUmakefile Nmakefile LICENSE.txt README.md \
    build.sh build.cmd unmaintained

FROM cgr.dev/chainguard/wolfi-base

# Wolfi is glibc-based, so the Factor binary built on Debian above runs
# without a compat shim. bash for run.sh; gawk + jq + sed for the parser;
# coreutils for realpath / mktemp.
RUN apk add --no-cache bash coreutils gawk jq libstdc++ sed

COPY --from=builder /opt/factor /opt/factor
ENV PATH="/opt/factor:${PATH}" \
    XDG_CACHE_HOME=/tmp

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
