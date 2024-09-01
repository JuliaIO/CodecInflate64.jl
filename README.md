# CodecInflate64.jl

[![CI](https://github.com/nhz2/CodecInflate64.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/nhz2/CodecInflate64.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/nhz2/CodecInflate64.jl/branch/main/graph/badge.svg?token=K3J0T9BZ42)](https://codecov.io/gh/nhz2/CodecInflate64.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

CodecInflate64 implements deflate64 decompression for the [TranscodingStream.jl](https://github.com/JuliaIO/TranscodingStreams.jl) interface.

This package aims to read entries of ZIP files created by the default Windows File Explorer.

Deflate64 is an incompatible variant of deflate that Windows File Explorer sometimes uses when making ZIP files.

The deflate algorithm is described in [RFC 1951](https://www.ietf.org/rfc/rfc1951.txt).

Deflate64 has a reference implementation in [dotnet](https://github.com/dotnet/runtime/tree/e5efd8010e19593298dc2c3ee15106d5aec5a924/src/libraries/System.IO.Compression/src/System/IO/Compression/DeflateManaged)

It is also described unofficially in https://libzip.org/specifications/appnote_iz.txt

Some of the code from [Inflate.jl](https://github.com/GunnarFarneback/Inflate.jl) is used here, but modified to work with deflate64.

This package exports the following codecs and streams:

| Codec                   | Stream                        |
| ----------------------- | ----------------------------- |
| `DeflateDecompressor`   | `DeflateDecompressorStream`   |
| `Deflate64Decompressor` | `Deflate64DecompressorStream` |

See [TranscodingStreams.jl](https://github.com/bicycle1885/TranscodingStreams.jl) for details.

Related packages in other programming languages:
- Rust: https://github.com/anatawa12/deflate64-rs
- Python: https://github.com/brianhelba/zipfile-deflate64
