using CleanUpPullRequestPreviews
using Documenter

makedocs(;
    modules=[CleanUpPullRequestPreviews],
    authors="Brown Center for Biomedical Informatics",
    repo="https://github.com/bcbi/CleanUpPullRequestPreviews.jl/blob/{commit}{path}#L{line}",
    sitename="CleanUpPullRequestPreviews.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://bcbi.github.io/CleanUpPullRequestPreviews.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/bcbi/CleanUpPullRequestPreviews.jl",
)
