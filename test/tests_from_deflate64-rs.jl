using Pkg.Artifacts: @artifact_str, ensure_artifact_installed

# These tests are ported from https://github.com/anatawa12/deflate64-rs/releases/tag/v0.1.9

include("utils.jl")


@testset "tests from deflate64-rs" begin
    ensure_artifact_installed("deflate64-rs", joinpath(@__DIR__,"Artifacts.toml"))
    test_assets = joinpath(artifact"deflate64-rs", "deflate64-rs-0.1.9", "test-assets")
    checkcrc32_zipfile(joinpath(test_assets,"deflate64.zip"))
    checkcrc32_zipfile(joinpath(test_assets,"deflate64.zip"); bufsize=1)

    u = read(joinpath(test_assets,"issue-13/logo.png"))
    c = read(joinpath(test_assets,"issue-13/unitwf-1.5.0.minimized.zip"))[1183:1182+34919]
    @test de64compress(c) == u

    c = read(joinpath(test_assets,"issue-23/raw_deflate64_index_out_of_bounds"))
    @test_throws DecompressionError("incomplete code table") de64compress(c)

    c = read(joinpath(test_assets,"issue-25/deflate64_not_enough_space.zip"))[31:end]
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(c)

    c = read(joinpath(test_assets,"issue-29/raw.zip"))[122:end]
    @test_throws DecompressionError("incomplete code table") de64compress(c)

    c = read(joinpath(test_assets,"deflate64.zip"))[41:40+2669743]
    stream = Deflate64DecompressorStream(IOBuffer(c))
    u = UInt8[]
    read!(stream, u)
    @test u == UInt8[]
    @test read(stream) == read(joinpath(test_assets,"folder/binary.wmv"))
end
