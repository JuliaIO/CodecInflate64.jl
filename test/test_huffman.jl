include("utils.jl")

using Random

# Note HuffmanTree is internal

using CodecInflate64: HuffmanTree, parse_huffman!, get_op

@testset "empty trees" begin
    # it is invalid to build an empty tree.
    for i in 0:19
        @test_throws DecompressionError("incomplete code table") parse_huffman!(HuffmanTree(19, 7), zeros(UInt8,i))
    end
end

@testset "one code trees" begin
    # it is valid to build a tree with one op with one bit.
    # Any input will use one bit and decode to the op, so that op has two codes, 0 and 1
    for i in 1:19
        for pad in i:19
            num_bits_per_op = zeros(UInt8, pad)
            num_bits_per_op[i] = 0x01
            tree = parse_huffman!(HuffmanTree(19, 7), num_bits_per_op)
            local op_code, op_nbits = op_to_huffman_code(tree, i-1)
            @test op_code == 0x0000
            @test op_nbits == 1
            for input in 0x0000:0xFFFF
                op, nbits = get_op(input, tree)
                @test nbits == 1
                @test op == i-1
            end
        end
    end
end

@testset "two code trees" begin
    for i in 1:18
        for j in i+1:19
            num_bits_per_op = zeros(UInt8, 19)
            num_bits_per_op[i] = 0x01
            num_bits_per_op[j] = 0x01
            tree = parse_huffman!(HuffmanTree(19, 7), num_bits_per_op)
            for input in 0x0000:0xFFFF
                op, nbits = get_op(input, tree)
                @test nbits == num_bits_per_op[op+1]
                @test op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits)
            end
        end
    end
end

@testset "random nbits" begin
    for trial in 1:10000
        n = rand(2:19)
        num_bits_per_op = rand(0x00:0x07, n)
        sum(num_bits_per_op) < 2 && continue
        try
            tree = parse_huffman!(HuffmanTree(19, 7), num_bits_per_op)
            # @show num_bits_per_op
            for input in 0x0000:0xFFFF
                op, nbits = get_op(input, tree)
                @test nbits == num_bits_per_op[op+1]
                @test op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits)
            end
        catch err
            err isa DecompressionError || rethrow()
        end
    end
end

@testset "Full tree" begin
    num_bits_per_op = fill(0x05, 32)
    tree = parse_huffman!(HuffmanTree(32, 5), num_bits_per_op)
    for input in 0x0000:0xFFFF
        op, nbits = get_op(input, tree)
        @test nbits == num_bits_per_op[op+1]
        @test op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits)
    end

    for trial in 1:100
        num_bits_per_op = shuffle([fill(0x02, 3); fill(0x06, 16);])
        tree = parse_huffman!(HuffmanTree(19, 7), num_bits_per_op)
        for input in 0x0000:0xFFFF
            op, nbits = get_op(input, tree)
            @test nbits == num_bits_per_op[op+1]
            @test op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits)
        end
    end
    for trial in 1:100
        num_bits_per_op = shuffle([0x01; 0x02; 0x03; fill(0x07, 16);])
        tree = parse_huffman!(HuffmanTree(19, 7), num_bits_per_op)
        for input in 0x0000:0xFFFF
            op, nbits = get_op(input, tree)
            @test nbits == num_bits_per_op[op+1]
            @test op_to_huffman_code(tree, op) == (input & ~(0xFFFF<<nbits), nbits)
        end
    end
end