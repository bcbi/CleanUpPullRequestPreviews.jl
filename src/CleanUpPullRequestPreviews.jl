module CleanUpPullRequestPreviews

import GitHub
import HTTP

export remove_old_previews

struct PRandPath
    pr::Int 
    path::String
end

struct Config{A <: GitHub.Authorization}
    auth::A
    email_address::String
    git_command::String
    my_regex::Regex
    num_samples::Int
    push_to_origin::Bool
    repo_main::String
    repo_previews::String
    repo_previews_branch::String
    sample_delay_seconds::Int
    username::String
end

function Config(;
                auth::GitHub.Authorization = GitHub.authenticate(ENV["GITHUB_TOKEN"]),
                email_address::AbstractString = "41898282+github-actions[bot]@users.noreply.github.com",
                git_command::AbstractString = "git",
                my_regex::Regex = r"^\.\/previews\/PR(\d*)$",
                num_samples::Integer = 3,
                push_to_origin::Bool = true,
                repo_main::AbstractString,
                repo_previews::AbstractString,
                repo_previews_branch::AbstractString,
                sample_delay_seconds::Integer = 60,
                username::AbstractString = "github-actions[bot]",
                )
    result = Config(
        auth,
        email_address,
        git_command,
        my_regex,
        num_samples,
        push_to_origin,
        repo_main,
        repo_previews,
        repo_previews_branch,
        sample_delay_seconds,
        username,
    )
    return result
end

"""
    remove_old_previews

Remove old pull request previews.
"""
function remove_old_previews(;
                             api::GitHub.GitHubAPI = GitHub.GitHubWebAPI(HTTP.URI("https://api.github.com")),
                             kwargs...)
    config = Config(; kwargs...)

    clone_directory = _git_clone(api, config)::String
    prs_and_paths = _get_prs_and_paths(api, config, clone_directory)::Vector{PRandPath}
    pr_is_open = _pr_is_open(api, config, prs_and_paths)::Dict{Int, Bool}
    _delete_preview_directories(api, config, clone_directory, prs_and_paths, pr_is_open)::Nothing
    _git_add_commit_push(api, config, clone_directory)::Nothing
    return nothing
end


function _git_clone(api::GitHub.GitHubAPI,
                    config::Config)
    parent_dir = mktempdir()
    atexit(() -> rm(parent_dir; force = true, recursive = true))
    original_directory = pwd()
    cd(parent_dir)
    run(`$(config.git_command) clone $(config.repo_previews) CLONEDIRECTORY`)
    clone_directory = joinpath(parent_dir, "CLONEDIRECTORY")
    cd(clone_directory)
    run(Cmd(String[config.git_command, "config", "user.name", strip(config.username)]))
    run(Cmd(String[config.git_command, "config", "user.email", strip(config.email_address)]))
    run(`$(config.git_command) checkout $(config.repo_previews_branch)`)
    cd(original_directory)
    return clone_directory
end

function _get_prs_and_paths(api::GitHub.GitHubAPI,
                            config::Config,
                            root_directory::AbstractString)
    result = Vector{PRandPath}(undef, 0)
    original_directory = pwd()
    cd(root_directory)
    for (root, dirs, files) in walkdir(".")
        for dir in dirs
            path = joinpath(root, dir)
            m = match(config.my_regex, path)
            if m !== nothing
                pr = parse(Int, m[1])
                push!(result, PRandPath(pr, path))
            end
        end
    end
    cd(original_directory)
    return result
end

function _pr_is_open(api::GitHub.GitHubAPI,
                     config::Config,
                     prs_and_paths)
    auth = config.auth
    num_samples = config.num_samples
    sample_delay_seconds = config.sample_delay_seconds

    intermediate = Vector{Dict{Int, Bool}}(undef, num_samples)
    for i = 1:num_samples
        intermediate[i] = Dict{Int, Bool}()
    end
    for i = 1:num_samples
        @info("Waiting for $(sample_delay_seconds) second(s)...")
        sleep(sample_delay_seconds)
        for pr_and_path in prs_and_paths
            pr = pr_and_path.pr 
            @info("Getting state of PR # $(pr)")
            github_pr = GitHub.pull_request(api,
                                            config.repo_main,
                                            pr;
                                            auth = auth)
            github_pr_is_open = github_pr.state == "open"
            intermediate[i][pr] = github_pr_is_open
        end
    end
    result = Dict{Int, Bool}()
    for pr_and_path in prs_and_paths
        pr = pr_and_path.pr 
        pr_intermediates = Vector{Bool}(undef, num_samples)
        for i = 1:num_samples
            pr_intermediates[i] = intermediate[i][pr]
        end
        result[pr] = any(pr_intermediates)
        @info("PR # $(pr) is open: $(result[pr])")
    end 
    return result
end

function _git_add_commit_push(api::GitHub.GitHubAPI,
                              config::Config,
                              clone_directory::AbstractString)
    original_directory = pwd()
    cd(clone_directory)
    run(`$(config.git_command) add -A`)
    run(`$(config.git_command) commit -m "Automated commit created by CleanUpPullRequestPreviews.jl"`)
    if config.push_to_origin
        run(`$(config.git_command) push origin --all`)
    end
    cd(original_directory)
    return nothing
end

function _delete_preview_directories(api::GitHub.GitHubAPI,
                                     config::Config,
                                     clone_directory::AbstractString,
                                     prs_and_paths::Vector{PRandPath},
                                     pr_is_open::Dict{Int, Bool})
    original_directory = pwd()
    for pr_and_path in prs_and_paths
        pr = pr_and_path.pr 
        path = pr_and_path.path
        this_pr_is_open = pr_is_open[pr]
        if !this_pr_is_open
            cd(clone_directory)
            @info("Removing \"$(path)\"")
            rm(path; force = true, recursive = true)
        end
    end 
    cd(original_directory)
    return nothing
end

end  # end module CleanUpPullRequestPreviews
