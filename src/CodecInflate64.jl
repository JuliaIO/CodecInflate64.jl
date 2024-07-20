module CodecInflate64

export DeflateDecompressor
export DeflateDecompressorStream
export Deflate64Decompressor
export Deflate64DecompressorStream

include("huffmantree.jl")
include("stream.jl")
include("codecs.jl")

end