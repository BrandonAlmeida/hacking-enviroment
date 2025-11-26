#!/bin/bash

echo "[+] Initializing Gateway..."

# Stop on errors
set -e

# Default WAN interface is eth0, will be overwritten by WireGuard
WAN_IF="eth0"
WG_IF=""
VPN_SUBNET="10.77.10.0/28"
TOR_TRANSPARENT_PORT=9041
TOR_DNS_PORT=5353
TOR_CLIENT_IP="${TOR_CLIENT_IP:-10.77.10.6}"

# Function to set up the kill switch
setup_firewall() {
    echo "[+] Setting up firewall kill switch..."

    # Get Tor UID
    TOR_UID=$(id -u debian-tor)
    if [ -z "$TOR_UID" ]; then
        echo "[!] Could not find UID for debian-tor. Firewall will be more permissive."
        TOR_UID="debian-tor" # Fallback, might not work
    fi

    # Flush all previous rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Default policies: DROP everything
    iptables -P INPUT   DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT  DROP

    # --- INPUT CHAIN ---
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    # Allow established and related connections (replies to our outbound traffic)
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow connections from the local Docker network (for Kali container)
    iptables -A INPUT -s "$VPN_SUBNET" -j ACCEPT

    # Allow incoming connections to exposed service ports
    echo "[+] Allowing incoming connections to service ports"
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT # Dante
    iptables -A INPUT -p tcp --dport 9050 -j ACCEPT # Tor SOCKS
    iptables -A INPUT -p tcp --dport 9040 -j ACCEPT # Tor HTTP proxy
    iptables -A INPUT -p tcp --dport "$TOR_TRANSPARENT_PORT" -j ACCEPT # Tor transparent proxy
    iptables -A INPUT -p udp --dport "$TOR_DNS_PORT" -j ACCEPT # Tor DNS
    iptables -A INPUT -p tcp --dport "$TOR_DNS_PORT" -j ACCEPT # Tor DNS

    # --- FORWARD CHAIN ---
    # Allow forwarding for established and related connections
    iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow forwarding from the local Docker network to the WAN interface
    if [ -n "$WG_IF" ]; then
        iptables -A FORWARD -i eth0 -o "$WG_IF" -s "$VPN_SUBNET" -j ACCEPT
    fi

    # --- OUTPUT CHAIN ---
    # Allow loopback
    iptables -A OUTPUT -o lo -j ACCEPT
    # Allow established and related connections (replies to our inbound traffic)
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    #Allow outgoing connections to the local Docker network (e.g., for SSH to Kali)
    iptables -A OUTPUT -d "$VPN_SUBNET" -o eth0 -j ACCEPT 
    # Allow traffic from the Tor user
    iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
    # Allow DNS queries (needed for WireGuard endpoint resolution and Tor)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # If WireGuard is up, allow its traffic and route all other allowed output through it
    if [ -n "$WG_IF" ]; then
        # This assumes the WireGuard endpoint port is known.
        # It should be dynamically extracted if possible, but 51820 is standard.
        iptables -A OUTPUT -o eth0 -p udp --dport 51820 -j ACCEPT
        iptables -A OUTPUT -o "$WG_IF" -j ACCEPT
        echo "[+] Firewall configured to route through WireGuard interface: $WG_IF"
    else
        echo "[!] WARNING: WireGuard is not active. Firewall will NOT allow outbound traffic except for Tor and DNS."
    fi

    # --- IPv6 Firewall Rules ---
    echo "[+] Setting up ip6tables kill switch..."

    # Flush all previous IPv6 rules
    ip6tables -F
    ip6tables -X
    # ip6tables -t nat -F # flush nat table if exists (some systems have it)
    # ip6tables -t nat -X
    # ip6tables -t mangle -F # flush mangle table if exists
    # ip6tables -t mangle -X

    # Default policies: DROP everything for IPv6
    ip6tables -P INPUT   DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT  DROP

    # --- IPv6 INPUT CHAIN ---
    # Allow loopback
    ip6tables -A INPUT -i lo -j ACCEPT
    # Allow established and related connections (replies to our outbound traffic)
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow incoming connections to exposed service ports (if they support IPv6)
    # Note: Docker doesn't map IPv6 ports by default like IPv4, but good to have
    ip6tables -A INPUT -p tcp --dport 1080 -j ACCEPT # Dante (if listening on IPv6)
    ip6tables -A INPUT -p tcp --dport 9050 -j ACCEPT # Tor SOCKS (if listening on IPv6)
    ip6tables -A INPUT -p tcp --dport 9040 -j ACCEPT # Tor HTTP proxy (if listening on IPv6)
    ip6tables -A INPUT -p tcp --dport "$TOR_TRANSPARENT_PORT" -j ACCEPT # Tor transparent proxy (if listening on IPv6)
    ip6tables -A INPUT -p udp --dport "$TOR_DNS_PORT" -j ACCEPT # Tor DNS (if listening on IPv6)
    ip6tables -A INPUT -p tcp --dport "$TOR_DNS_PORT" -j ACCEPT # Tor DNS (if listening on IPv6)


    # --- IPv6 FORWARD CHAIN ---
    # Allow forwarding for established and related connections
    ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow forwarding from the local Docker network to the WAN interface (if WG_IF is IPv6 capable)
    if [ -n "$WG_IF" ]; then
        # Assuming eth0 as internal interface for forwarding from other containers
        ip6tables -A FORWARD -i eth0 -o "$WG_IF" -j ACCEPT
    fi

    # --- IPv6 OUTPUT CHAIN ---
    # Allow loopback
    ip6tables -A OUTPUT -o lo -j ACCEPT
    # Allow established and related connections (replies to our inbound traffic)
    ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow traffic from the Tor user (Tor supports IPv6)
    ip6tables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
    # Allow DNS queries (needed for WireGuard endpoint resolution and Tor)
    ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT
    ip6tables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # If WireGuard is up, allow its traffic and route all other allowed output through it
    if [ -n "$WG_IF" ]; then
        # WireGuard itself uses UDP 51820 for both IPv4 and IPv6
        ip6tables -A OUTPUT -o eth0 -p udp --dport 51820 -j ACCEPT
        ip6tables -A OUTPUT -o "$WG_IF" -j ACCEPT
        echo "[+] Firewall configured to route IPv6 through WireGuard interface: $WG_IF"
    else
        echo "[!] WARNING: WireGuard is not active. IPv6 Firewall will NOT allow outbound traffic except for Tor and DNS."
    fi

    # --- Transparent Tor redirection for Kali when using alternate source IP ---
    if [ -n "$TOR_CLIENT_IP" ]; then
        echo "[+] Adding transparent Tor rules for client $TOR_CLIENT_IP"
        iptables -t nat -A PREROUTING -s "$TOR_CLIENT_IP" -p udp --dport 53 -j REDIRECT --to-ports "$TOR_DNS_PORT"
        iptables -t nat -A PREROUTING -s "$TOR_CLIENT_IP" -p tcp --dport 53 -j REDIRECT --to-ports "$TOR_DNS_PORT"
        iptables -t nat -A PREROUTING -s "$TOR_CLIENT_IP" -p tcp --syn -j REDIRECT --to-ports "$TOR_TRANSPARENT_PORT"
    fi
}


##############################
# 1. Activate IP Forwarding
##############################
echo "[+] Activating IP Forwarding"
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.src_valid_mark=1


##############################
# 2. Start WireGuard if configured
##############################
if [ -n "$WG_CONFIG" ] && [ -f "/etc/wireguard/$WG_CONFIG" ]; then
    # Interface name is the config file name without .conf
    WG_IF="${WG_CONFIG%.*}"
    WAN_IF="$WG_IF"
    echo "[+] WireGuard config found: $WG_CONFIG"
    echo "[+] Bringing up WireGuard interface: $WG_IF"
    # Use wg-quick to set up routing, then setup_firewall will lock it down
    wg-quick up "$WG_IF"
else
    echo "[-] WG_CONFIG environment variable not set or file not found."
    echo "[-] VPN will not be started."
fi


##############################
# 3. Configure DNS
##############################
echo "[+] Configuring DNS..."
DNS_SERVER=""
if [ -n "$WG_CONFIG" ] && [ -f "/etc/wireguard/$WG_CONFIG" ]; then
    # Try to find DNS server in the WireGuard config, ignoring commented lines
    DNS_SERVER=$(grep -v '^#' "/etc/wireguard/$WG_CONFIG" | grep -oP '(?<=DNS\s=\s)[^\s,]+' | head -n 1)
fi

if [ -z "$DNS_SERVER" ]; then
    echo "[-] No DNS found in WireGuard config or VPN not active. Using fallback DNS 1.1.1.1."
    DNS_SERVER="1.1.1.1"
fi

echo "[+] Setting nameserver to $DNS_SERVER"
echo "nameserver $DNS_SERVER" > /etc/resolv.conf


##############################
# 4. Setup Firewall
##############################
setup_firewall


##############################
# 5. Start Tor
##############################
echo "[+] Starting Tor service..."
tor -f /etc/tor/torrc &
sleep 3


##############################
# 6. Start Dante SOCKS proxy
##############################
echo "[+] Configuring and starting Dante SOCKS proxy (in background)..."
DANTE_CONF="/etc/danted/danted.conf"
DANTE_TEMPLATE="/etc/danted/danted.conf.template"

if [ -f "$DANTE_TEMPLATE" ]; then
    echo "[+] Refreshing Dante config from template..."
    cp "$DANTE_TEMPLATE" "$DANTE_CONF"
elif [ ! -f "$DANTE_CONF" ]; then
    echo "[!] Dante template not found and config missing. SOCKS proxy will not start."
fi

if [ -f "$DANTE_CONF" ]; then
    sed -i "s/__WAN_IF__/$WAN_IF/g" "$DANTE_CONF"
    /usr/local/sbin/sockd -f "$DANTE_CONF" &
else
    echo "[!] Skipping Dante startup; configuration file is unavailable."
fi


##############################
# 7. Configure NAT for the Kali network
##############################
echo "[+] Configuring NAT for subnet $VPN_SUBNET..."
if [ -z "$WAN_IF" ]; then
    echo "[!] WAN interface not detected. NAT will not be configured."
else
    echo "[+] Applying NAT masquerade to interface: $WAN_IF"
    iptables -t nat -A POSTROUTING -s "$VPN_SUBNET" -o "$WAN_IF" -j MASQUERADE
fi


##############################
# 8. Keep container running
##############################
echo "[+] Gateway initialization complete!"
echo "[+] Active outbound interface: $WAN_IF"
tail -f /dev/null
