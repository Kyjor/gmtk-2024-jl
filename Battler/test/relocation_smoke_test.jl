#!/usr/bin/env julia
# Hides Battler runtime source paths, runs the built exe, then restores them.
# Invoked as a separate process so the test runner can keep Battler loaded
# (Windows locks the active project root if we rename Battler/ itself).

# Only hide runtime data dirs. Don't hide src/scripts — the test runner keeps
# Battler loaded (Windows can't restore locked dirs), and CI copies from src/.
const HIDE_DIRS = ("assets", "scenes", "release-bundle")

function hidden_path(battler_root::String, name::String)
    joinpath(battler_root, ".relocation_test_hidden_$name")
end

function hide_paths!(battler_root::String)
    hidden = String[]
    for name in HIDE_DIRS
        src = joinpath(battler_root, name)
        isdir(src) || continue
        mv(src, hidden_path(battler_root, name))
        push!(hidden, name)
    end
    isempty(hidden) && error("relocation smoke test: no paths to hide under $battler_root")
    return hidden
end

function restore_paths!(battler_root::String, hidden::Vector{String})
    for name in hidden
        src = hidden_path(battler_root, name)
        dst = joinpath(battler_root, name)
        isdir(src) || continue
        isdir(dst) && rm(dst; recursive=true, force=true)
        mv(src, dst)
    end
end

function ensure_battler_paths_restored!(battler_root::String)
    # Include legacy names so a prior failed run can't strand src/ for CI copy steps.
    legacy = ("scripts", "src")
    for name in (HIDE_DIRS..., legacy...)
        hidden = hidden_path(battler_root, name)
        dst = joinpath(battler_root, name)
        isdir(hidden) || continue
        isdir(dst) && rm(dst; recursive=true, force=true)
        mv(hidden, dst)
    end
end

function main()
    repo_root = ARGS[1]
    ext = length(ARGS) >= 2 ? ARGS[2] : ""
    battler_root = joinpath(repo_root, "Battler")
    exe = joinpath(repo_root, "Build", "bin", "Battler$ext")

    hidden = String[]
    try
        hidden = hide_paths!(battler_root)
        ENV["BUILD_MODE_TEST"] = "true"
        result = run(`$exe`, wait=true)
        exit(result.exitcode)
    finally
        restore_paths!(battler_root, hidden)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
