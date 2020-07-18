module CleanUpPullRequestPreviews

import GitHub
import HTTP

export remove_old_previews

struct AlwaysAssertionError <: Exception
    msg::String
end

function always_assert(cond::Bool, message::String)
    cond || throw(AlwaysAssertionError(message))
    return nothing
end

struct PRandPath
    pr::Int 
    path::String
end

struct Config
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
                email_address::AbstractString = "41898282+github-actions[bot]@users.noreply.github.com",
                git_command::AbstractString = "git",
                my_regex::Regex,
                num_samples::Integer = 3,
                push_to_origin::Bool = true,
                repo_main::AbstractString,
                repo_previews::AbstractString,
                repo_previews_branch::AbstractString,
                sample_delay_seconds::Integer = 60,
                username::AbstractString = "github-actions[bot]",
                )
    result = Config(
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
                             auth::GitHub.Authorization = GitHub.authenticate(ENV["GITHUB_TOKEN"]),
                             kwargs...)
    config = Config(; kwargs...)
    remove_old_previews(api, auth, config)::Nothing
    return nothing
end

"""
    remove_old_previews

Remove old pull request previews.
"""
function remove_old_previews(api::GitHub.GitHubAPI,
                             auth::GitHub.Authorization,
                             config::Config)
    original_directory::String = pwd()::String
    clone_directory::String = _git_clone(api, auth, config)::String
    prs_and_paths::Vector{PRandPath} = _get_prs_and_paths(api, auth, config, clone_directory)::Vector{PRandPath}
    pr_is_open::Dict{Int, Bool} = _pr_is_open(api, auth, config, prs_and_paths)::Dict{Int, Bool}
    _delete_preview_directories(api, auth, config, clone_directory, prs_and_paths, pr_is_open)::Nothing
    _git_add_commit_push(api, auth, config, clone_directory)::Nothing
    cd(original_directory)
    rm(clone_directory; force = true, recursive = true)
    return nothing
end

function _git_clone(api::GitHub.GitHubAPI,
                    auth::GitHub.Authorization,
                    config::Config)::String
    parent_dir = mktempdir()
    atexit(() -> rm(parent_dir; force = true, recursive = true))
    original_directory = pwd()
    cd(parent_dir)
    run(`$(config.git_command) clone $(config.repo_previews) CLONEDIRECTORY`)
    clone_directory::String = joinpath(parent_dir, "CLONEDIRECTORY")::String
    cd(clone_directory)
    run(Cmd(String[config.git_command, "config", "user.name", strip(config.username)]))
    run(Cmd(String[config.git_command, "config", "user.email", strip(config.email_address)]))
    run(`$(config.git_command) checkout $(config.repo_previews_branch)`)
    cd(original_directory)
    return clone_directory
end

function _get_prs_and_paths(api::GitHub.GitHubAPI,
                            auth::GitHub.Authorization,
                            config::Config,
                            root_directory::AbstractString)::Vector{PRandPath}
    result::Vector{PRandPath} = Vector{PRandPath}(undef, 0)::Vector{PRandPath}
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
                     auth::GitHub.Authorization,
                     config::Config,
                     prs_and_paths)::Dict{Int, Bool}
    list_of_all_pr_numbers::Vector{Int} = Int[pr_and_path.pr for pr_and_path in prs_and_paths]::Vector{Int}
    unique!(list_of_all_pr_numbers)
    sort!(list_of_all_pr_numbers)

    intermediate = Vector{Dict{Int, Bool}}(undef, config.num_samples)
    for i = 1:config.num_samples
        intermediate[i] = Dict{Int, Bool}()
    end

    for i = 1:config.num_samples
        if i != 1
            @info("Waiting for $(config.sample_delay_seconds) second(s)...")
            sleep(config.sample_delay_seconds)
        end
        for pr_number in list_of_all_pr_numbers
            @info("Getting state of PR # $(pr_number)")
            github_pr = GitHub.pull_request(api,
                                            config.repo_main,
                                            pr_number;
                                            auth = auth)
            github_pr_is_open = github_pr.state != "closed"
            intermediate[i][pr_number] = github_pr_is_open
        end
    end

    result::Dict{Int, Bool} = Dict{Int, Bool}()::Dict{Int, Bool}

    for pr_number in list_of_all_pr_numbers
        pr_intermediates = Vector{Bool}(undef, config.num_samples)
        for i = 1:config.num_samples
            pr_intermediates[i] = intermediate[i][pr_number]
        end
        result[pr_number] = any(pr_intermediates)
        @info("PR # $(pr_number) is open: $(result[pr])")
    end

    return result
end

function _git_add_commit_push(api::GitHub.GitHubAPI,
                              auth::GitHub.Authorization,
                              config::Config,
                              clone_directory::AbstractString)::Nothing
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
                                     auth::GitHub.Authorization,
                                     config::Config,
                                     clone_directory::AbstractString,
                                     prs_and_paths::Vector{PRandPath},
                                     pr_is_open::Dict{Int, Bool})::Nothing
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
