using Bitbucket
using Documenter

DocMeta.setdocmeta!(Bitbucket, :DocTestSetup, :(using Bitbucket); recursive=true)

makedocs(;
    modules=[Bitbucket],
    authors="Conrad Wiebe <miniging13@gmail.com",
    repo="https://github.com/Cyrannosaurus/Bitbucket.jl/blob/{commit}{path}#{line}",
    sitename="Bitbucket.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Cyrannosaurus.github.io/Bitbucket.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/Cyrannosaurus/Bitbucket.jl.git",
    devbranch="main",
)
