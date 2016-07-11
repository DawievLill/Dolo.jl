module DoloTests

using Dolo
using Compat
using DataStructures

if VERSION >= v"0.5-"
    using Base.Test
else
    using BaseTestNext
    const Test = BaseTestNext
end

tests = length(ARGS) > 0 ? ARGS : ["numeric",
                                   "parser",
                                   "util",
                                   "model_types",
                                   "model_import"]
for t in tests
    include("$(t).jl")
end

end  # module
