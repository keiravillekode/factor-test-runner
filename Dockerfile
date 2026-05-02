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
#   glib, gmodule, gobject, gio, graphene, atk, gobject-introspection, gir,
#   pango, x11, fonts, images
# - macOS-specific: cocoa, core-foundation, core-graphics, core-text, iokit
# - Windows-specific: windows
# - Linux-specific: linux
# - Networking, RPC, web: dns, ftp, html, http, mime, oauth1, oauth2, openssl,
#   resolv-conf, smtp, syndication, urls, webbrowser, xml, xml-rpc
# - Data formats: cbor, csv, ini-file, json, msgpack, pack, quoted-printable,
#   serialize, toml, uu
# - Persistence / db: couchdb, db
# - Encoding / hashing / compression: base16, base24, base32, base36, base45,
#   base58, base62, base64, base85, base91, base92, checksums, compression,
#   crypto, hex-strings
# - Specialised data structures with no exercise use: biassocs, bit-arrays,
#   bit-sets, bit-vectors, bitstreams, bloom-filters, boxes, circular,
#   columns, cuckoo-filters, disjoint-sets, dlists, heaps, interval-maps,
#   interval-sets, lazy, linked-assocs, linked-sets, lists, named-tuples,
#   nibble-arrays, reservoir-sampling, search-deques, specialized-arrays,
#   specialized-vectors, suffix-arrays, tuple-arrays, unrolled-lists, vlists
# - Pattern, parsing, text utilities: globs, lcs, match, peg,
#   porter-stemmer, regexp, simple-tokenizer, tr, wrap
# - Editor / interactive only: documents, inspector, listener, see, xdg
# - Other unused: xmode (syntax highlighting), game, farkup (markup),
#   calendar, colors, delegate, escape-strings, etc-hosts, eval, interpolate,
#   ip-parser, logging, memoize, method-chains, mirrors, models, nmake, ntp,
#   protocols, quoting, refs, retries, roman, simple-flat-file, system-info,
#   timers, typed, uuid, validators
RUN cd basis && rm -rf \
    atk cairo cocoa core-foundation core-graphics core-text fonts \
    farkup game gdk2 gdk3 gdk4 gdk-pixbuf gio gir glib gmodule \
    gobject gobject-introspection graphene gsk4 gtk2 gtk3 gtk4 \
    images iokit linux opengl pango ui windows x11 xmode \
    editors furnace help \
    dns ftp html http mime oauth1 oauth2 openssl resolv-conf smtp \
    syndication urls webbrowser xml xml-rpc \
    cbor csv ini-file json msgpack pack quoted-printable serialize toml uu \
    couchdb db \
    base16 base24 base32 base36 base45 base58 base62 base64 base85 base91 \
    base92 checksums compression crypto hex-strings \
    biassocs bit-arrays bit-sets bit-vectors bitstreams bloom-filters boxes \
    circular columns cuckoo-filters disjoint-sets dlists heaps \
    interval-maps interval-sets lazy linked-assocs linked-sets lists \
    named-tuples nibble-arrays reservoir-sampling search-deques \
    specialized-arrays specialized-vectors suffix-arrays tuple-arrays \
    unrolled-lists vlists \
    globs lcs match peg porter-stemmer regexp simple-tokenizer tr wrap \
    documents inspector listener see xdg \
    calendar colors delegate escape-strings etc-hosts eval interpolate \
    ip-parser logging memoize method-chains mirrors models nmake ntp \
    protocols quoting refs retries roman simple-flat-file system-info \
    timers typed uuid validators \
    bootstrap environment persistent random

# Asian and rare encodings: only utf8 / latin1 / strict are kept (everything
# bundled streams use). 8-bit is the multi-codepage non-utf umbrella.
RUN cd basis/io/encodings && rm -rf \
    8-bit big5 euc euc-jp euc-kr gb18030 iso2022 johab shift-jis utf32 utf7

# Drop *-docs.factor — only used by Factor's interactive help browser.
# *-tests.factor and tags.txt / summary.txt / authors.txt are kept: Factor's
# vocab loader and `test` word reference them and removing them breaks
# at least basis/binary-search at runtime.
RUN find . -name '*-docs.factor' -delete


FROM cgr.dev/chainguard/wolfi-base

# Wolfi is glibc-based, so the Factor binary built on Debian above runs
# without a compat shim. bash for run.sh; gawk + jq for the parser;
# coreutils for realpath / mktemp.
RUN apk add --no-cache bash coreutils gawk jq libstdc++

COPY --from=builder /opt/factor /opt/factor
ENV PATH="/opt/factor:${PATH}" \
    XDG_CACHE_HOME=/tmp

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
