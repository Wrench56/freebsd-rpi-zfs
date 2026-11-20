FROM ghcr.io/freebsd/freebsd-notoolchain:15.1

RUN pkg install -y -q dtc ca_root_nss mtools python3 hs-ShellCheck \
 && pkg clean -a -y \
 && mkdir -p /inputs

WORKDIR /opt/monitor
COPY . .

RUN shellcheck -s sh -x build.sh root/usr/local/sbin/logsync \
        root/usr/local/etc/rc.d/*

RUN <<'EOF'
set -eu
. ./manifest.env

cd /inputs
fetch -q -o "$BASE_IMG.xz" "$BASE_URL"
fetch -q -o "$BASE_IMG.sum" "${BASE_URL%/*}/CHECKSUM.SHA256-${BASE_IMG%.img}"

digest=$(mktemp)
trap 'rm -f "$digest"' EXIT
sha256 "$BASE_IMG.xz" > "$digest"
cmp "$digest" "$BASE_IMG.sum"

xz -d "$BASE_IMG.xz"

fetch -q "$DIST_URL/MANIFEST" "$DIST_URL/base.txz" "$DIST_URL/kernel.txz"
sha256 -q base.txz kernel.txz > "$digest"
grep -E '^(base|kernel)\.txz' MANIFEST | cut -f 2 | cmp "$digest" -
rm MANIFEST
rm "$digest"
EOF

CMD ["/opt/monitor/build.sh"]
