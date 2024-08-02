using CodecInflate64
using CodecZlib: DeflateCompressor, DeflateCompressorStream
using Random
using Test
using TranscodingStreams: TranscodingStream
using TestsForCodecPackages:
    test_roundtrip_read,
    test_roundtrip_write,
    test_roundtrip_transcode,
    test_roundtrip_lines,
    test_roundtrip_seekstart,
    test_roundtrip_fileio,
    test_chunked_read,
    test_chunked_write

@testset "Deflate Codec" begin

    codec = DeflateDecompressor()
    @test codec isa DeflateDecompressor
    @test occursin(r"^(CodecInflate64\.)?DeflateDecompressor\(\)$", sprint(show, codec))

    test_roundtrip_read(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_write(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_transcode(DeflateCompressor, DeflateDecompressor)
    test_roundtrip_lines(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_seekstart(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_fileio(DeflateCompressor, DeflateDecompressor)
    test_chunked_read(DeflateCompressor, DeflateDecompressor)
    test_chunked_write(DeflateCompressor, DeflateDecompressor)

    @test DeflateDecompressorStream <: TranscodingStream
end