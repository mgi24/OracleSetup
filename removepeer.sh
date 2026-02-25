#!/bin/bash

set -euo pipefail

WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"

if [[ "${EUID}" -ne 0 ]]; then
	echo "Script ini harus dijalankan sebagai root (sudo)."
	exit 1
fi

if [[ ! -f "$WG_CONF" ]]; then
	echo "File config tidak ditemukan: $WG_CONF"
	exit 1
fi

echo "=== Peer history dari $WG_CONF ==="
awk '
BEGIN { RS=""; ORS="\n\n"; n=0 }
/\[Peer\]/ {
	n++
	printf "---- Peer #%d ----\n%s\n\n", n, $0
}
END {
	if (n == 0) {
		print "Tidak ada peer di file config."
	}
}
' "$WG_CONF"

read -r -p "Input IP peer yang mau dihapus (contoh 10.8.0.3): " TARGET_IP

if [[ ! "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
	echo "Format IP tidak valid: $TARGET_IP"
	exit 1
fi

TMP_CONF="$(mktemp)"
META_FILE="$(mktemp)"

IP_REGEX="$TARGET_IP"
IP_REGEX="${IP_REGEX//./\\.}"

set +e
awk -v ip_re="$IP_REGEX" -v meta_file="$META_FILE" '
BEGIN {
	RS=""
	ORS="\n\n"
	removed=0
}
function get_pubkey(block,   i, n, lines, val) {
	n = split(block, lines, "\n")
	for (i = 1; i <= n; i++) {
		if (lines[i] ~ /^PublicKey[[:space:]]*=/) {
			val = lines[i]
			sub(/^PublicKey[[:space:]]*=[[:space:]]*/, "", val)
			gsub(/[[:space:]]+$/, "", val)
			return val
		}
	}
	return ""
}
{
	if ($0 ~ /\[Peer\]/ && removed == 0 && $0 ~ ("AllowedIPs[[:space:]]*=[^\n]*" ip_re "(/32)?([^0-9]|$)")) {
		pub = get_pubkey($0)
		if (pub != "") {
			print pub > meta_file
			close(meta_file)
		}
		removed = 1
		next
	}
	print
}
END {
	if (removed == 0) {
		exit 3
	}
}
' "$WG_CONF" > "$TMP_CONF"
awk_status=$?
set -e

if [[ $awk_status -eq 3 ]]; then
	rm -f "$TMP_CONF" "$META_FILE"
	echo "Peer dengan AllowedIPs berisi $TARGET_IP tidak ditemukan di $WG_CONF"
	exit 1
elif [[ $awk_status -ne 0 ]]; then
	rm -f "$TMP_CONF" "$META_FILE"
	echo "Terjadi error saat memproses file config."
	exit 1
fi

cp "$WG_CONF" "${WG_CONF}.bak.$(date +%F-%H%M%S)"
mv "$TMP_CONF" "$WG_CONF"

REMOVED_PUBKEY=""
if [[ -s "$META_FILE" ]]; then
	REMOVED_PUBKEY="$(head -n 1 "$META_FILE")"
fi
rm -f "$META_FILE"

if wg show "$WG_INTERFACE" >/dev/null 2>&1; then
	if [[ -n "$REMOVED_PUBKEY" ]]; then
		wg set "$WG_INTERFACE" peer "$REMOVED_PUBKEY" remove || true
	fi
	wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_INTERFACE")
	echo "Peer $TARGET_IP berhasil dihapus tanpa shutdown $WG_INTERFACE."
else
	echo "Peer $TARGET_IP dihapus dari file. Interface $WG_INTERFACE tidak aktif, jadi sync runtime dilewati."
fi
