"""
    struct DecompressionError <: Exception

The data is not valid for decompression
"""
struct DecompressionError <: Exception
    msg::String
end

function Base.showerror(io::IO, err::DecompressionError)
    print(io, "DecompressionError: ")
    print(io, err.msg)
end
