using StableRNGs: StableRNG

# This script will create a "testdata" directory
# This directory can be compressed on windows to create
# a test for deflate64
# To compress, open the directory in File Explorer
# Then press ctrl A to select all the files.
# Next right click, and press "Compress to ZIP file" button.

rng = StableRNG(1234)

rm("testdata"; recursive=true, force=true)
dir = mkdir("testdata")

write(joinpath(dir,"abig.dat"), zeros(UInt8, 2^31))
for i in 0:500
    write(joinpath(dir,"small$(i).dat"), zeros(UInt8, i))
end

thing = rand(rng, UInt8, 200)
d = UInt8[]
for dist in [0:258; 1000:1030; 2000:1000:33000; 34000:10000:100_000]
    append!(d, thing)
    append!(d, rand(rng, 0x00:0x0f, dist))
end
write(joinpath(dir, "dist-rand.dat"), d)

for n in 65536-300:65536-100
    write(joinpath(dir, "dist-$(n).dat"), [thing; zeros(UInt8, n); thing])
end

write(joinpath(dir, "incomp.dat"), rand(rng, UInt8, 400_000))

# Finally write this file
write(joinpath(dir, "gen_files.jl"), read(@__FILE__))