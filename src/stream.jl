import TranscodingStreams: TranscodingStreams, TranscodingStream

@enum Mode begin
    DONE
    READ_BITS
    COPY_OUT
    RUN_OP
    WRITE_LIT
end

@enum InMode begin
    HEADER_BITS
    NON_COMPRESSED_LENS
    NUM_CODES
    CLEN_NUM_BITS_PER_OP
    CLEN_OP
    LIT_LEN_DIST_OP
end

"This many bytes must be saved in the output buffer for reference by ops"
const MAX_DIST = Int64(65536)

const BUFFER_SIZE = Int64(2^16) # must have enough space for MAX_DIST
@assert BUFFER_SIZE ≥ MAX_DIST
@assert BUFFER_SIZE - 1 == typemax(UInt16)

const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
const fixed_lit_len_dist_num_bits_per_op = UInt8[fill(0x08,144); fill(0x09,112); fill(0x07,24); fill(0x08,8); fill(0x05, 32)]

Base.@kwdef mutable struct StreamState
    mode::Mode=READ_BITS
    in_mode::InMode=HEADER_BITS
    in_buf::UInt64=0
    bits_left::UInt8=0
    bp::UInt8=0
    out_buf::Vector{UInt8}=zeros(UInt8, BUFFER_SIZE)
    out_offset::UInt16=0
    out_full::Bool=false
    len::UInt32=0
    dist::UInt32=0
    lit::UInt8=0
    copy_len::UInt16=0
    deflate64::Bool
    in_final_block::Bool=false
    nlit::UInt16=0
    ndist::UInt16=0
    nclen::UInt16=0
    clen_num_bits_per_op::Vector{UInt8}=zeros(UInt8,19)
    num_bits_per_op_idx::Int64=0
    clen_tree::HuffmanTree=HuffmanTree(19, 7)
    lit_len_dist_num_bits_per_op::Vector{UInt8}=zeros(UInt8, 320)
    lit_len_tree::HuffmanTree=HuffmanTree(288, 15)
    dist_tree::HuffmanTree=HuffmanTree(32, 15)
end

function reset!(s::StreamState)
    s.mode = READ_BITS
    s.in_mode = HEADER_BITS
    s.in_buf = 0
    s.bits_left = 0
    s.bp = 0
    s.out_buf .= 0x00
    s.out_offset = 0
    s.out_full = false
    s.len = 0
    s.dist = 0
    s.lit = 0
    s.copy_len = 0
    s.in_final_block = false
    s.nlit = 0
    s.ndist = 0
    s.nclen = 0
    s.clen_num_bits_per_op .= 0x00
    s.num_bits_per_op_idx = 0
    reset!(s.clen_tree)
    s.lit_len_dist_num_bits_per_op .= 0x00
    reset!(s.lit_len_tree)
    reset!(s.dist_tree)
end


function main_run!(input::TranscodingStreams.Memory, output::TranscodingStreams.Memory, s::StreamState)
    out_size = Int64(output.size)
    in_size = Int64(input.size)
    Δin::Int64 = 0
    Δout::Int64 = 0
    while true
        # println()
        # @show Δin Δout
        if s.mode == READ_BITS
            # @info "before refill"
            # @show Δin Δout s.bp s.bits_left
            Δin = refill_in_buf!(s, input, Δin)
            # @info "after refill"
            # @show Δin Δout s.bp s.bits_left
            in_buf = s.in_buf
            bits_left = s.bits_left
            if !read_input_bits!(s)
                # @info "need more input"
                # need more input
                @assert s.mode == READ_BITS
                @assert iszero(s.bp)
                @assert Δin == in_size
                # restore in buffer because read must be retried.
                s.bits_left = bits_left
                s.in_buf = in_buf
                return :input, Δin, Δout
            end
            # @info "after reading"
            # @show Δin Δout s.bp s.bits_left
        elseif s.mode == COPY_OUT
            # @info s.copy_len
            # @info "before refund"
            # @show Δin Δout s.bp s.bits_left
            Δin += refund_in_buf!(s)
            # @info "after refund"
            # @show Δin Δout s.bp s.bits_left
            @assert iszero(s.bp)
            !signbit(Δin) || error("internal error copying from input")
            in_left = in_size - Δin
            out_margin = out_size - Δout
            n_copy = UInt16(min(out_margin, Int64(s.copy_len), in_left))
            # @show n_copy
            unsafe_copyto!(output.ptr+Δout, input.ptr+Δin, Int(n_copy))
            copy_from_input!(s, input.ptr+Δin, n_copy)
            # These cannot overflow out_size because of min check
            s.copy_len -= n_copy
            Δin += n_copy
            Δout += n_copy
            if iszero(s.copy_len)
                if s.in_final_block
                    s.mode = DONE
                else
                    s.mode = READ_BITS
                end
            elseif Δin == in_size
                # @info "need more input"
                return :input, Δin, Δout
            else
                # @info "need more output"
                return :output, Δin, Δout
            end
        elseif s.mode == RUN_OP
            out_margin = out_size - Δout
            !signbit(out_margin) || error("internal error copying from output")
            # length distance copy
            n_copy = min(out_margin, Int64(s.len))
            copy_from_output!(output.ptr+Δout, s, n_copy, s.dist) # this can error if s.dist goes before the start of the out buffer.
            s.len -= n_copy
            Δout += n_copy # This cannot overflow out_size because of min check
            if iszero(s.len)
                s.mode = READ_BITS
            else
                Δin += refund_in_buf!(s)
                !signbit(Δin) || error("internal error refunding to input after partial RUN_OP")
                return :output, Δin, Δout
            end
        elseif s.mode == WRITE_LIT
            out_margin = out_size - Δout
            if out_margin < 1
                Δin += refund_in_buf!(s)
                !signbit(Δin) || error("internal error refunding to input after partial WRITE_LIT")
                return :output, Δin, Δout
            else
                unsafe_store!(output.ptr+Δout, s.lit)
                copy_one_byte!(s, s.lit)
                Δout += 1
                s.mode = READ_BITS
            end
        elseif s.mode == DONE
            Δin += refund_in_buf!(s)
            !signbit(Δin) || error("internal error refunding to input after DONE")
            return :done, Δin + !iszero(s.bp), Δout
        else
            @assert false "unreachable"
        end
    end
end

"""
    read_input_bits!(s::StreamState)::Bool

Update the state of the stream by reading at most 64 bits.
Return false if there are not enough bits to read the next input.
Throws an error if the input is invalid. The stream must be reset to recover from this.
"""
function read_input_bits!(s::StreamState)::Bool
    if s.in_mode == HEADER_BITS
        let s=s
            local h_bits = s.in_buf & 0b111
            if !consume!(s, 0x03)
                return false
            end
            s.in_final_block = isone(h_bits & 0b1)
            local BTYPE = (h_bits>>1)
            if BTYPE == 0b00
                s.in_mode = NON_COMPRESSED_LENS
            elseif BTYPE == 0b01
                # compressed with fixed Huffman codes
                parse_huffman!(s.lit_len_tree, view(fixed_lit_len_dist_num_bits_per_op, 1:288))
                parse_huffman!(s.dist_tree, view(fixed_lit_len_dist_num_bits_per_op, 289:320))
                s.in_mode = LIT_LEN_DIST_OP
            elseif BTYPE == 0b10
                s.in_mode = NUM_CODES
            else
                throw(DecompressionError("invalid block compression mode 3"))
            end
        end
    elseif s.in_mode == NON_COMPRESSED_LENS
        let s=s
            if !consume!(s, (s.bits_left - s.bp) & 0b111)
                return false # this shouldn't happen
            end
            local len = s.in_buf%UInt16
            local nlen = (s.in_buf>>0x10)%UInt16
            if !consume!(s, 0x20)
                return false
            end
            s.mode = COPY_OUT
            s.in_mode = HEADER_BITS
            if len ⊻ nlen != 0xffff
                throw(DecompressionError("corrupted copy lengths"))
            end
            s.copy_len = len
        end
    elseif s.in_mode == NUM_CODES
        let s=s
            local x = s.in_buf%UInt16
            if !consume!(s, 0x0E)
                return false
            end
            s.nlit = x & 0b11111 + UInt16(257)
            s.ndist = x>>0x05 & 0b11111 + UInt16(1)
            s.nclen = x>>0x0A & 0b1111 + UInt16(4)
            s.in_mode = CLEN_NUM_BITS_PER_OP
        end
    elseif s.in_mode == CLEN_NUM_BITS_PER_OP
        let s=s
            local x = s.in_buf
            @assert s.nclen < 20
            if !consume!(s, (s.nclen*0x03)%UInt8)
                return false
            end
            s.clen_num_bits_per_op .= 0x00
            for i in 1:s.nclen
                s.clen_num_bits_per_op[1 + order[i]] = x & 0b111
                x >>= 0x03
            end
            parse_huffman!(s.clen_tree, s.clen_num_bits_per_op)
            s.lit_len_dist_num_bits_per_op .= 0x00
            s.num_bits_per_op_idx = 1
            s.in_mode = CLEN_OP
        end
    elseif s.in_mode == CLEN_OP
        let s=s
            local op, nbits = get_op(s.in_buf%UInt16, s.clen_tree)
            local i = s.num_bits_per_op_idx
            local n::Int
            local max_i = s.nlit + s.ndist
            @assert i ≤ max_i
            if !consume!(s, nbits)
                return false
            end
            if op < 0x0010
                s.lit_len_dist_num_bits_per_op[i] = op
                i += 1
            elseif op == 0x0010
                # Copy the previous code length 3 - 6 times.
                n = s.in_buf&0b11 + 3
                if !consume!(s, 0x02) #   The next 2 bits indicate repeat length
                    return false
                end
                if isone(i)
                    throw(DecompressionError("no previous code length to repeat"))
                elseif i + n - 1 > max_i
                    throw(DecompressionError("too many code lengths"))
                end
                s.lit_len_dist_num_bits_per_op[i:i + n - 1] .= s.lit_len_dist_num_bits_per_op[i-1]
                i += n
            elseif op == 0x0011
                # Repeat a code length of 0 for 3 - 10 times.
                n = s.in_buf&0b111 + 3
                if !consume!(s, 0x03) # (3 bits of length)
                    return false
                end
                if i + n - 1 > max_i
                    throw(DecompressionError("too many code lengths"))
                end
                s.lit_len_dist_num_bits_per_op[i:i + n - 1] .= 0x00
                i += n
            elseif op == 0x0012
                # Repeat a code length of 0 for 11 - 138 times
                n = s.in_buf&0b1111111 + 11
                if !consume!(s, 0x07) # (7 bits of length)
                    return false
                end
                if i + n - 1 > max_i
                    throw(DecompressionError("too many code lengths"))
                end
                s.lit_len_dist_num_bits_per_op[i:i + n - 1] .= 0x00
                i += n
            else
                error("unreachable")
            end
            if i > max_i
                local lit_len_num_bits_per_op = view(s.lit_len_dist_num_bits_per_op, 1:Int(s.nlit))
                local dist_num_bits_per_op = view(s.lit_len_dist_num_bits_per_op, Int(s.nlit+1):Int(s.nlit+s.ndist))
                if iszero(lit_len_num_bits_per_op[1 + 256])
                    throw(DecompressionError("no code for end-of-block"))
                end
                parse_huffman!(s.lit_len_tree, lit_len_num_bits_per_op)
                # if there are no dist codes, there also cannot be any len codes
                if all(iszero, dist_num_bits_per_op)
                    local last_lit_len_op = something(findlast(!iszero, lit_len_num_bits_per_op))
                    if last_lit_len_op > 1 + 256
                        throw(DecompressionError("no codes for distances, but there is a code for length"))
                    end
                    reset!(s.dist_tree)
                else
                    parse_huffman!(s.dist_tree, dist_num_bits_per_op)
                end
                s.in_mode = LIT_LEN_DIST_OP
            else
                s.num_bits_per_op_idx = i
            end
        end
    elseif s.in_mode == LIT_LEN_DIST_OP
        let s=s
            local op, nbits = get_op(s.in_buf%UInt16, s.lit_len_tree)
            local len::UInt32
            local dist::UInt32
            local num_extra_bits::UInt8
            if !consume!(s, nbits)
                return false
            end
            if op < 0x0100
                s.lit = op%UInt8
                s.mode = WRITE_LIT
            elseif op == 0x0100
                if s.in_final_block
                    s.mode = DONE
                else
                    s.in_mode = HEADER_BITS
                end
            else
                # read length
                if op ≤ 0x0108
                    len = UInt32(op) - UInt32(254)
                elseif op ≤ 0x011c
                    len, num_extra_bits = parse_len(op, s.in_buf%UInt16)
                    if !consume!(s, num_extra_bits)
                        return false
                    end
                elseif op == 0x011d
                    if s.deflate64
                        # If deflate 64 use next 16 bits +3 as length
                        len = s.in_buf%UInt16 + UInt32(3)
                        if !consume!(s, 0x10)
                            return false
                        end
                    else
                        len = UInt32(258)
                    end
                else
                    # unknown op
                    # if the fixed Huffman codes are used
                    # op 286 and op 287 are invalid but can be encoded.
                    throw(DecompressionError("unknown len op"))
                end
                # read dist
                op, nbits = get_op(s.in_buf%UInt16, s.dist_tree)
                if !consume!(s, nbits)
                    return false
                end
                if op ≤ 0x0003
                    dist = UInt32(op) + UInt32(1)
                else
                    dist, num_extra_bits = parse_dist(op, s.in_buf%UInt16)
                    if !consume!(s, num_extra_bits)
                        return false
                    end
                end
                s.len = len
                s.dist = dist
                s.mode = RUN_OP
            end
        end
    else
        @assert false "unreachable"
    end
    true
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

"""
    consume! `n` bits from `s`, return false if over read the input.
"""
function consume!(s::StreamState, n::UInt8)::Bool
    if n > s.bits_left
        s.in_buf = 0
        s.bits_left = 0
        false
    else
        s.in_buf >>= n
        s.bits_left -= n
        true
    end
end

"""
refund input buffer, return change in Δin
"""
function refund_in_buf!(s::StreamState)::Int64
    new_bp = Int64(s.bp) - Int64(s.bits_left)
    s.bp = (new_bp%UInt8)&0x07
    s.in_buf = 0
    s.bits_left = 0x00
    new_bp >> 3
end

"""
fill input buffer, return new Δin
"""
function refill_in_buf!(s::StreamState, input::TranscodingStreams.Memory, Δin::Int64)::Int64
    while Δin < Int64(input.size) && s.bits_left < 0x40
        x = unsafe_load(input.ptr + Δin)>>s.bp
        s.in_buf |= UInt64(x)<<s.bits_left
        new_bits_left = min(0x40, s.bits_left + 0x08 - s.bp)
        Δbits = new_bits_left - s.bits_left
        s.bp = (s.bp + Δbits)&0x07
        Δin += Int64(iszero(s.bp))
        s.bits_left = new_bits_left
    end
    Δin
end

"""
copy `n_copy` bytes from `in_ptr` into the out buffer.
"""
function copy_from_input!(s::StreamState, in_ptr::Ptr{UInt8}, u16_n_copy::UInt16)::Nothing
    n_copy = Int64(u16_n_copy)
    out_buf = s.out_buf
    out_offset = s.out_offset
    # this addition cannot overflow because n_copy and out_offset are ∈ 0:BUFFER_SIZE
    s.out_full |= (out_offset + n_copy ≥ BUFFER_SIZE)
    # n_copy_next ∈ 0:n_copy because out_offset < BUFFER_SIZE and n_copy ≥ 0
    n_copy_next = min(BUFFER_SIZE - out_offset, n_copy)::Int64
    # This is inbounds because the min above.
    GC.@preserve out_buf unsafe_copyto!(pointer(out_buf, 1 + out_offset), in_ptr, n_copy_next)
    if n_copy_next < n_copy
        # wrap around and write any extra data to the start of out_buf
        n_copy_start = n_copy - n_copy_next
        # This is inbounds because n_copy_next ∈ 0:n_copy , so n_copy_start ∈ 0:n_copy, and
        # n_copy ∈ 0:BUFFER_SIZE as a precondition
        GC.@preserve out_buf unsafe_copyto!(pointer(out_buf, 1), in_ptr + n_copy_next, n_copy_start)
    end
    s.out_offset += u16_n_copy
    nothing
end

"""
copy `n_copy` bytes from `dist` back in the out buffer into `out_ptr` and the out buffer.
this can error if `dist` goes before the start of the out buffer.
"""
function copy_from_output!(out_ptr::Ptr{UInt8}, s::StreamState, n_copy::Int64, dist::UInt32)::Nothing
    if dist > BUFFER_SIZE || iszero(dist) || (!s.out_full && s.out_offset < dist)
        throw(DecompressionError("cannot read before beginning of out buffer"))
    end
    for i in 1:n_copy
        x = s.out_buf[begin + (s.out_offset - dist%UInt16)]
        unsafe_store!(out_ptr, x)
        copy_one_byte!(s, x)
        out_ptr += 1
    end
end


"""
write one byte into the out buffer.
"""
function copy_one_byte!(s::StreamState, lit::UInt8)::Nothing
    # this should always be inbounds because s.out_offset is a UInt16
    # and s.out_buf is length 2^16
    @inbounds s.out_buf[begin + s.out_offset] = lit
    s.out_offset += UInt16(1)
    s.out_full |= iszero(s.out_offset)
    nothing
end