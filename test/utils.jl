using Test
using p7zip_jll: p7zip
using CRC32: crc32
using InputBuffers: InputBuffer
using TranscodingStreams: TranscodingStreams
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
using ArgCheck: @argcheck
using CodecInflate64

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

function checkcrc32_zipfile(zipfile::String; bufsize=2^14)
    data = read(zipfile)
    r = ZipReader(data)
    for i in 1:zip_nentries(r)
        method = zip_compression_method(r, i)
        a = zip_entry_data_offset(r,i)
        s = zip_compressed_size(r,i)
        c = data[begin+a:begin+a+s-1]
        u = if method == 9
            Deflate64DecompressorStream(InputBuffer(c); bufsize)
        elseif method == 8
            DeflateDecompressorStream(InputBuffer(c); bufsize)
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

"""
Return the huffman code of an op
"""
function op_to_huffman_code(tree::CodecInflate64.HuffmanTree, op)::Tuple{UInt16, UInt8}
    @argcheck op ∈ tree.sorted_ops
    @argcheck op < length(tree.sorted_ops)
    op_pos = findfirst(==(op), tree.sorted_ops)
    op_nbits = findfirst(>(op_pos), tree.op_offset_per_num_bit) - 1
    v::UInt16 = 0x0000
    for nbits in 1:op_nbits-1
        v += tree.num_ops_per_num_bit[nbits]
        v <<= 1
    end
    v += op_pos - tree.op_offset_per_num_bit[op_nbits]
    vr = bitreverse(v) >> (0x10-op_nbits)
    vr, op_nbits
end

# pack a bit vector into bytes in deflate style, first bit is lsb
# padding is zeros
function bitvector_to_bytes(v::AbstractVector{Bool})::Vector{UInt8}
    out = UInt8[]
    bp = 8
    for bit in v
        if bp == 8
            push!(out, 0x00)
            bp = 0
        end
        out[end] |= bit << bp
        bp += 1
    end
    out
end

bit_digits(x, nbits) = Bool.(digits(x; base=2, pad=nbits))

default_clen_num_bits_per_op = [fill(0x02, 3); fill(0x06, 16)]
default_clen_tree = CodecInflate64.parse_huffman!(CodecInflate64.HuffmanTree(19,7), default_clen_num_bits_per_op)

function bits_clen_num_bits_per_op(;
        final=true,
        nlit=257,
        ndist=1,
        unsorted_clen_num_bits_per_op=default_clen_num_bits_per_op[CodecInflate64.order .+ 1],
    )::Vector{Bool}
    nclen = length(unsorted_clen_num_bits_per_op)
    @argcheck nlit ∈ (257:288)
    @argcheck ndist ∈ (1:32)
    @argcheck nclen ∈ (4:19)
    @argcheck all(≤(0x07), unsorted_clen_num_bits_per_op)
    Bool[
        final;
        bit_digits(0b10, 2); # dynamic huffman codes
        bit_digits(nlit-257, 5);
        bit_digits(ndist-1, 5);
        bit_digits(nclen-4, 4);
        (bit_digits(nb, 3) for nb in unsorted_clen_num_bits_per_op)...;
    ]
end

function bits_dynamic_huffman_header(;
        final=true,
        lit_len_num_bits_per_op=CodecInflate64.fixed_lit_len_dist_num_bits_per_op[1:288],
        dist_num_bits_per_op=CodecInflate64.fixed_lit_len_dist_num_bits_per_op[289:320],
    )
    nlit = length(lit_len_num_bits_per_op)
    ndist = length(dist_num_bits_per_op)
    Bool[
        bits_clen_num_bits_per_op(;final, nlit, ndist);
        (bit_digits(op_to_huffman_code(default_clen_tree, UInt16(nb))...) for nb in lit_len_num_bits_per_op)...;
        (bit_digits(op_to_huffman_code(default_clen_tree, UInt16(nb))...) for nb in dist_num_bits_per_op)...;
    ]
    
end