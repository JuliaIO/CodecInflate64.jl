module CodecInflate64

export DeflateDecompressor
export DeflateDecompressorStream
export Deflate64Decompressor
export Deflate64DecompressorStream
export DecompressionError

include("errors.jl")
include("huffmantree.jl")
include("stream.jl")
include("codecs.jl")

end