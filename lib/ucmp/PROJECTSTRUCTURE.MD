ucmp/
├── arch/
│   ├── common/
│   │   ├── macros.inc
│   │   ├── error.inc
│   │   ├── types.inc
│   │   └── bitops.inc        ← bit manipulation macros (shifts, rotates)
│   ├── aarch64/
│   │   ├── entry.s
│   │   ├── syscall.s
│   │   ├── string.s
│   │   └── simd/
│   │       ├── crc32.s       ← NEON CRC32 hardware acceleration
│   │       ├── adler32.s     ← NEON Adler32
│   │       ├── xxhash.s      ← NEON xxHash
│   │       └── scan.s        ← NEON byte scanning
│   ├── x86_64/
│   │   ├── entry.s
│   │   ├── syscall.s
│   │   ├── string.s
│   │   └── simd/
│   │       ├── crc32.s       ← SSE4.2 CRC32 instruction
│   │       ├── adler32.s     ← AVX2 Adler32
│   │       ├── xxhash.s      ← AVX2 xxHash
│   │       ├── scan.s        ← AVX2 byte scanning
│   │       └── avx512.s      ← AVX512 hot paths
│   └── riscv/
│       ├── entry.s
│       ├── syscall.s
│       ├── string.s
│       └── simd/
│           ├── crc32.s
│           ├── adler32.s
│           ├── xxhash.s
│           └── scan.s
│
├── core/
│   ├── stream.s              ← streaming compress/decompress abstraction
│   ├── buffer.s              ← sliding window buffer management
│   ├── bitstream.s           ← bit-level read/write (deflate needs this)
│   ├── huffman.s             ← huffman tree build/encode/decode
│   ├── lz77.s                ← base LZ77 match finding
│   ├── matchfinder.s         ← hash chain + binary tree match finder
│   └── entropy.s             ← entropy coding primitives (ANS/FSE)
│
├── algo/
│   ├── deflate/
│   │   ├── deflate.s         ← deflate compressor
│   │   ├── inflate.s         ← deflate decompressor
│   │   ├── huffman_static.s  ← static huffman trees
│   │   ├── huffman_dynamic.s ← dynamic huffman trees
│   │   └── window.s          ← 32KB sliding window
│   ├── zlib/
│   │   ├── zlib.s            ← zlib wrapper over deflate
│   │   ├── header.s          ← zlib header read/write
│   │   └── adler32.s         ← zlib checksum
│   ├── gzip/
│   │   ├── gzip.s            ← gzip wrapper over deflate
│   │   ├── header.s          ← gzip header read/write
│   │   └── crc32.s           ← gzip checksum
│   ├── zstd/
│   │   ├── zstd.s            ← zstd compressor entry
│   │   ├── zstd_decomp.s     ← zstd decompressor entry
│   │   ├── frame.s           ← zstd frame format
│   │   ├── block.s           ← zstd block types (raw/rle/compressed)
│   │   ├── fse.s             ← finite state entropy coding
│   │   ├── huf.s             ← huffman coding (zstd variant)
│   │   ├── sequences.s       ← literal/match sequence coding
│   │   ├── dict.s            ← zstd dictionary support
│   │   └── xxhash.s          ← zstd checksum
│   ├── lz4/
│   │   ├── lz4.s             ← lz4 compressor
│   │   ├── lz4_decomp.s      ← lz4 decompressor
│   │   ├── lz4hc.s           ← lz4 high compression
│   │   ├── frame.s           ← lz4 frame format
│   │   └── xxhash.s          ← lz4 checksum
│   ├── lzma/
│   │   ├── lzma.s            ← lzma compressor
│   │   ├── lzma_decomp.s     ← lzma decompressor
│   │   ├── range_enc.s       ← range encoder
│   │   ├── range_dec.s       ← range decoder
│   │   ├── lz.s              ← lz match finding
│   │   └── literals.s        ← literal coding
│   ├── xz/
│   │   ├── xz.s              ← xz wrapper over lzma2
│   │   ├── stream.s          ← xz stream format
│   │   ├── block.s           ← xz block format
│   │   ├── index.s           ← xz index
│   │   ├── header.s          ← xz stream header/footer
│   │   └── crc64.s           ← xz checksum
│   ├── brotli/
│   │   ├── brotli.s          ← brotli compressor
│   │   ├── brotli_decomp.s   ← brotli decompressor
│   │   ├── prefix.s          ← prefix codes
│   │   ├── context.s         ← context modeling
│   │   ├── metablock.s       ← metablock format
│   │   ├── transform.s       ← word transforms
│   │   └── dictionary.s      ← brotli static dictionary
│   ├── bzip2/
│   │   ├── bzip2.s           ← bzip2 compressor
│   │   ├── bzip2_decomp.s    ← bzip2 decompressor
│   │   ├── bwt.s             ← Burrows-Wheeler transform
│   │   ├── mtf.s             ← move-to-front transform
│   │   ├── rle.s             ← run-length encoding
│   │   └── huffman.s         ← bzip2 huffman coding
│   ├── snappy/
│   │   ├── snappy.s          ← snappy compressor
│   │   ├── snappy_decomp.s   ← snappy decompressor
│   │   └── varint.s          ← snappy varint encoding
│   ├── lzo/
│   │   ├── lzo.s             ← lzo compressor
│   │   └── lzo_decomp.s      ← lzo decompressor
│   ├── zopfli/
│   │   ├── zopfli.s          ← zopfli deflate optimizer
│   │   ├── blocksplitter.s   ← optimal block splitting
│   │   ├── squeeze.s         ← optimal match finding
│   │   └── cache.s           ← match cache
│   ├── lzss/
│   │   ├── lzss.s            ← lzss compressor
│   │   └── lzss_decomp.s     ← lzss decompressor
│   └── compress_z/
│       ├── compress.s        ← .Z compressor (LZW)
│       └── uncompress.s      ← .Z decompressor
│
├── checksum/
│   ├── crc32.s               ← CRC32 (gzip, ZIP)
│   ├── crc64.s               ← CRC64 (xz)
│   ├── adler32.s             ← Adler32 (zlib)
│   ├── xxhash32.s            ← xxHash32 (lz4)
│   ├── xxhash64.s            ← xxHash64 (zstd)
│   └── xxhash3.s             ← xxHash3 (zstd modern)
│
├── dict/
│   ├── zstd_dict.s           ← zstd dictionary training + loading
│   ├── brotli_dict.s         ← brotli static dictionary tables
│   └── dict_common.s         ← shared dictionary primitives
│
├── mem/
│   ├── arena.s
│   ├── alloc.s
│   ├── pool.s
│   └── align.s
│
├── include/
│   └── ucmp.h
│
├── bindings/
│   └── rust/
│       ├── Cargo.toml
│       ├── build.rs
│       ├── src/
│       │   ├── lib.rs
│       │   ├── sys.rs
│       │   ├── error.rs
│       │   ├── compress.rs
│       │   ├── decompress.rs
│       │   ├── stream.rs
│       │   ├── dict.rs
│       │   └── checksum.rs
│       └── tests/
│           └── integration.rs
│
├── tests/
│   ├── unit/
│   │   ├── arch/
│   │   │   ├── aarch64/
│   │   │   │   ├── crc32_test.s
│   │   │   │   ├── adler32_test.s
│   │   │   │   └── xxhash_test.s
│   │   │   ├── x86_64/
│   │   │   │   ├── crc32_test.s
│   │   │   │   ├── adler32_test.s
│   │   │   │   └── xxhash_test.s
│   │   │   └── riscv/
│   │   │       ├── crc32_test.s
│   │   │       ├── adler32_test.s
│   │   │       └── xxhash_test.s
│   │   ├── core/
│   │   │   ├── stream_test.s
│   │   │   ├── buffer_test.s
│   │   │   ├── bitstream_test.s
│   │   │   ├── huffman_test.s
│   │   │   ├── lz77_test.s
│   │   │   ├── matchfinder_test.s
│   │   │   └── entropy_test.s
│   │   ├── algo/
│   │   │   ├── deflate/
│   │   │   │   ├── deflate_test.s
│   │   │   │   ├── inflate_test.s
│   │   │   │   ├── huffman_static_test.s
│   │   │   │   ├── huffman_dynamic_test.s
│   │   │   │   └── window_test.s
│   │   │   ├── zlib/
│   │   │   │   ├── zlib_test.s
│   │   │   │   ├── header_test.s
│   │   │   │   └── adler32_test.s
│   │   │   ├── gzip/
│   │   │   │   ├── gzip_test.s
│   │   │   │   ├── header_test.s
│   │   │   │   └── crc32_test.s
│   │   │   ├── zstd/
│   │   │   │   ├── zstd_test.s
│   │   │   │   ├── zstd_decomp_test.s
│   │   │   │   ├── frame_test.s
│   │   │   │   ├── block_test.s
│   │   │   │   ├── fse_test.s
│   │   │   │   ├── huf_test.s
│   │   │   │   ├── sequences_test.s
│   │   │   │   └── dict_test.s
│   │   │   ├── lz4/
│   │   │   │   ├── lz4_test.s
│   │   │   │   ├── lz4_decomp_test.s
│   │   │   │   ├── lz4hc_test.s
│   │   │   │   └── frame_test.s
│   │   │   ├── lzma/
│   │   │   │   ├── lzma_test.s
│   │   │   │   ├── lzma_decomp_test.s
│   │   │   │   ├── range_enc_test.s
│   │   │   │   ├── range_dec_test.s
│   │   │   │   ├── lz_test.s
│   │   │   │   └── literals_test.s
│   │   │   ├── xz/
│   │   │   │   ├── xz_test.s
│   │   │   │   ├── stream_test.s
│   │   │   │   ├── block_test.s
│   │   │   │   ├── index_test.s
│   │   │   │   ├── header_test.s
│   │   │   │   └── crc64_test.s
│   │   │   ├── brotli/
│   │   │   │   ├── brotli_test.s
│   │   │   │   ├── brotli_decomp_test.s
│   │   │   │   ├── prefix_test.s
│   │   │   │   ├── context_test.s
│   │   │   │   ├── metablock_test.s
│   │   │   │   ├── transform_test.s
│   │   │   │   └── dictionary_test.s
│   │   │   ├── bzip2/
│   │   │   │   ├── bzip2_test.s
│   │   │   │   ├── bzip2_decomp_test.s
│   │   │   │   ├── bwt_test.s
│   │   │   │   ├── mtf_test.s
│   │   │   │   ├── rle_test.s
│   │   │   │   └── huffman_test.s
│   │   │   ├── snappy/
│   │   │   │   ├── snappy_test.s
│   │   │   │   ├── snappy_decomp_test.s
│   │   │   │   └── varint_test.s
│   │   │   ├── lzo/
│   │   │   │   ├── lzo_test.s
│   │   │   │   └── lzo_decomp_test.s
│   │   │   ├── zopfli/
│   │   │   │   ├── zopfli_test.s
│   │   │   │   ├── blocksplitter_test.s
│   │   │   │   ├── squeeze_test.s
│   │   │   │   └── cache_test.s
│   │   │   ├── lzss/
│   │   │   │   ├── lzss_test.s
│   │   │   │   └── lzss_decomp_test.s
│   │   │   └── compress_z/
│   │   │       ├── compress_test.s
│   │   │       └── uncompress_test.s
│   │   ├── checksum/
│   │   │   ├── crc32_test.s
│   │   │   ├── crc64_test.s
│   │   │   ├── adler32_test.s
│   │   │   ├── xxhash32_test.s
│   │   │   ├── xxhash64_test.s
│   │   │   └── xxhash3_test.s
│   │   ├── dict/
│   │   │   ├── zstd_dict_test.s
│   │   │   ├── brotli_dict_test.s
│   │   │   └── dict_common_test.s
│   │   └── mem/
│   │       ├── arena_test.s
│   │       ├── alloc_test.s
│   │       ├── pool_test.s
│   │       └── align_test.s
│   ├── integration/
│   │   ├── roundtrip_test.s          ← compress → decompress → verify
│   │   ├── streaming_test.s          ← streaming compress/decompress
│   │   ├── dict_roundtrip_test.s     ← dictionary compress/decompress
│   │   ├── checksum_verify_test.s    ← checksum correctness
│   │   ├── corrupt_input_test.s      ← handle corrupt data gracefully
│   │   ├── empty_input_test.s        ← edge case: empty input
│   │   ├── large_input_test.s        ← multi-GB streams
│   │   ├── cross_algo_test.s         ← compare ratios across algorithms
│   │   └── interop_test.s            ← verify against reference impls
│   └── conformance/
│       ├── run.sh
│       ├── samples/
│       └── expected/
│
├── bench/
│   ├── micro/
│   │   ├── crc32_bench.s
│   │   ├── adler32_bench.s
│   │   ├── xxhash_bench.s
│   │   ├── huffman_bench.s
│   │   ├── matchfinder_bench.s
│   │   ├── fse_bench.s
│   │   └── mem_arena_bench.s
│   └── macro/
│       ├── deflate_bench.s
│       ├── zlib_bench.s
│       ├── gzip_bench.s
│       ├── zstd_bench.s
│       ├── lz4_bench.s
│       ├── lzma_bench.s
│       ├── xz_bench.s
│       ├── brotli_bench.s
│       ├── bzip2_bench.s
│       ├── snappy_bench.s
│       ├── lzo_bench.s
│       ├── ratio_comparison_bench.s  ← all algos, same input, compare ratio
│       └── speed_comparison_bench.s  ← all algos, same input, compare speed
│
├── docs/
│   ├── spec/
│   │   ├── deflate_spec.md
│   │   ├── zlib_spec.md
│   │   ├── gzip_spec.md
│   │   ├── zstd_spec.md
│   │   ├── lz4_spec.md
│   │   ├── lzma_spec.md
│   │   ├── xz_spec.md
│   │   ├── brotli_spec.md
│   │   ├── bzip2_spec.md
│   │   ├── snappy_spec.md
│   │   ├── lzo_spec.md
│   │   ├── zopfli_spec.md
│   │   └── checksum_spec.md
│   ├── api/
│   │   ├── ucmp_h.md
│   │   └── rust_bindings.md
│   └── internals/
│       ├── architecture.md
│       ├── memory_model.md
│       ├── simd_strategy.md
│       ├── build_system.md
│       ├── algorithm_comparison.md
│       ├── dictionary_training.md
│       └── phase_roadmap.md
│
├── examples/
│   ├── c/
│   │   ├── compress_file.c
│   │   ├── decompress_file.c
│   │   ├── streaming_compress.c
│   │   ├── dict_compress.c
│   │   ├── checksum.c
│   │   └── arena_usage.c
│   └── rust/
│       ├── compress_file.rs
│       ├── decompress_file.rs
│       ├── streaming_compress.rs
│       ├── dict_compress.rs
│       └── checksum.rs
│
├── scripts/
│   ├── run_tests.sh
│   ├── run_bench.sh
│   └── gen_bindings.sh
│
├── third_party/
│   ├── samples/
│   └── specs/
│       ├── rfc1950_zlib.md
│       ├── rfc1951_deflate.md
│       ├── rfc1952_gzip.md
│       ├── rfc7932_brotli.md
│       ├── zstd_spec.md
│       ├── lz4_spec.md
│       └── xz_spec.md
│
├── Makefile
├── build.sh
├── README.md
├── CHANGELOG.md
├── LICENSE
├── CONTRIBUTING.md
└── .gitignore