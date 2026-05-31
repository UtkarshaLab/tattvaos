ufile/
├── arch/
│   ├── common/
│   │   ├── macros.inc
│   │   ├── error.inc
│   │   ├── types.inc
│   │   └── utf8.inc
│   ├── aarch64/
│   │   ├── entry.s
│   │   ├── syscall.s
│   │   ├── string.s
│   │   ├── file.s
│   │   └── simd/
│   │       ├── scan.s
│   │       └── utf8.s
│   ├── x86_64/
│   │   ├── entry.s
│   │   ├── syscall.s
│   │   ├── string.s
│   │   ├── file.s
│   │   └── simd/
│   │       ├── scan.s
│   │       ├── utf8.s
│   │       └── avx512.s
│   └── riscv/
│       ├── entry.s
│       ├── syscall.s
│       ├── string.s
│       ├── file.s
│       └── simd/
│           ├── scan.s
│           └── utf8.s
│
├── detect/
│   ├── detect.s           ← main entry, orchestrates all detectors
│   ├── magic.s            ← magic byte table engine
│   ├── fallback.s         ← text heuristics when magic fails
│   ├── confidence.s       ← confidence scoring across detectors
│   └── mime.s             ← format → MIME type mapping
│
├── formats/
│   ├── text/
│   │   ├── txt.s
│   │   ├── markdown.s
│   │   ├── rst.s
│   │   ├── asciidoc.s
│   │   ├── latex.s
│   │   ├── html.s
│   │   └── rtf.s
│   ├── config/
│   │   ├── toml.s
│   │   ├── yaml.s
│   │   ├── ini.s
│   │   ├── dotenv.s
│   │   ├── hcl.s
│   │   ├── kdl.s
│   │   ├── nginx.s
│   │   └── systemd.s
│   ├── data/
│   │   ├── json.s
│   │   ├── jsonl.s
│   │   ├── xml.s
│   │   ├── csv.s
│   │   ├── tsv.s
│   │   ├── msgpack.s
│   │   ├── cbor.s
│   │   ├── protobuf.s
│   │   ├── bson.s
│   │   ├── flatbuffers.s
│   │   └── bxp.s
│   ├── office/
│   │   ├── docx.s
│   │   ├── odt.s
│   │   ├── xlsx.s
│   │   ├── ods.s
│   │   ├── pptx.s
│   │   ├── odp.s
│   │   └── pdf.s
│   ├── media/
│   │   ├── image/
│   │   │   ├── jpeg.s
│   │   │   ├── png.s
│   │   │   ├── webp.s
│   │   │   ├── gif.s
│   │   │   ├── avif.s
│   │   │   └── svg.s
│   │   ├── audio/
│   │   │   ├── mp3.s
│   │   │   ├── flac.s
│   │   │   ├── ogg.s
│   │   │   └── wav.s
│   │   └── video/
│   │       ├── mp4.s
│   │       ├── mkv.s
│   │       └── webm.s
│   ├── archive/
│   │   ├── zip.s
│   │   ├── tar.s
│   │   ├── gz.s
│   │   ├── zst.s
│   │   ├── xz.s
│   │   ├── bz2.s
│   │   └── sevenz.s
│   ├── binary/
│   │   ├── elf.s
│   │   ├── pe.s
│   │   ├── macho.s
│   │   └── wasm.s
│   ├── font/
│   │   ├── ttf.s
│   │   ├── otf.s
│   │   ├── woff.s
│   │   ├── woff2.s
│   │   ├── bdf.s
│   │   └── psf2.s
│   └── dev/
│       ├── makefile.s
│       ├── dockerfile.s
│       ├── gitconfig.s
│       ├── gitignore.s
│       └── sshconfig.s
│
├── meta/
│   ├── meta.s             ← ufile_meta_t population orchestrator
│   ├── text_meta.s        ← encoding, line endings, line count, BOM
│   ├── image_meta.s       ← width, height, color space, bit depth
│   ├── audio_meta.s       ← sample rate, channels, bitrate, duration
│   ├── video_meta.s       ← resolution, fps, codec, duration
│   ├── archive_meta.s     ← entry count, compression ratio, total size
│   ├── binary_meta.s      ← arch, bits, endianness, entry point
│   ├── font_meta.s        ← family, style, glyph count, format version
│   ├── office_meta.s      ← title, author, page/sheet count, created date
│   └── exif.s             ← EXIF/XMP extraction for images
│
├── mem/
│   ├── arena.s
│   ├── alloc.s
│   └── align.s
│
├── include/
│   └── ufile.h
│
├── bindings/
│   └── rust/
│       ├── Cargo.toml
│       ├── build.rs
│       ├── src/
│       │   ├── lib.rs
│       │   ├── sys.rs
│       │   ├── error.rs
│       │   ├── detect.rs
│       │   ├── meta.rs
│       │   └── format.rs
│       └── tests/
│           └── integration.rs
│
├── tests/
│   ├── unit/
│   │   ├── arch/
│   │   │   ├── aarch64/
│   │   │   │   ├── string_test.s
│   │   │   │   ├── utf8_test.s
│   │   │   │   └── syscall_test.s
│   │   │   ├── x86_64/
│   │   │   │   ├── string_test.s
│   │   │   │   ├── utf8_test.s
│   │   │   │   └── syscall_test.s
│   │   │   └── riscv/
│   │   │       ├── string_test.s
│   │   │       ├── utf8_test.s
│   │   │       └── syscall_test.s
│   │   ├── detect/
│   │   │   ├── magic_test.s
│   │   │   ├── fallback_test.s
│   │   │   ├── confidence_test.s
│   │   │   └── mime_test.s
│   │   ├── formats/
│   │   │   ├── text/
│   │   │   │   ├── txt_test.s
│   │   │   │   ├── markdown_test.s
│   │   │   │   ├── rst_test.s
│   │   │   │   ├── asciidoc_test.s
│   │   │   │   ├── latex_test.s
│   │   │   │   ├── html_test.s
│   │   │   │   └── rtf_test.s
│   │   │   ├── config/
│   │   │   │   ├── toml_test.s
│   │   │   │   ├── yaml_test.s
│   │   │   │   ├── ini_test.s
│   │   │   │   ├── dotenv_test.s
│   │   │   │   ├── hcl_test.s
│   │   │   │   ├── kdl_test.s
│   │   │   │   ├── nginx_test.s
│   │   │   │   └── systemd_test.s
│   │   │   ├── data/
│   │   │   │   ├── json_test.s
│   │   │   │   ├── jsonl_test.s
│   │   │   │   ├── xml_test.s
│   │   │   │   ├── csv_test.s
│   │   │   │   ├── tsv_test.s
│   │   │   │   ├── msgpack_test.s
│   │   │   │   ├── cbor_test.s
│   │   │   │   ├── protobuf_test.s
│   │   │   │   ├── bson_test.s
│   │   │   │   ├── flatbuffers_test.s
│   │   │   │   └── bxp_test.s
│   │   │   ├── office/
│   │   │   │   ├── docx_test.s
│   │   │   │   ├── odt_test.s
│   │   │   │   ├── xlsx_test.s
│   │   │   │   ├── ods_test.s
│   │   │   │   ├── pptx_test.s
│   │   │   │   ├── odp_test.s
│   │   │   │   └── pdf_test.s
│   │   │   ├── media/
│   │   │   │   ├── image/
│   │   │   │   │   ├── jpeg_test.s
│   │   │   │   │   ├── png_test.s
│   │   │   │   │   ├── webp_test.s
│   │   │   │   │   ├── gif_test.s
│   │   │   │   │   ├── avif_test.s
│   │   │   │   │   └── svg_test.s
│   │   │   │   ├── audio/
│   │   │   │   │   ├── mp3_test.s
│   │   │   │   │   ├── flac_test.s
│   │   │   │   │   ├── ogg_test.s
│   │   │   │   │   └── wav_test.s
│   │   │   │   └── video/
│   │   │   │       ├── mp4_test.s
│   │   │   │       ├── mkv_test.s
│   │   │   │       └── webm_test.s
│   │   │   ├── archive/
│   │   │   │   ├── zip_test.s
│   │   │   │   ├── tar_test.s
│   │   │   │   ├── gz_test.s
│   │   │   │   ├── zst_test.s
│   │   │   │   ├── xz_test.s
│   │   │   │   ├── bz2_test.s
│   │   │   │   └── sevenz_test.s
│   │   │   ├── binary/
│   │   │   │   ├── elf_test.s
│   │   │   │   ├── pe_test.s
│   │   │   │   ├── macho_test.s
│   │   │   │   └── wasm_test.s
│   │   │   ├── font/
│   │   │   │   ├── ttf_test.s
│   │   │   │   ├── otf_test.s
│   │   │   │   ├── woff_test.s
│   │   │   │   ├── woff2_test.s
│   │   │   │   ├── bdf_test.s
│   │   │   │   └── psf2_test.s
│   │   │   └── dev/
│   │   │       ├── makefile_test.s
│   │   │       ├── dockerfile_test.s
│   │   │       ├── gitconfig_test.s
│   │   │       ├── gitignore_test.s
│   │   │       └── sshconfig_test.s
│   │   ├── meta/
│   │   │   ├── text_meta_test.s
│   │   │   ├── image_meta_test.s
│   │   │   ├── audio_meta_test.s
│   │   │   ├── video_meta_test.s
│   │   │   ├── archive_meta_test.s
│   │   │   ├── binary_meta_test.s
│   │   │   ├── font_meta_test.s
│   │   │   ├── office_meta_test.s
│   │   │   └── exif_test.s
│   │   └── mem/
│   │       ├── arena_test.s
│   │       ├── alloc_test.s
│   │       └── align_test.s
│   ├── integration/
│   │   ├── detect_pipeline_test.s
│   │   ├── meta_pipeline_test.s
│   │   ├── ambiguous_format_test.s
│   │   ├── corrupt_file_test.s
│   │   ├── empty_file_test.s
│   │   ├── large_file_test.s
│   │   └── mime_mapping_test.s
│   └── conformance/
│       ├── run.sh
│       ├── samples/
│       └── expected/
│
├── bench/
│   ├── micro/
│   │   ├── magic_scan_bench.s
│   │   ├── utf8_detect_bench.s
│   │   ├── confidence_bench.s
│   │   ├── exif_bench.s
│   │   └── mem_arena_bench.s
│   └── macro/
│       ├── detect_1k_files_bench.s
│       ├── detect_mixed_formats_bench.s
│       ├── meta_images_bench.s
│       ├── meta_audio_bench.s
│       └── cold_start_bench.s
│
├── docs/
│   ├── spec/
│   │   ├── magic_bytes.md
│   │   ├── confidence_scoring.md
│   │   ├── mime_types.md
│   │   └── format_coverage.md
│   ├── api/
│   │   ├── ufile_h.md
│   │   └── rust_bindings.md
│   └── internals/
│       ├── architecture.md
│       ├── memory_model.md
│       ├── simd_strategy.md
│       ├── detection_algorithm.md
│       ├── metadata_extraction.md
│       ├── build_system.md
│       └── phase_roadmap.md
│
├── examples/
│   ├── c/
│   │   ├── detect_file.c
│   │   ├── image_meta.c
│   │   ├── audio_meta.c
│   │   ├── batch_detect.c
│   │   └── arena_usage.c
│   └── rust/
│       ├── detect_file.rs
│       ├── image_meta.rs
│       ├── audio_meta.rs
│       └── batch_detect.rs
│
├── scripts/
│   ├── run_tests.sh
│   ├── run_bench.sh
│   └── gen_bindings.sh
│
├── third_party/
│   ├── samples/
│   └── specs/
│       ├── magic_db.md
│       ├── exif_spec.md
│       ├── id3_spec.md
│       ├── elf_spec.md
│       ├── pe_spec.md
│       └── macho_spec.md
│
├── Makefile
├── build.sh
├── README.md
├── CHANGELOG.md
├── LICENSE
├── CONTRIBUTING.md
└── .gitignore