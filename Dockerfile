# To refresh, copy the Digest from
# `docker buildx imagetools inspect cgr.dev/chainguard/wolfi-base:latest`
ARG WOLFI_BASE=cgr.dev/chainguard/wolfi-base@sha256:3258be472764337fd13095bcbb3182da170243b5819fd67ad4c0754590588b31

FROM ${WOLFI_BASE} AS builder

# build-base bundles gcc/g++, make and glibc-dev (for the C++ side
# of Factor's VM); the rest fetch + bootstrap the source tree.
# gcc / libstdc++-dev are held at the last 15.x release
RUN apk add --no-cache bash build-base curl git wget \
    gcc=15.2.0-r11 libstdc++-dev=15.2.0-r11

# Factor 0.101
ARG FACTOR_COMMIT="a56e6390e81340be6573cb790311c0a980a5f369"

WORKDIR /opt
RUN git clone https://github.com/factor/factor.git && \
    cd factor && \
    git checkout ${FACTOR_COMMIT}
WORKDIR /opt/factor

# Bootstrap a headless image: drop the GUI (ui, ui.tools), the in-image help
# system (help, handbook), and the dev-tools component (tools) from the bootstrap
# component set.
ARG FACTOR_EXCLUDE="ui ui.tools help handbook tools"
RUN sed -i 's#-i="\$BOOT_IMAGE"#-i="$BOOT_IMAGE" -exclude="'"${FACTOR_EXCLUDE}"'"#' build.sh

# build the pinned commit with no git pull.
RUN ./build.sh net-bootstrap

# Precompile tools.test AND the common exercise vocabs into factor.image, then re-save it.
RUN ./factor -e='USING: accessors arrays ascii assocs calendar calendar.english combinators combinators.short-circuit command-line concurrency.combinators concurrency.locks continuations debugger deques destructors dlists formatting fry generic grouping hash-sets hashtables io io.encodings.utf8 io.files io.streams.string kernel lexer locals macros make math math.bitwise math.combinatorics math.constants math.functions math.order math.parser math.primes math.statistics namespaces prettyprint.config quotations random random.mersenne-twister ranges regexp sequences sets sorting source-files.errors.debugger splitting splitting.monotonic strings system tools.test typed unicode vectors vocabs vocabs.loader memory ; save'

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
#   colors, delegate, escape-strings, etc-hosts, eval, interpolate,
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
    colors delegate escape-strings etc-hosts eval interpolate \
    ip-parser logging memoize method-chains mirrors models nmake ntp \
    protocols quoting refs retries roman simple-flat-file system-info \
    timers typed uuid validators \
    bootstrap environment persistent

# Asian and rare encodings: only utf8 / latin1 / strict are kept (everything
# bundled streams use). 8-bit is the multi-codepage non-utf umbrella.
RUN cd basis/io/encodings && rm -rf \
    8-bit big5 euc euc-jp euc-kr gb18030 iso2022 johab shift-jis utf32 utf7

# Drop *-docs.factor — only used by Factor's interactive help browser.
# *-tests.factor and tags.txt / summary.txt / authors.txt are kept: Factor's
# vocab loader and `test` word reference them and removing them breaks
# at least basis/binary-search at runtime.
RUN find . -name '*-docs.factor' -delete

# Drop the Unicode source data tables. These are parsed only during bootstrap to
# build the unicode tables that are baked into factor.image; they are not read at
# runtime.
RUN rm -f basis/unicode/UnicodeData.txt \
    basis/unicode/allkeys.txt

RUN strip factor


FROM ${WOLFI_BASE}

# bash for run.sh
# coreutils for realpath / mktemp
# gawk + jq for the parser
RUN apk add --no-cache bash coreutils gawk jq libstdc++

COPY --from=builder /opt/factor /opt/factor
ENV PATH="/opt/factor:${PATH}" \
    XDG_CACHE_HOME=/tmp

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
