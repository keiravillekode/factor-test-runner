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

# Prune basis subdirs that exercism tests cannot reach. Source files only —
# the precompiled bytecode for these is in factor.image, which is unaffected.
# - GUI and graphics: ui, opengl, cairo, gdk2/3/4, gtk2/3/4, gdk-pixbuf, gsk4,
#   glib, gmodule, gobject, gio, graphene, atk, gobject-introspection, gir
# - macOS-specific: cocoa, core-foundation, core-graphics, core-text
# - Windows-specific: windows
# - Other unused: xmode (syntax highlighting), game, farkup (markup)
RUN cd basis && rm -rf \
    atk cairo cocoa core-foundation core-graphics core-text \
    farkup game gdk2 gdk3 gdk4 gdk-pixbuf gio gir glib gmodule \
    gobject gobject-introspection graphene gsk4 gtk2 gtk3 gtk4 \
    opengl ui windows xmode \
    editors furnace help

# Drop *-docs.factor — only used by Factor's interactive help browser.
# *-tests.factor and tags.txt / summary.txt / authors.txt are kept: Factor's
# vocab loader and `test` word reference them and removing them breaks
# at least basis/binary-search at runtime.
RUN find . -name '*-docs.factor' -delete


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
