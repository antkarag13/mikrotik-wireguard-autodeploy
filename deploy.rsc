# =====================================================================
#  MikroTik WireGuard Auto-Deploy  v1.0.0
#  Site-to-site WireGuard client for RouterOS v7+, deployed in one paste.
#  https://github.com/antkarag13/mikrotik-wireguard-autodeploy
#
#  - DHCP client on ether1 that auto-detects the local LAN subnet and
#    patches the firewall/NAT rules to match it
#  - /32 bypass route to the VPN endpoint (avoids the 0.0.0.0/0 loop)
#  - NETMAP so overlapping customer LANs are reachable via a mask subnet
#  - Hidden management Wi-Fi on wlan1 with its own DHCP pool
#  - Netwatch-driven LED that shows tunnel status
#
#  Fill in the variables below before pasting into the router terminal.
#  Never commit a copy of this file with real keys or passwords in it.
# =====================================================================
{
# ---------------------------------------------------------------------
# 1. WireGuard settings
# ---------------------------------------------------------------------
:local wgPrivKey  "PASTE_CLIENT_PRIVATE_KEY";
:local wgPubKey   "PASTE_SERVER_PUBLIC_KEY";
:local wgPsk      "PASTE_PRESHARED_KEY";
:local wgEndpoint "vpn.example.com";      # hostname or public IP of the server
:local wgPort     51820;
#
# ---------------------------------------------------------------------
# 2. IP & routing settings
# ---------------------------------------------------------------------
:local wgIp       "10.8.0.X/24";          # this client's tunnel address
:local wgServerIp "10.8.0.1";             # server's tunnel address
:local peerSubnet "10.8.0.0/24";          # whole tunnel subnet
:local maskSubnet "10.0.X.0/24";          # unique mask subnet for this site's LAN
#
# ---------------------------------------------------------------------
# 3. Management Wi-Fi
# ---------------------------------------------------------------------
:local mgmtSsid "YOUR-MGMT-SSID";
:local mgmtPass "YOUR-STRONG-WIFI-PASSWORD";
#
# =====================================================================
#  DO NOT EDIT BELOW THIS LINE
# =====================================================================
:log info "Starting automated VPN deployment...";

# 1. WAN / LOCAL LAN — DHCP client with auto-logic
#    On every lease: detect the LAN subnet, install a /32 bypass route to
#    the endpoint via the upstream gateway, and patch the VPN rules.
#    The rules are matched by their comment, so keep the comments in
#    section 4 unchanged.
#    Escaped \$ variables are evaluated later, when the lease is bound;
#    $wgEndpoint (unescaped) is baked in now, at deploy time.
/ip/dhcp-client add interface=ether1 disabled=no comment="Get Local IP and Internet" script=":if (\$bound = 1) do={ \
    :delay 3s; \
    :local ipAddr [/ip address get [find interface=ether1 dynamic=yes] address]; \
    :local netAddr [/ip address get [find interface=ether1 dynamic=yes] network]; \
    :local pos [:find \$ipAddr \"/\"]; \
    :local prefix [:pick \$ipAddr \$pos [:len \$ipAddr]]; \
    :local fullSubnet (\$netAddr . \$prefix); \
    :local gw [/ip/dhcp-client get [find interface=ether1] gateway]; \
    :local epIp [:resolve \"$wgEndpoint\"]; \
    :log info (\"WG-Auto: LAN=\" . \$fullSubnet . \" GW=\" . \$gw . \" EP=\" . \$epIp); \
    /ip/route remove [find comment=\"VPN Endpoint Bypass\"]; \
    /ip/route add dst-address=(\$epIp . \"/32\") gateway=\$gw distance=1 comment=\"VPN Endpoint Bypass\"; \
    /ip/firewall/filter set [find comment=\"Allow WG Forwarding to LAN\"] dst-address=\$fullSubnet; \
    /ip/firewall/nat set [find comment=\"Netmap: Disguise Inbound to LAN\"] to-addresses=\$fullSubnet disabled=no; \
    /ip/firewall/nat set [find comment=\"Masquerade: Inbound Peer to LAN\"] dst-address=\$fullSubnet; \
    :log info \"WG-Auto: VPN rules patched successfully.\"; \
}"

# 2. MANAGEMENT WI-FI (hidden SSID, own subnet)
#    Uses the legacy "wireless" package (/interface/wireless).
#    Out-of-band access to the router even when the LAN or VPN is down.
/interface/wireless/security-profiles add name=mgmt-profile mode=dynamic-keys authentication-types=wpa2-psk wpa2-pre-shared-key=$mgmtPass
/interface/wireless set [find default-name=wlan1] mode=ap-bridge ssid=$mgmtSsid hide-ssid=yes security-profile=mgmt-profile band=2ghz-b/g/n frequency=auto disabled=no
/ip/address add address=192.168.99.1/24 interface=wlan1 comment="Management Wi-Fi"
/ip/pool add name=mgmt-pool ranges=192.168.99.10-192.168.99.50
/ip/dhcp-server add name=mgmt-dhcp interface=wlan1 address-pool=mgmt-pool disabled=no
/ip/dhcp-server/network add address=192.168.99.0/24 gateway=192.168.99.1 dns-server=8.8.8.8,1.1.1.1

# 3. WIREGUARD
#    MTU 1280 leaves headroom for WireGuard + PPPoE/LTE overhead upstream.
#    persistent-keepalive keeps the NAT mapping open so the server can
#    reach this site at any time.
/interface/wireguard add name=wg-client private-key=$wgPrivKey mtu=1280 listen-port=$wgPort
/interface/wireguard/peers add interface=wg-client public-key=$wgPubKey preshared-key=$wgPsk endpoint-address=$wgEndpoint endpoint-port=$wgPort allowed-address=0.0.0.0/0 persistent-keepalive=25s
/ip/address add address=$wgIp interface=wg-client
/ip/dns set servers=1.1.1.1,8.8.8.8

# 4. FIREWALL & 1:1 NAT
#    Placeholders below are patched by the DHCP script in section 1.
#    Inbound flow: peer -> maskSubnet --NETMAP--> real LAN host,
#    source masqueraded so LAN hosts reply via this router without
#    needing a route back to the tunnel subnet.
/ip/firewall/filter add chain=input in-interface=wlan1 action=accept comment="Allow Management via WLAN"
/ip/firewall/filter add chain=input in-interface=wg-client action=accept comment="Allow WG Input"
/ip/firewall/filter add chain=forward in-interface=wg-client action=accept comment="Allow WG Forwarding to LAN"
# NETMAP needs to-addresses at creation: it starts disabled and the DHCP
# script fills in the real LAN subnet and enables it.
/ip/firewall/nat add chain=dstnat in-interface=wg-client dst-address=$maskSubnet action=netmap to-addresses=0.0.0.0 disabled=yes comment="Netmap: Disguise Inbound to LAN"
/ip/firewall/nat add chain=srcnat src-address=$peerSubnet action=masquerade comment="Masquerade: Inbound Peer to LAN"
/ip/firewall/nat add chain=srcnat out-interface=wg-client action=masquerade comment="Masquerade: Outbound VPN Traffic"

# 5. LED STATUS INDICATOR (on = tunnel up)
#    Pings the server's tunnel IP; "cap-led" exists on cAP-series boards.
/system/leds/set [find leds="cap-led"] type=off
/tool/netwatch/add host=$wgServerIp interval=10s up-script="/system/leds/set [find leds=\"cap-led\"] type=on" down-script="/system/leds/set [find leds=\"cap-led\"] type=off"

:log info "Deployment complete! Waiting for DHCP lease...";
}
