# dist — Distributed Systems Category

> Distributed coordination primitives for Tattva OS clusters.
> Consensus, gossip, RPC, and distributed execution.

---

## Projects

| Project | Description |
|---|---|
| [`uraft/`](uraft/) | Raft consensus implementation — leader election, log replication |
| [`uchord/`](uchord/) | Chord DHT — distributed hash table for cluster routing |
| [`umesh/`](umesh/) | Service mesh — inter-node communication fabric |
| [`urpc/`](urpc/) | Remote procedure calls over BXP binary protocol |
| [`udist/`](udist/) | Distributed task execution and work distribution |

---

## Philosophy

No Kubernetes. No Etcd. No Zookeeper.
Consensus runs in assembly at wire speed.
