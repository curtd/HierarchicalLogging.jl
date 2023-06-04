using HierarchicalLogging

# Aqua is unhappy with Dictionaries.jl on Julia 1.6
if VERSION ≥ v"1.9"
    using Aqua
    Aqua.test_all(HierarchicalLogging)
end

include("TestHierarchicalLogging.jl")