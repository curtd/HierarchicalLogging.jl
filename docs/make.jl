using Documenter

using Pkg
docs_dir = joinpath(@__DIR__, "..")
project_dir = isempty(ARGS) ? @__DIR__() : joinpath(pwd(), ARGS[1])
Pkg.activate(project_dir)

using HierarchicalLogging

DocMeta.setdocmeta!(HierarchicalLogging, :DocTestSetup, :(using HierarchicalLogging); recursive=true)

makedocs(;
    modules=[HierarchicalLogging],
    authors="Curt Da Silva",
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
        "API" => "api.md"
    ],
    warnonly=:missing_docs
)

deploydocs(;
    repo="github.com/curtd/HierarchicalLogging.jl.git",
    devbranch="main", push_preview=true
)
