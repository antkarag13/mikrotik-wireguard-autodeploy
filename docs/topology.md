# Topology

```mermaid
flowchart LR
    subgraph HQ["VPN server side"]
        S["WireGuard server<br/>vpn.example.com:51820<br/>tunnel IP 10.8.0.1"]
        A["Admin / other peers<br/>10.8.0.0/24"]
        A --- S
    end

    subgraph SITE["Remote site"]
        UP["Upstream router / ISP<br/>(DHCP server)"]
        MT["MikroTik (RouterOS v7+)<br/>ether1: DHCP client<br/>wg-client: 10.8.0.X/24"]
        LAN["Site LAN hosts<br/>e.g. 192.168.1.0/24<br/>(auto-detected)"]
        W["Management laptop (optional)<br/>hidden SSID on wlan1<br/>192.168.99.0/24"]
        UP --- MT
        UP --- LAN
        W -. "wlan1" .- MT
    end

    MT == "WireGuard tunnel<br/>(/32 bypass route to endpoint via upstream GW)" ==> S
```

## Inbound packet walk-through

A peer reaches LAN host `192.168.1.50` through the site's mask subnet `10.0.X.0/24`:

| Step | Where | Src | Dst |
|---|---|---|---|
| 1 | Peer sends into tunnel | `10.8.0.2` | `10.0.X.50` |
| 2 | dstnat NETMAP on `wg-client` | `10.8.0.2` | `192.168.1.50` |
| 3 | srcnat masquerade (`src 10.8.0.0/24`, `dst LAN`) | `192.168.1.Y` (router's ether1 IP) | `192.168.1.50` |
| 4 | Host replies to router, connection tracking reverses both NATs | | |

Because every site maps its LAN to its own unique mask subnet, two sites can both use
`192.168.1.0/24` and still be reached without conflict.
