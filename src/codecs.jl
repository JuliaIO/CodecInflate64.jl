# Glue code for TranscodingStreams

abstract type DecompressorCodec <: TranscodingStreams.Codec end

"""
    DeflateDecompressor()

Create a deflate decompression codec.
"""
struct DeflateDecompressor <: DecompressorCodec
    s::StreamState
end
DeflateDecompressor() = DeflateDecompressor(StreamState(deflate64=false))

const DeflateDecompressorStream{S} = TranscodingStream{DeflateDecompressor,S} where S<:IO

"""
    DeflateDecompressorStream(stream::IO; kwargs...)

Create a deflate decompression stream.
"""
DeflateDecompressorStream(stream::IO; kwargs...) = TranscodingStream(DeflateDecompressor(), stream; kwargs...)

"""
    Deflate64Decompressor()

Create a deflate64 decompression codec.
"""
struct Deflate64Decompressor <: DecompressorCodec
    s::StreamState
end
Deflate64Decompressor() = Deflate64Decompressor(StreamState(deflate64=true))

const Deflate64DecompressorStream{S} = TranscodingStream{Deflate64Decompressor,S} where S<:IO

"""
    Deflate64DecompressorStream(stream::IO; kwargs...)

Create a deflate64 decompression stream.
"""
Deflate64DecompressorStream(stream::IO; kwargs...) = TranscodingStream(Deflate64Decompressor(), stream; kwargs...)

function Base.show(io::IO, codec::DecompressorCodec)
    print(io, summary(codec), "()")
end

function TranscodingStreams.startproc(codec::DecompressorCodec, ::Symbol, error_ref::TranscodingStreams.Error)
    reset!(codec.s)
    :ok
end

function TranscodingStreams.process(
        codec     :: DecompressorCodec,
        input     :: TranscodingStreams.Memory,
        output    :: TranscodingStreams.Memory,
        error_ref :: TranscodingStreams.Error,
    )
    all_in = iszero(input.size)
    # @show "proccall" input.size output.size
    # done, in2, out2 = main_run!(all_in, input, output, codec.s) 
    done, in2, out2 = try
        main_run!(all_in, input, output, codec.s)
    catch e
        # rethrow()
        e isa InterruptException && rethrow()
        error_ref[] = e
        return 0, 0, :error
    end
    Δin::Int = input.size - in2.size
    Δout::Int = output.size - out2.size
    if done
        return Δin, Δout, :end
    else
        return Δin, Δout, :ok
    end
end