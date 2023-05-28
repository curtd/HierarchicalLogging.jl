using HierarchicalLogging
using Documenter

DocMeta.setdocmeta!(HierarchicalLogging, :DocTestSetup, :(using HierarchicalLogging); recursive=true)

makedocs(;
    modules=[HierarchicalLogging],
    authors="Curt Da Silva <curt.dasilva@gmail.com>",
    repo="https://github.com/curtd/HierarchicalLogging.jl/blob/{commit}{path}#{line}",
    sitename="HierarchicalLogging.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://curtd.github.io/HierarchicalLogging.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/curtd/HierarchicalLogging.jl",
    devbranch="main",
)
