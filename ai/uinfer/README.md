# ai/uinfer — Inference Engine

> The core inference engine. The heart of Tattva OS.

Orchestrates the full inference pipeline: tokenize → prefill → decode → detokenize.
Calls into `ai/kernels` for compute. Manages `ai/memory` for KV cache.

Part of the `ai/` category in Tattva OS.
