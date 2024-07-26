#=
These tests are ported from [Inflate.jl](https://github.com/GunnarFarneback/Inflate.jl)

Inflate.jl is licensed under MIT License:
> Copyright (c) 2013, 2018: Gunnar Farnebäck.
>
> Permission is hereby granted, free of charge, to any person
> obtaining a copy of this software and associated documentation files
> (the "Software"), to deal in the Software without restriction,
> including without limitation the rights to use, copy, modify, merge,
> publish, distribute, sublicense, and/or sell copies of the Software,
> and to permit persons to whom the Software is furnished to do so,
> subject to the following conditions:
>
> The above copyright notice and this permission notice shall be
> included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
> EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
> MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
> BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
> ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
> CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
=#

empty_string = ""
short_string = "This is a short string."
medium_string = read(pathof(CodecInflate64), String)
long_string = join(fill(medium_string, 1000), short_string)

@testset "Text strings" begin
    for s in [empty_string, short_string, medium_string, long_string]
        d = collect(codeunits(s))
        @test decompress(zlib_compress(d)) == d
        @test decompress(p7zip_compress(d)) == d
        @test decompress_bytes(zlib_compress(d)) == d
        @test decompress_bytes(p7zip_compress(d)) == d
        @test de64compress(p7zip_64compress(d)) == d
        @test de64compress_bytes(p7zip_64compress(d)) == d
    end
end

@testset "Incompressible data" begin
    Random.seed!(1)
    for n in [0, 1, 10, 100, 1000, 10000, 100000, 1000000]
        d = rand(UInt8, n)
        @test decompress(zlib_compress(d)) == d
        @test decompress(p7zip_compress(d)) == d
        @test decompress_bytes(zlib_compress(d)) == d
        @test decompress_bytes(p7zip_compress(d)) == d
        @test de64compress(p7zip_64compress(d)) == d
        @test de64compress_bytes(p7zip_64compress(d)) == d
    end
end

@testset "Huffman compressible data" begin
    Random.seed!(1)
    for n in [0, 1, 10, 100, 1000, 10000, 100000, 1000000]
        d = rand(UInt8, n) .& 0x0f
        @test decompress(zlib_compress(d)) == d
        @test decompress(p7zip_compress(d)) == d
        @test decompress_bytes(zlib_compress(d)) == d
        @test decompress_bytes(p7zip_compress(d)) == d
        @test de64compress(p7zip_64compress(d)) == d
        @test de64compress_bytes(p7zip_64compress(d)) == d
    end
end

# Deflate compression of empty string.
empty_deflate = [0x03, 0x00]

@testset "Empty messages" begin
    @test decompress(empty_deflate) == UInt8[]
    @test de64compress(empty_deflate) == UInt8[]
    @test de64compress_bytes(empty_deflate) == UInt8[]
end

@testset "Deflate corruption" begin
    d1 = UInt8[0x01, 0x00, 0x00, 0x00, 0x00] # corrupted compression mode 0 data
    d2 = UInt8[0x07]                         # invalid compression mode 3
    d3 = UInt8[0xed, 0x1c, 0xed, 0x72,
               0xdb, 0x48, 0xf2, 0x3f]       # incomplete code table
    for d in [d1, d2, d3]
        @test_throws DecompressionError decompress(d)
        @test_throws DecompressionError decompress_bytes(d)
        @test_throws DecompressionError de64compress(d)
        @test_throws DecompressionError de64compress_bytes(d)
    end
end

@testset "Reading past end of file" begin
    s1 = DeflateDecompressorStream(IOBuffer(empty_deflate))
    s2 = Deflate64DecompressorStream(IOBuffer(empty_deflate))
    for s in [s1, s2]
        @test eof(s)
        @test_throws EOFError read(s, UInt8)
    end
end
