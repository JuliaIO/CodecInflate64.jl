using Supposition: Data, @composed, @check, event!, produce!

include("../test/utils.jl")

# Note HuffmanTree is internal
using CodecInflate64: HuffmanTree, parse_huffman!, get_op

const datas = Data.Vectors(Data.Integers{UInt8}(); min_size=0, max_size=200_000)

@testset "roundtrip" begin
    @check max_examples=10_000 function roundtrip(
            data=datas
        )
        data == decompress(zlib_compress(data))
    end
    @check max_examples=200 function roundtrip_partial(
            data=datas
        )
        c = zlib_compress(data)
        for i in eachindex(c)
            try
                decompress(c[begin:i-1])
                return false
            catch e
                e === DecompressionError("not enough input") || return false
            end
        end
        return true
    end
end

@testset "random input" begin
    @check max_examples=10_000 function rand_input(
            data=datas
        )
        try
            s = DeflateDecompressorStream(InputBuffer(data))
            read(s, 1_000_000) # avoid using all memory
        catch e
            e isa DecompressionError || rethrow()
        end
        true
    end
    @check max_examples=10_000 function rand_input64(
            data=datas
        )
        try
            s = Deflate64DecompressorStream(InputBuffer(data))
            read(s, 1_000_000) # avoid using all memory
        catch e
            e isa DecompressionError || rethrow()
        end
        true
    end
end

const blockss = Data.Vectors(Data.Vectors(Data.Integers{UInt8}(); min_size=0, max_size=2^16-1); min_size=1, max_size=100)

@testset "random non compressed blocks" begin
    @check max_examples=10_000 function rand_blocks(
            blocks=blockss
        )
        data = UInt8[]
        for i in 1:length(blocks)
            len = UInt16(length(blocks[i]))
            nlen = ~len
            if i == length(blocks)
                push!(data, 0b001)
            else
                push!(data, 0b000)
            end
            push!(data, len&0xFF)
            push!(data, len>>8)
            push!(data, nlen&0xFF)
            push!(data, nlen>>8)
            append!(data, blocks[i])
        end
        de64compress(data) == collect(Iterators.flatten(blocks))
    end
end

const clen_num_bits_per_ops = Data.Vectors(Data.Integers(0x00,0x07); min_size=4, max_size=19)
const lit_len_num_bits_per_ops = Data.Vectors(Data.Integers(0x00,0x0F); min_size=257, max_size=288)
const dist_num_bits_per_ops = Data.Vectors(Data.Integers(0x00,0x0F); min_size=1, max_size=32)

tree_types = [
    ((19, 7), clen_num_bits_per_ops),
    ((288, 15), lit_len_num_bits_per_ops),
    ((32, 15), dist_num_bits_per_ops),
]

@testset "random huffman tree building $(tree_args)" for (tree_args, tree_pos) in tree_types
    @check max_examples=1_000_000 function rand_trees(
            num_bits_per_op=tree_pos
        )
        sum(num_bits_per_op) < 2 && return true # ignore one bit special case here
        try
            tree = parse_huffman!(HuffmanTree(tree_args...), num_bits_per_op)
            # @show num_bits_per_op
            for input in 0x0000:0xFFFF
                op, nbits = get_op(input, tree)
                nbits == num_bits_per_op[op+1] || return false
                op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits) || return false
            end
        catch err
            err isa DecompressionError || return false
        end
        true
    end
end

@testset "random valid huffman tree building" begin
    @check max_examples=10_000 function rand_valid_trees(
            split_ops=Data.Vectors(Data.Pairs(Data.Integers{Int}(),Data.Integers{Int}()); min_size=0, max_size=286)
        )
        max_nbits = 0x0F
        num_bits_per_op = [0x01, 0x01]
        for (split, at) in split_ops
            n_left = findall(<(max_nbits), num_bits_per_op)
            split = n_left[mod1(split, length(n_left))]
            nb = num_bits_per_op[split] + 1
            num_bits_per_op[split] = nb
            insert!(num_bits_per_op, mod1(at, length(num_bits_per_op)+1), nb)
        end
        tree = parse_huffman!(HuffmanTree(288, 15), num_bits_per_op)
        # @show num_bits_per_op
        for input in 0x0000:0xFFFF
            op, nbits = get_op(input, tree)
            nbits == num_bits_per_op[op+1] || return false
            op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits) || return false
        end
        true
    end
end