# net — Networking Category

> Network stack for Tattva OS. Built for AI inference traffic.
> HTTP/3, zero-copy, kernel-bypass where possible.

---

## Projects

| Project | Description |
|---|---|
| [`unet/`](unet/) | Core network stack — Ethernet, IP, TCP, UDP |
| [`uhttp/`](uhttp/) | HTTP/3 server — QUIC transport, zero-copy body handling |
| [`udns/`](udns/) | DNS resolver — Nama integration, caching, DoH support |
| [`uSSH/`](uSSH/) | SSH server — remote access, key-based auth |
| [`urdma/`](urdma/) | RDMA — direct memory access for cluster inference |
| [`ugossip/`](ugossip/) | Gossip protocol — cluster membership and health |
| [`tools/`](tools/) | Network diagnostic tools — ping, trace, packet capture |
| [`tests/`](tests/) | Network stack tests |

---

## Philosophy

The network stack is the API surface.
Everything enters and exits through `uhttp` or `unet`.
No iptables. Firewall policy is `niti` — a separate project.
