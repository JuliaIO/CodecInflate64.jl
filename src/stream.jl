import TranscodingStreams: TranscodingStreams, TranscodingStream

@enum Mode begin
    ERROR = -1
    DONE = 0
    PARSE_HEADER = 1
    COPY_OUT = 2
    RUN_OP = 3
end

"The maximum bytes that can be written by a single op."
const MIN_OUTPUT_MARGIN = 65538

"The maximum bytes that can be read in one step."
const MIN_INPUT_LENGTH = 65535

"This many bytes must be saved in the output buffer for reference by ops"
const MAX_DIST = 65536

const BUFFER_SIZE = 2^18 -1 # must have enough space for MIN_OUTPUT_MARGIN + MAX_DIST

const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
const fixed_lit_dist_num_bits_per_op = UInt8[fill(0x08,144); fill(0x09,112); fill(0x07,24); fill(0x08,8); fill(0x05, 32)]

@kwdef mutable struct StreamState
    in_buf::Vector{UInt8}=zeros(UInt8, BUFFER_SIZE + 1)
    in_read_offset::Int=0
    in_write_offset::Int=0
    out_buf::Vector{UInt8}=zeros(UInt8, BUFFER_SIZE + 1)
    out_read_offset::Int=0
    out_write_offset::Int=0
    mode::Mode=PARSE_HEADER
    len::UInt32=UInt32(0)
    deflate64::Bool
    in_final_block::Bool=false
    all_in::Bool=false
    bp::UInt8=0x00
    clen_num_bits_per_op::Vector{UInt8}=zeros(UInt8,19)
    clen_tree::HuffmanTree=HuffmanTree(19, 7)
    lit_dist_num_bits_per_op::Vector{UInt8}=zeros(UInt8, 320)
    lit_tree::HuffmanTree=HuffmanTree(288, 15)
    dist_tree::HuffmanTree=HuffmanTree(32, 15)
end

function reset!(s::StreamState)
    s.in_buf .= 0x00
    s.in_read_offset = 0
    s.in_write_offset = 0
    s.out_buf .= 0x00
    s.out_read_offset = 0
    s.out_write_offset = 0
    s.mode = PARSE_HEADER
    s.len = UInt32(0)
    s.in_final_block = false
    s.all_in = false
    s.bp = 0x00
    s.clen_num_bits_per_op .= 0x00
    reset!(s.clen_tree)
    s.lit_dist_num_bits_per_op .= 0x00
    reset!(s.lit_tree)
    reset!(s.dist_tree)
end

function main_run!(all_in::Bool, input::TranscodingStreams.Memory, output::TranscodingStreams.Memory, s::StreamState)
    s.mode == ERROR && error("stream had previous error")
    s.all_in && !iszero(length(input)) && error("extra unexpected input")
    s.all_in |= all_in
    while true
        # @info "write in"
        input = write_in!(s, input)
        n_preserve = if s.mode == DONE
            0
        else
            MAX_DIST # if not done preserve some output for potential future reference
        end
        # @info "read out"
        output = read_out!(s, output, n_preserve)
        # @show in_length(s) out_margin(s)
        while s.mode != DONE && (all_in || in_length(s) ≥ MIN_INPUT_LENGTH) && out_margin(s) ≥ MIN_OUTPUT_MARGIN
            if all_in
                n_available = in_length(s)
            end
            run!(s)
            if all_in
                if in_length(s) > n_available
                    error("not enough bytes available")
                end
            end
        end
        if s.mode == DONE && iszero(out_length(s))
            # YAY done
            return true, input, output
        elseif iszero(length(output))
            # @info "need more output space"
            return false, input, output
        elseif iszero(length(input)) && !s.all_in
            # @info "need more input"
            return false, input, output
        end
    end
end

function run!(s::StreamState)::Nothing
    # @show s.mode
    if s.mode == ERROR
        error("stream had previous error")
    elseif s.mode == DONE
        return
    elseif s.mode == PARSE_HEADER
        @assert !s.in_final_block
        h_bits = readbyte(s) & 0b111
        s.in_final_block = isone(h_bits & 0b1)
        BTYPE = (h_bits>>1)
        # @show BTYPE
        consume!(s, 0x03)
        if BTYPE == 0b00
            consume!(s, (0x08-s.bp) & 0b111)
            @assert iszero(s.bp)
            # read LEN and NLEN
            hlen = readchunk(s)
            consume!(s, 0x10)
            hnlen = readchunk(s)
            consume!(s, 0x10)
            s.mode = COPY_OUT
            if hlen ⊻ hnlen != 0xffff
                error("corrupted data")
            end
            s.len = hlen
            return
        elseif BTYPE == 0b01
            # compressed with fixed Huffman codes
            s.lit_dist_num_bits_per_op .= fixed_lit_dist_num_bits_per_op
            parse_huffman!(s.lit_tree, view(s.lit_dist_num_bits_per_op, 1:288))
            parse_huffman!(s.dist_tree, view(s.lit_dist_num_bits_per_op, 289:320))
            s.mode = RUN_OP
            return
        elseif BTYPE == 0b10
            # compressed with dynamic Huffman codes
            x = readchunk(s)
            NLIT = x & 0b11111 + UInt16(257)
            NDIST = x>>5 & 0b11111 + UInt16(1)
            NCLEN = x>>10 & 0b1111 + UInt16(4)
            # @show Int.((NLIT, NDIST, NCLEN))
            consume!(s, 0x0E)
            s.clen_num_bits_per_op .= 0x00
            for i in 1:NCLEN
                s.clen_num_bits_per_op[1 + order[i]] = readbyte(s) & 0b111
                consume!(s, 0x03)
            end
            parse_huffman!(s.clen_tree, s.clen_num_bits_per_op)
            # @info "printing codes clen"
            # print_codes(s.clen_tree)
            # @show s.clen_num_bits_per_op
            # NLIT code lengths for the literal/length alphabet
            parse_num_bits_per_op!(s.lit_dist_num_bits_per_op, NLIT+NDIST, s)
            parse_huffman!(s.lit_tree, view(s.lit_dist_num_bits_per_op, 1:Int(NLIT)))
            parse_huffman!(s.dist_tree, view(s.lit_dist_num_bits_per_op, (Int(NLIT)+1):(Int(NLIT+NDIST))))
            s.mode = RUN_OP
            return
        else
            error("invalid block compression mode 3")
        end
    elseif s.mode == COPY_OUT
        @assert iszero(s.bp)
        for i in UInt32(1):s.len
            s.out_buf[1+s.out_write_offset] = s.in_buf[1+s.in_read_offset]
            s.out_write_offset = (s.out_write_offset + 1) & BUFFER_SIZE
            s.in_read_offset = (s.in_read_offset + 1) & BUFFER_SIZE
        end
        s.len = UInt32(0)
        if s.in_final_block
            s.mode = DONE
        else
            s.mode = PARSE_HEADER
        end
        return
    elseif s.mode == RUN_OP
        op, nbits = get_op(readchunk(s), s.lit_tree)
        consume!(s, nbits)
        if op < 0x0100
            s.out_buf[1+s.out_write_offset] = op%UInt8
            s.out_write_offset = (s.out_write_offset + 1) & BUFFER_SIZE
        elseif op == 0x0100
            if s.in_final_block
                s.mode = DONE
            else
                s.mode = PARSE_HEADER
            end
        else
            # read length
            len::UInt32 = if op ≤ 0x0108
                UInt32(op) - UInt32(254)
            elseif op ≤ 0x011c
                p_len, num_extra_bits = parse_len(op, readchunk(s))
                consume!(s, num_extra_bits)
                p_len
            elseif op == 0x011d
                if s.deflate64
                    # If deflate 64 use next 16 bits +3 as length
                    p_len = readchunk(s) + UInt32(3)
                    consume!(s, 0x10)
                    p_len
                else
                    UInt32(258)
                end
            else
                # unknown op
                error("unknown op")
            end
            # read dist
            dist_op, nbits = get_op(readchunk(s), s.dist_tree)
            consume!(s, nbits)
            dist::UInt32 = if dist_op ≤ 0x0003
                UInt32(dist_op) + UInt32(1)
            else
                p_dist, num_extra_bits = parse_dist(dist_op, readchunk(s))
                consume!(s, num_extra_bits)
                p_dist
            end
            for i in UInt32(1):len
                s.out_buf[1+s.out_write_offset&BUFFER_SIZE] = s.out_buf[1+(s.out_write_offset-dist)&BUFFER_SIZE]
                s.out_write_offset = (s.out_write_offset + 1) & BUFFER_SIZE
            end
        end
        return
    else
        @assert false "unreachable"
    end
end

function parse_len(op::UInt16, chunk::UInt16)::Tuple{UInt32, UInt8}
    op_l = op%UInt8
    x = op_l - 0x09
    num_extra_bits = (op_l-0x05)>>2
    extra_bits = chunk & 0xFFFF>>(0x10 - num_extra_bits)
    len = (UInt32(0b100 | x & 0b11)<<num_extra_bits | UInt32(extra_bits)) + UInt32(3)
    len, num_extra_bits
end

function parse_dist(op::UInt16, chunk::UInt16)::Tuple{UInt32, UInt8}
    op_l = op%UInt8
    num_extra_bits = (op_l-0x02)>>1
    extra_bits = chunk & 0xFFFF>>(0x10 - num_extra_bits)
    dist = (UInt32(0b10 | op_l & 0b1)<<num_extra_bits | UInt32(extra_bits)) + UInt32(1)
    dist, num_extra_bits
end

function readchunk(s::StreamState)::UInt16
    data = s.in_buf
    r1 = s.in_read_offset & BUFFER_SIZE
    r2 = (r1 + 1) & BUFFER_SIZE
    r3 = (r1 + 2) & BUFFER_SIZE
    x = UInt32(data[1+r1]) | UInt32(data[1+r2])<<8 | UInt32(data[1+r3])<<16
    (x >> s.bp)%UInt16
end

function readbyte(s::StreamState)::UInt8
    data = s.in_buf
    r1 = s.in_read_offset & BUFFER_SIZE
    r2 = (r1 + 1) & BUFFER_SIZE
    x = UInt16(data[1+r1]) | UInt16(data[1+r2])<<8
    (x >> s.bp)%UInt8
end

function consume!(s::StreamState, n::UInt8)
    s.in_read_offset = (s.in_read_offset + ((s.bp + n) >> 3)) & BUFFER_SIZE
    s.bp = (s.bp + n) & 0b111
    nothing
end

function parse_num_bits_per_op!(
        num_bits_per_op::Vector{UInt8},
        N::UInt16,
        s::StreamState,
    )
    i = 1
    while i ≤ N
        op, nbits = get_op(readchunk(s), s.clen_tree)
        consume!(s, nbits)
        if op < 0x0010
            num_bits_per_op[i] = op
            i += 1
        elseif op == 0x0010
            # Copy the previous code length 3 - 6 times.
            n = readchunk(s)&0b11 + 3
            num_bits_per_op[i:i + n - 1] .= num_bits_per_op[i-1]
            consume!(s, 0x02) #   The next 2 bits indicate repeat length
            i += n
        elseif op == 0x0011
            # Repeat a code length of 0 for 3 - 10 times.
            n = readchunk(s)&0b111 + 3
            num_bits_per_op[i:i + n - 1] .= 0x00
            consume!(s, 0x03) # (3 bits of length)
            i += n
        elseif op == 0x0012
            # Repeat a code length of 0 for 11 - 138 times
            n = readchunk(s)&0b1111111 + 11
            num_bits_per_op[i:i + n - 1] .= 0x00
            consume!(s, 0x07)  # (7 bits of length)
            i += n
        else
            error("unreachable")
        end
    end
end

in_margin(s::StreamState)::Int = (s.in_read_offset - s.in_write_offset - 1) & BUFFER_SIZE
out_margin(s::StreamState)::Int = (s.out_read_offset - s.out_write_offset - 1) & BUFFER_SIZE
in_length(s::StreamState)::Int = BUFFER_SIZE - in_margin(s)
out_length(s::StreamState)::Int = BUFFER_SIZE - out_margin(s)

function write_in!(s::StreamState, mem::TranscodingStreams.Memory)::TranscodingStreams.Memory
    p::Ptr{UInt8} = mem.ptr
    sink = s.in_buf
    wo = s.in_write_offset & BUFFER_SIZE
    n = min(mem.size, in_margin(s)%UInt)
    i = 0
    while i < n
        sink[1 + wo] = unsafe_load(p+i)
        wo = (wo+1)&BUFFER_SIZE
        i += 1
    end
    s.in_write_offset = wo
    TranscodingStreams.Memory(p+n, mem.size-n)
end

function read_out!(s::StreamState, mem::TranscodingStreams.Memory, n_preserve::Int=0)::TranscodingStreams.Memory
    if out_length(s) < n_preserve
        return mem
    end
    p::Ptr{UInt8} = mem.ptr
    source = s.out_buf
    ro = s.out_read_offset & BUFFER_SIZE
    n = min(mem.size, (out_length(s) - n_preserve)%UInt64)
    i = 0
    while i < n
        unsafe_store!(p+i, source[1+ro])
        ro = (ro+1)&BUFFER_SIZE
        i += 1
    end
    s.out_read_offset = ro
    TranscodingStreams.Memory(p+n, mem.size-n)
end