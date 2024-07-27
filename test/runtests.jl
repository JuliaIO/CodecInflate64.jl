using Test
using Random
using CodecInflate64
using Aqua: Aqua
using Pkg.Artifacts: @artifact_str, ensure_artifact_installed

Aqua.test_all(CodecInflate64)

Random.seed!(1234)

include("utils.jl")

include("tests_from_inflate.jl")

include("test_huffman.jl")

include("test_errors.jl")

@testset "Exercise Deflate64 distances and lengths" begin
    thing = rand(UInt8, 200)
    d = UInt8[]
    for dist in [0:258; 1000:1030; 2000:1000:33000; 34000:10000:100_000]
        append!(d, thing)
        append!(d, rand(0x00:0x0f, dist))
    end
    @test decompress(zlib_compress(d)) == d
    @test decompress(p7zip_compress(d)) == d
    @test decompress_bytes(zlib_compress(d)) == d
    @test decompress_bytes(p7zip_compress(d)) == d
    @test de64compress(p7zip_64compress(d)) == d
    @test de64compress_bytes(p7zip_64compress(d)) == d
    @test_throws DecompressionError de64compress(p7zip_64compress(d)[begin:end-1])

    for n_start in [0, 65536-100, 65536*3]
        for n in 65536-400:65536+400
            d = [zeros(UInt8, n_start); thing; zeros(UInt8, n); thing]
            @test de64compress(p7zip_64compress(d)) == d
            @test_throws DecompressionError de64compress(p7zip_64compress(d)[begin:end-1])
        end
    end

    for n in [0:1000; 1000000;]
        d = zeros(UInt8, n)
        @test decompress(zlib_compress(d)) == d
        @test decompress(p7zip_compress(d)) == d
        @test decompress_bytes(zlib_compress(d)) == d
        @test decompress_bytes(p7zip_compress(d)) == d
        @test de64compress(p7zip_64compress(d)) == d
        @test de64compress_bytes(p7zip_64compress(d)) == d
        @test_throws DecompressionError de64compress(p7zip_64compress(d)[begin:end-1])
    end
end

@testset "tests from ZipArchives.jl fixture" begin
    ensure_artifact_installed("ziparchives-jl", joinpath(@__DIR__,"Artifacts.toml"))
    fixture_dir = joinpath(artifact"ziparchives-jl", "fixture")
    for file in readdir(fixture_dir)
        checkcrc32_zipfile(joinpath(fixture_dir,file))
        checkcrc32_zipfile(joinpath(fixture_dir,file); bufsize=1)
    end
end

include("tests_from_deflate64-rs.jl")

include("test_ts.jl")