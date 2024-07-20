using CodecInflate64
using CodecZlib: DeflateCompressor, DeflateCompressorStream
using Random
using Test
import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    test_roundtrip_read,
    test_roundtrip_write,
    test_roundtrip_lines,
    test_roundtrip_transcode

@testset "Deflate Codec" begin

    codec = DeflateDecompressor()
    @test codec isa DeflateDecompressor
    @test occursin(r"^(CodecInflate64\.)?DeflateDecompressor\(\)$", sprint(show, codec))

    test_roundtrip_read(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_write(DeflateCompressorStream, DeflateDecompressorStream)
    test_roundtrip_lines(DeflateCompressorStream, DeflateDecompressorStream)
    if isdefined(TranscodingStreams, :test_roundtrip_seekstart)
        TranscodingStreams.test_roundtrip_seekstart(DeflateCompressorStream, DeflateDecompressorStream)
    end
    test_roundtrip_transcode(DeflateCompressor, DeflateDecompressor)

    @test DeflateDecompressorStream <: TranscodingStream
end