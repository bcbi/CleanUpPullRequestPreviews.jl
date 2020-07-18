# CleanUpPullRequestPreviews

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://bcbi.github.io/CleanUpPullRequestPreviews.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://bcbi.github.io/CleanUpPullRequestPreviews.jl/dev)
[![Build Status](https://github.com/bcbi/CleanUpPullRequestPreviews.jl/workflows/CI/badge.svg)](https://github.com/bcbi/CleanUpPullRequestPreviews.jl/actions)
[![Coverage](https://codecov.io/gh/bcbi/CleanUpPullRequestPreviews.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/bcbi/CleanUpPullRequestPreviews.jl)

CleanUpPullRequestPreviews automatically deletes old pull request previews from Documenter, Franklin, etc.

## Example usage

### Step 1:

Create a file named `.ci/Project.toml` with the following contents:
```toml
[deps]
CleanUpPullRequestPreviews = "06c59129-2005-40e8-8e6e-18d91e04568a"
```

### Step 2:

Make sure that you have a deploy key with write permissions on `JuliaHealth/juliahealth.github.io-previews`, and the private key for this deploy key is available as a secret named `FRANKLIN_PRIV_PREVIEW`.

Create a file named `.github/workflows/CleanUpPullRequestPreviews.yml` with the following contents:
```yaml
name: CleanUpPullRequestPreviews

on:
  schedule:
    - cron: '00 00 * * *' # run one time per day

jobs:
  CleanUpPullRequestPreviews:
    runs-on: ubuntu-latest
    steps:
      - name: Install SSH Client (pull request previews)
        uses: webfactory/ssh-agent@v0.2.0
        with:
          ssh-private-key: ${{ secrets.FRANKLIN_PRIV_PREVIEW }}
      - run: julia --project=.ci/ -e 'using Pkg; Pkg.instantiate()'
      - name: CleanUpPullRequestPreviews.remove_old_previews
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: julia -e 'using CleanUpPullRequestPreviews; CleanUpPullRequestPreviews.remove_old_previews(; repo_main = "JuliaHealth/juliahealth.github.io", repo_previews = "git@github.com:JuliaHealth/juliahealth.github.io-previews.git", repo_previews_branch = "gh-pages")'
```
