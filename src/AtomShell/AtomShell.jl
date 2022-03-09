module AtomShell

using Sockets
using WebIO
using RelocatableFolders

abstract type Shell end

include("install.jl")
include("process.jl")
include("window.jl")
include("webio.jl")

end
