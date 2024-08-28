# test inputs that should trigger various errors

include("utils.jl")

@testset "error printing" begin
    @test sprint(io-> Base.showerror(io, DecompressionError("invalid block compression mode 3"))) == "DecompressionError: invalid block compression mode 3"
end

@testset "decompressing corrupt input with $(decompress)" for decompress in (decompress, decompress_bytes)
    # HEADER_BITS
    @test_throws DecompressionError("invalid block compression mode 3") decompress([0b111, 0x00])
    @test_throws DecompressionError("invalid block compression mode 3") decompress([0b110, 0x00])

    # NON_COMPRESSED_LENS
    @test_throws DecompressionError("corrupted copy lengths") decompress([0b001, 0x00,0x00,0x00,0x00])
    @test_throws DecompressionError("corrupted copy lengths") decompress([0b000, 0x00,0x10,0x00,0x01])
    @test_throws DecompressionError("not enough input") decompress([0b001, 0xFF,0xFF,0x00,0x00])
    @test_throws DecompressionError("not enough input") decompress([0b000, 0x00,0x00,0xFF,0xFF])
    @test_throws DecompressionError("not enough input") decompress([0b001, 0x00,0x00,0xFF,0xFF, 0b001])

    # CLEN_NUM_BITS_PER_OP
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[0,0,0,0]
        )
    ))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[0,7,0,0]
        )
    ))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[0,2,0,2]
        )
    ))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[1,2,0,0]
        )
    ))
    @test_throws DecompressionError("overfull code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[1,1,1,1]
        )
    ))
    @test_throws DecompressionError("overfull code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[1,1,1,0]
        )
    ))
    @test_throws DecompressionError("overfull code table") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[2,2,2,2,7,7]
        )
    ))
    # This is a valid code table valid according to https://github.com/ebiggers/libdeflate/blob/dc76454a39e7e83b68c3704b6e3784654f8d5ac5/lib/deflate_decompress.c#L809-L839
    @test_throws DecompressionError("not enough input") decompress(bitvector_to_bytes(
        bits_clen_num_bits_per_op(
            unsorted_clen_num_bits_per_op=UInt8[0,0,0,0,1,0]
        )
    ))

    # CLEN_OP
    @test_throws DecompressionError("no previous code length to repeat") decompress(bitvector_to_bytes(Bool[
        bits_clen_num_bits_per_op();
        bit_digits(op_to_huffman_code(default_clen_tree, 0x0010)...); # Copy the previous code length 3 times.
        bit_digits(0, 2);
    ]))
    @test_throws DecompressionError("too many code lengths") decompress(bitvector_to_bytes(Bool[
        bits_clen_num_bits_per_op(;nlit=257, ndist=1);
        bit_digits(op_to_huffman_code(default_clen_tree, 0x0007)...); # 7 bits
        # Copy the previous code length 6*43 = 258 times
        ([bit_digits(op_to_huffman_code(default_clen_tree, 0x0010)...); bit_digits(3, 2)] for i in 1:43)...;
    ]))
    @test_throws DecompressionError("too many code lengths") decompress(bitvector_to_bytes(Bool[
        bits_clen_num_bits_per_op(;nlit=257, ndist=1);
        # Repeat a code length of 0 for 10*26 = 260 times.
        ([bit_digits(op_to_huffman_code(default_clen_tree, 0x0011)...); bit_digits(7, 3)] for i in 1:26)...;
    ]))
    @test_throws DecompressionError("too many code lengths") decompress(bitvector_to_bytes(Bool[
        bits_clen_num_bits_per_op(;nlit=257, ndist=1);
        # Repeat a code length of 0 for 138*2 = 276 times.
        ([bit_digits(op_to_huffman_code(default_clen_tree, 0x0012)...); bit_digits(127, 7)] for i in 1:2)...;
    ]))
    @test_throws DecompressionError("no code for end-of-block") decompress(bitvector_to_bytes(Bool[
        bits_clen_num_bits_per_op(;nlit=257, ndist=1);
        # Repeat a code length of 0 for 138 + 11 + 109 = 258 times.
        [bit_digits(op_to_huffman_code(default_clen_tree, 0x0012)...); bit_digits(127, 7)]
        [bit_digits(op_to_huffman_code(default_clen_tree, 0x0012)...); bit_digits(109, 7)]
    ]))
    @test_throws DecompressionError("no code for end-of-block") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            lit_len_num_bits_per_op=zeros(UInt8,288),
            dist_num_bits_per_op=zeros(UInt8,32),
        );
    ]))
    @test UInt8[] == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(;
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x01; fill(0x00, 31)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        false;
    ]))
    @test UInt8[] == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(;
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x01; fill(0x00, 31)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        true;
    ]))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(;
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x02; 0x02],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        true;
    ]))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(;
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x02; 0x0f],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        true;
    ]))
    @test_throws DecompressionError("overfull code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(;
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x02; 0x02; 0x02; 0x02; 0x0f],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        true;
    ]))
    @test_throws DecompressionError("no codes for distances, but there is a code for length") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            lit_len_num_bits_per_op=[fill(0x00, 256); 0x01; 0x01; fill(0x00, 30)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
    ]))
    @test_throws DecompressionError("no codes for distances, but there is a code for length") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            lit_len_num_bits_per_op=[0x02;0x02;fill(0x00, 254); 0x02; 0x02; fill(0x00, 30)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
    ]))
    @test UInt8[0x00] == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            lit_len_num_bits_per_op=[0x01; fill(0x00, 255); 0x01; fill(0x00, 31)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        false;
        true;
    ]))
    @test UInt8[] == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            lit_len_num_bits_per_op=[0x01; fill(0x00, 255); 0x01; fill(0x00, 31)],
            dist_num_bits_per_op=zeros(UInt8,32),
        );
        true;
    ]))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            dist_num_bits_per_op=[0x01, 0x02],
        );
    ]))
    @test_throws DecompressionError("incomplete code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            dist_num_bits_per_op=[0x02, 0x02],
        );
    ]))
    @test_throws DecompressionError("overfull code table") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header(
            dist_num_bits_per_op=[0x02, 0x02, 0x02, 0x02, 0x0f],
        );
    ]))

    # LIT_LEN_DIST_OP
    @test_throws DecompressionError("unknown len op") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,1,1,];
    ]))
    @test_throws DecompressionError("unknown len op") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,1,0,];
    ]))
    @test_throws DecompressionError("unknown len op") decompress(bitvector_to_bytes(Bool[
        [1,1,0];
        [1,1,0,0,0,1,1,1,];
    ]))
    @test_throws DecompressionError("unknown len op") decompress(bitvector_to_bytes(Bool[
        [1,1,0];
        [1,1,0,0,0,1,1,0,];
    ]))

    # Reading before the beginning of the buffer
    @test UInt8[] == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [0,0,0,0,0,0,0,];
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [0,0,0,0,0,0,1,];
        [0,0,0,0,0,];
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [0,0,0,0,0,0,1,];
        [1,1,1,1,1,];
        bit_digits(0x3FFF,14);
    ]))
    @test fill(0x8F, 4) == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [0,0,0,0,0,0,1,];
        [0,0,0,0,0,];
        [0,0,0,0,0,0,0,];
    ]))
    @test fill(0x8F, 259) == decompress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [1,1,0,0,0,1,0,1,];
        [0,0,0,0,0,];
        [0,0,0,0,0,0,0,];
    ]))
    @test fill(0x8F, 4) == de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [1,1,0,0,0,1,0,1,];
        bit_digits(0, 16);
        [0,0,0,0,0,];
        [0,0,0,0,0,0,0,];
    ]))
    @test fill(0x8F, 1+3+0xFFFF) == de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [1,1,0,0,0,1,0,1,]; bit_digits(0xFFFF, 16); # length of 65538
        [0,0,0,0,0,]; # distance of 1
        [0,0,0,0,0,0,0,]; # end of block
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,0,1,];
        bit_digits(0, 16);
        [0,0,0,0,0,];
        [0,0,0,0,0,0,0,];
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,0,1,];
        bit_digits(0xFFFF, 16);
        [0,0,0,0,0,];
        [0,0,0,0,0,0,0,];
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,0,1,];
        bit_digits(0xFFFF, 16);
        [1,1,1,1,1,];
        bit_digits(0x3FFF,14);
        [0,0,0,0,0,0,0,];
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,1,0,0,0,1,0,1,];
        bit_digits(0xFFFF-3, 16);
        [1,1,1,1,1,];
        bit_digits(0x3FFF,14);
        [0,0,0,0,0,0,0,];
    ]))
    @test fill(0x8F, 2^16 + 2^16+2) == de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [1,1,0,0,0,1,0,1,]; bit_digits(0xFFFF-3, 16); # length of 65535
        [0,0,0,0,0,]; # distance of 1
        [1,1,0,0,0,1,0,1,]; bit_digits(0xFFFF, 16); # length of 65538
        [1,1,1,1,1,]; bit_digits(0x3FFF,14); # distance of 65536
        [0,0,0,0,0,0,0,];# end of block
    ]))
    @test_throws DecompressionError("cannot read before beginning of out buffer") de64compress(bitvector_to_bytes(Bool[
        bits_dynamic_huffman_header();
        [1,0,1,1,1,1,1,1,]; # lit 8F
        [1,1,0,0,0,1,0,1,];
        bit_digits(0xFFFF-4, 16);
        [0,0,0,0,0,];
        [1,1,0,0,0,1,0,1,];
        bit_digits(0xFFFF, 16);
        [1,1,1,1,1,];
        bit_digits(0x3FFF,14);
        [0,0,0,0,0,0,0,];
    ]))

end