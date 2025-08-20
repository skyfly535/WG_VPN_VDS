#!/usr/bin/env bash
set -Eeuo pipefail

# -------- Settings (override via env if needed) --------
WG_IFACE="${WG_IFACE:-wg0}"
WG_DIR="/etc/wireguard"
SERVER_CONF="$WG_DIR/${WG_IFACE}.conf"
CLIENTS_DIR="$WG_DIR/clients"

# VPN addressing (must match your server conf)
SERVER_VPN_IP="${SERVER_VPN_IP:-10.0.0.1}"
SERVER_VPN_CIDR="${SERVER_VPN_CIDR:-10.0.0.0/24}"

# Port (for info only; client uses Endpoint below)
SERVER_PORT="${SERVER_PORT:-51820}"

# Optional: override detected endpoint with ENDPOINT="x.x.x.x"
ENDPOINT="${ENDPOINT:-}"

# -------- Args --------
CLIENT_NAME="${1:-}"
if [[ -z "$CLIENT_NAME" ]]; then
  echo "Usage: $0 <client-name>"
  exit 1
fi

# -------- Preconditions --------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

for bin in wg qrencode awk grep curl ip; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing dependency: $bin"; exit 1; }
done

[[ -f "$SERVER_CONF" ]] || { echo "Server config not found: $SERVER_CONF"; exit 1; }
mkdir -p "$CLIENTS_DIR"
chmod 700 "$CLIENTS_DIR"

SERVER_PUBLIC_KEY_FILE="$WG_DIR/publickey"
[[ -f "$SERVER_PUBLIC_KEY_FILE" ]] || { echo "Server public key file not found: $SERVER_PUBLIC_KEY_FILE"; exit 1; }

# -------- Helpers --------
get_prefix() {
  # derive 10.0.0 from SERVER_VPN_IP
  echo "$SERVER_VPN_IP" | awk -F. '{printf "%s.%s.%s", $1,$2,$3}'
}

next_free_ip() {
  local prefix; prefix="$(get_prefix)"
  # collect used last octets from AllowedIPs lines in server conf (ignore comments)
  mapfile -t used < <(grep -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "$SERVER_CONF" \
    | grep -E "${prefix}\.[0-9]+/32" \
    | awk -F'[ ./]+' '{print $(NF-1)}' \
    | sort -n | uniq)

  # find first free from .2 to .254
  for i in $(seq 2 254); do
    local taken=0
    for u in "${used[@]:-}"; do
      if [[ "$u" == "$i" ]]; then taken=1; break; fi
    done
    # also avoid server IP last octet
    if [[ "$i" == "$(echo "$SERVER_VPN_IP" | awk -F. '{print $4}')" ]]; then taken=1; fi
    if [[ $taken -eq 0 ]]; then
      echo "${prefix}.${i}"
      return 0
    fi
  done
  return 1
}

detect_endpoint() {
  if [[ -n "$ENDPOINT" ]]; then
    echo "$ENDPOINT"
    return 0
  fi
  local ip4=""
  ip4="$(curl -4s https://ifconfig.co || true)"
  [[ -z "$ip4" ]] && ip4="$(curl -4s https://ifconfig.me || true)"
  echo "$ip4"
}

# -------- Generate keys --------
CLIENT_PRIVATE_KEY="$(wg genkey)"
CLIENT_PUBLIC_KEY="$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)"
CLIENT_PSK="$(wg genpsk)"
SERVER_PUBLIC_KEY="$(cat "$SERVER_PUBLIC_KEY_FILE")"

# -------- Allocate IP --------
CLIENT_IP="$(next_free_ip || true)"
if [[ -z "$CLIENT_IP" ]]; then
  echo "No free IPs left in ${SERVER_VPN_CIDR}"
  exit 1
fi

# -------- Append peer to server conf (idempotent guard) --------
if grep -q "^[[:space:]]*#*[[:space:]]*${CLIENT_NAME}[[:space:]]*$" "$SERVER_CONF"; then
  echo "Warning: a line with client name already exists in server conf, continuing anyway."
fi

cat >> "$SERVER_CONF" <<EOF

# ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP}/32
EOF

# -------- Apply to running interface without downtime --------
if ip link show "$WG_IFACE" >/dev/null 2>&1; then
  wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")
else
  # interface is down; bring it up
  wg-quick up "$WG_IFACE"
fi

# -------- Build client config --------
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
ENDPOINT_IP="$(detect_endpoint)"
if [[ -z "$ENDPOINT_IP" ]]; then
  ENDPOINT_IP="<SERVER_PUBLIC_IP>"
fi

cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/32
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${ENDPOINT_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF"

# -------- Output summary and QR --------
echo "Client created:"
echo "  Name:     ${CLIENT_NAME}"
echo "  Address:  ${CLIENT_IP}/32"
echo "  Config:   ${CLIENT_CONF}"
echo
echo "QR (for mobile import):"
qrencode -t ansiutf8 < "${CLIENT_CONF}"
echo
echo "Done."
