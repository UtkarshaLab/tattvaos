# serve — Inference Serving Category

> The inference serving layer for Tattva OS.
> Accepts requests, routes to the engine, streams responses.

---

## Projects

| Project | Description |
|---|---|
| [`userve/`](userve/) | Core serving engine — request lifecycle, response streaming |
| [`ugate/`](ugate/) | API gateway — routing, rate limiting, request validation |
| [`ulb/`](ulb/) | Load balancer — distributes requests across inference workers |
| [`uauth/`](uauth/) | Authentication — API keys, JWT, token validation |
| [`uaudit/`](uaudit/) | Audit log — request logging, compliance, tracing |
| [`ustream/`](ustream/) | SSE / streaming response support for token-by-token output |
| [`uopenai/`](uopenai/) | OpenAI-compatible API surface — `/v1/chat/completions` etc. |
| [`uembedding/`](uembedding/) | Embedding endpoint — vector generation for RAG |
| [`urerank/`](urerank/) | Reranking endpoint — cross-encoder scoring |
| [`niti/`](niti/) | Firewall — inbound request filtering, IP policy |

---

## Philosophy

The serving layer is thin. It routes requests and streams tokens.
All heavy lifting happens in `ai/uinfer`.
