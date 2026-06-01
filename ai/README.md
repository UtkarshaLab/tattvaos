# ai — Artificial Intelligence Category

> AI inference, training, and model execution infrastructure for Tattva OS.
> Everything needed to run language models and neural networks at bare-metal speed.

---

## Projects

| Project | Description |
|---|---|
| [`decode/`](decode/) | Token decoding and sampling strategies (greedy, top-k, top-p, temperature) |
| [`distributed/`](distributed/) | Multi-node inference coordination and tensor parallelism |
| [`formats/`](formats/) | Model file format parsers — GGUF, SafeTensors, ONNX |
| [`kernels/`](kernels/) | Hand-written SIMD compute kernels — matmul, attention, FFN |
| [`memory/`](memory/) | KV cache management, weight loading, activation buffers |
| [`models/`](models/) | Model architecture definitions — LLaMA, Mistral, custom |
| [`tokenize/`](tokenize/) | Tokenizer implementations — BPE, SentencePiece |
| [`ubatch/`](ubatch/) | Continuous batching and request scheduling |
| [`uinfer/`](uinfer/) | Main inference engine — the core runtime |
| [`umodel/`](umodel/) | Model loading, validation, and lifecycle management |
| [`uoptim/`](uoptim/) | Quantization, pruning, and model optimization |
| [`utrain/`](utrain/) | Fine-tuning and training loop infrastructure |

---

## Philosophy

No Python. No framework dispatch. No CUDA runtime overhead.
Compute goes directly from model weights to hardware registers.
