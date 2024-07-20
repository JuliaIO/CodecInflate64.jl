struct HuffmanTree
    sorted_ops::Vector{UInt16}
    num_ops_per_num_bit::Vector{UInt16}
    op_offset_per_num_bit::Vector{UInt16}
end
function HuffmanTree(num_ops::Integer, max_num_bits::Integer)
    HuffmanTree(fill(0xFFFF,num_ops), zeros(UInt16,max_num_bits), zeros(UInt16,max_num_bits+1))
end

function reset!(tree::HuffmanTree)
    tree.sorted_ops .= 0xFFFF
    tree.num_ops_per_num_bit .= 0x0000
    tree.op_offset_per_num_bit .= 0x0000
end

# Non allocating version of https://github.com/GunnarFarneback/Inflate.jl/blob/cc77be73388f4160d187ab0c3fdaa3df13aa7f3b/src/Inflate.jl#L174-L186
function parse_huffman!(
        tree::HuffmanTree,
        num_bits_per_op::AbstractVector{UInt8}, # in
    )
    # @show length(num_bits_per_op)
    # TODO Validate produced tree
    sorted_ops = tree.sorted_ops
    num_ops_per_num_bit = tree.num_ops_per_num_bit
    op_offset_per_num_bit = tree.op_offset_per_num_bit
    num_ops_per_num_bit .= 0x0000
    sorted_ops .= 0xFFFF
    op_offset_per_num_bit .= 0x0000
    max_num_bits = length(num_ops_per_num_bit)
    @assert max_num_bits ≥ maximum(num_bits_per_op)
    @assert length(op_offset_per_num_bit) == max_num_bits + 1
    @assert length(sorted_ops) ≥ length(num_bits_per_op)
    for n in num_bits_per_op
        if !iszero(n)
            num_ops_per_num_bit[n] += 1
        end
    end
    op_offset_per_num_bit[1] = 1
    op_offset_per_num_bit[2] = 1
    for n in 2:max_num_bits
        op_offset_per_num_bit[n+1] = op_offset_per_num_bit[n+1-1] + num_ops_per_num_bit[n-1]
    end
    # display(op_offset_per_num_bit)
    for (c, n) in enumerate(num_bits_per_op)
        # @show c, n
        if !iszero(n)
            off = op_offset_per_num_bit[n+1]
            sorted_ops[off] = c-1
            op_offset_per_num_bit[n+1] = off + 1
        end
    end
end

# Using algorithm from https://github.com/GunnarFarneback/Inflate.jl/blob/cc77be73388f4160d187ab0c3fdaa3df13aa7f3b/src/Inflate.jl#L134-L145
function get_op(bits::UInt16, tree::HuffmanTree)::Tuple{UInt16, UInt8}
    v = 0x0000
    for nbits in 1:length(tree.num_ops_per_num_bit)
        bit = bits & 0x01
        bits >>= 1
        v = (v << 1) | bit
        if v < tree.num_ops_per_num_bit[nbits]
            return tree.sorted_ops[tree.op_offset_per_num_bit[nbits]+v], UInt8(nbits)
        end
        v -= tree.num_ops_per_num_bit[nbits]
    end
    error("incomplete code table")
end