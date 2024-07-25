using Test
using p7zip_jll: p7zip
using CRC32: crc32
using InputBuffers: InputBuffer
using ZipArchives: 
    ZipReader,
    zip_nentries,
    zip_compressed_size,
    zip_uncompressed_size,
    zip_stored_crc32,
    zip_crc32,
    zip_compression_method, # experimental
    zip_entry_data_offset # experimental
using CodecZlib: DeflateCompressor
using CodecInflate64: DeflateDecompressor, Deflate64Decompressor, Deflate64DecompressorStream, DeflateDecompressorStream

# p7zip doesn't seem to use the special 16 bit length code
function p7zip_64compress(data::Vector{UInt8})::Vector{UInt8}
    d = read(pipeline(IOBuffer(data),`$(p7zip()) a dummy/ -tzip -mm=deflate64 -mx=9 -mmt=off -sidata -so`))
    r = ZipReader(d)
    @assert zip_nentries(r) == 1
    @assert zip_compression_method(r, 1) == 9
    @assert zip_uncompressed_size(r, 1) == length(data)
    a = zip_entry_data_offset(r,1)
    s = zip_compressed_size(r,1)
    return d[begin+a:begin+a+s-1]
end

function p7zip_compress(data::Vector{UInt8})::Vector{UInt8}
    d = read(pipeline(IOBuffer(data),`$(p7zip()) a dummy/ -tzip -mm=deflate -mx=9 -mmt=off -sidata -so`))
    r = ZipReader(d)
    @assert zip_nentries(r) == 1
    @assert zip_compression_method(r, 1) == 8
    @assert zip_uncompressed_size(r, 1) == length(data)
    a = zip_entry_data_offset(r,1)
    s = zip_compressed_size(r,1)
    return d[begin+a:begin+a+s-1]
end

function zlib_compress(data::Vector{UInt8})::Vector{UInt8}
    transcode(DeflateCompressor, data)
end

function decompress(data::Vector{UInt8})::Vector{UInt8}
    transcode(DeflateDecompressor, data)
end

function de64compress(data::Vector{UInt8})::Vector{UInt8}
    transcode(Deflate64Decompressor, data)
end

# decompress one byte at a time
function decompress_bytes(data::Vector{UInt8})::Vector{UInt8}
    io = IOBuffer()
    s = DeflateDecompressorStream(io; bufsize=1)
    for i in eachindex(data)
        write(s, data[i])
        flush(s)
    end
    write(s, TranscodingStreams.TOKEN_END)
    flush(s)
    take!(io)
end

function de64compress(data::Vector{UInt8})::Vector{UInt8}
    transcode(Deflate64Decompressor, data)
end

function de64compress_bytes(data::Vector{UInt8})::Vector{UInt8}
    io = IOBuffer()
    s = Deflate64DecompressorStream(io; bufsize=1)
    for i in eachindex(data)
        write(s, data[i])
        flush(s)
    end
    write(s, TranscodingStreams.TOKEN_END)
    flush(s)
    take!(io)
end

function checkcrc32_zipfile(zipfile::String)
    data = read(zipfile)
    r = ZipReader(data)
    for i in 1:zip_nentries(r)
        method = zip_compression_method(r, i)
        a = zip_entry_data_offset(r,i)
        s = zip_compressed_size(r,i)
        c = data[begin+a:begin+a+s-1]
        u = if method == 9
            Deflate64DecompressorStream(InputBuffer(c))
        elseif method == 8
            DeflateDecompressorStream(InputBuffer(c))
        elseif method == 0
            InputBuffer(c)
        else
            error("unknown method in $(repr(zipfile)) entry: $(i) name: $(repr(zip_name(r,i)))")
        end
        if crc32(u) != zip_stored_crc32(r, i)
            error("crc32 wrong for $(repr(zipfile)) entry: $(i) name: $(repr(zip_name(r,i)))")
        end
    end
    true
end