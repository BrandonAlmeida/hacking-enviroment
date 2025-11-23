#!/bin/bash

# ==============================================================================
# switch_net - Gerencia o roteamento de rede do contêiner Kali
#
# Parâmetros:
#   --vpn   Roteia o tráfego através do gateway WireGuard padrão.
#   --tor   Usa endereço-fonte dedicado para acionar o transparent proxy Tor.
# ==============================================================================

set -euo pipefail

VPN_GATEWAY_IP="${GATEWAY_IP:-10.77.10.4}"
TOR_GATEWAY_IP="${TOR_GATEWAY_IP:-$VPN_GATEWAY_IP}"
LAN_SUBNET="${LAN_SUBNET:-10.77.10.0/28}"
VPN_SOURCE_IP="${VPN_SOURCE_IP:-$(ip -4 addr show dev eth0 | awk '/inet / {print $2}' | head -n1 | cut -d/ -f1)}"
TOR_SOURCE_IP="${TOR_SOURCE_IP:-10.77.10.6}"
TOR_SOURCE_CIDR="${TOR_SOURCE_IP}/28"
VPN_DNS="${VPN_DNS:-8.8.8.8}"
TOR_DNS_IP="${TOR_DNS_IP:-$VPN_GATEWAY_IP}"

TOR_ALIAS_LABEL="eth0:tor"

set_dns() {
    local resolver="$1"
    echo "nameserver $resolver" > /etc/resolv.conf
    echo "[+] DNS definido para $resolver"
}

set_lan_source() {
    local source_ip="$1"
    ip route replace "$LAN_SUBNET" dev eth0 proto kernel scope link src "$source_ip"
    echo "[+] Rota local $LAN_SUBNET atualizada para src $source_ip"
}

ensure_tor_alias() {
    if ! ip addr show dev eth0 | grep -q "$TOR_SOURCE_IP"; then
        ip addr add "$TOR_SOURCE_CIDR" dev eth0 label "$TOR_ALIAS_LABEL"
        echo "[+] Alias Tor $TOR_SOURCE_CIDR adicionado."
    fi
}

remove_tor_alias() {
    if ip addr show dev eth0 | grep -q "$TOR_SOURCE_IP"; then
        ip addr del "$TOR_SOURCE_CIDR" dev eth0 2>/dev/null || true
        echo "[+] Alias Tor removido."
    fi
}

get_current_state() {
    local default_line
    default_line=$(ip route show default | head -n1)
    if echo "$default_line" | grep -q "src $TOR_SOURCE_IP"; then
        echo "tor"
    elif echo "$default_line" | grep -q "src $VPN_SOURCE_IP"; then
        echo "vpn"
    else
        echo "none"
    fi
}

set_vpn_mode() {
    local current_state
    current_state=$(get_current_state)
    if [ "$current_state" = "vpn" ]; then
        echo "[INFO] O modo VPN já está ativo."
        exit 0
    fi

    echo "[+] Configurando rota padrão para o gateway VPN ($VPN_GATEWAY_IP) com origem $VPN_SOURCE_IP..."
    ip route replace default via "$VPN_GATEWAY_IP" src "$VPN_SOURCE_IP"
    set_lan_source "$VPN_SOURCE_IP"
    set_dns "$VPN_DNS"
    remove_tor_alias
    echo "[SUCCESS] Tráfego roteado pela VPN/WireGuard."
}

set_tor_mode() {
    local current_state
    current_state=$(get_current_state)
    if [ "$current_state" = "tor" ]; then
        echo "[INFO] O modo Tor já está ativo."
        exit 0
    fi

    ensure_tor_alias
    echo "[+] Configurando rota padrão para $TOR_GATEWAY_IP com origem $TOR_SOURCE_IP..."
    ip route replace default via "$TOR_GATEWAY_IP" src "$TOR_SOURCE_IP"
    set_lan_source "$TOR_SOURCE_IP"
    set_dns "$TOR_DNS_IP"
    echo "[SUCCESS] Tráfego encaminhado para o gateway Tor."
}

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root."
  exit 1
fi

case "${1:-}" in
    --vpn)
        set_vpn_mode
        ;;
    --tor)
        set_tor_mode
        ;;
    *)
        echo "Uso: $0 [--vpn|--tor]"
        exit 1
        ;;
esac
