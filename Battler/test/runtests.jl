using Test
using PackageCompiler
using JulGame
ENV["TEST_MODE"] = "true"

ROOTDIR = joinpath(@__DIR__, "..")
include(joinpath(ROOTDIR, "src", "Battler.jl"))

# Steam Linux fails with "missing downloaded files" on Julia artifact dir aliases
# (ncurses -> ncursesw, icu/current -> 68.2). Duplicating them makes steamcmd emit
# manifest paths with no chunks; drop the aliases and copy file symlinks instead.
function flatten_depot_tree!(root::AbstractString; skip_runtime_libs::Bool=Sys.isapple())
    runtime_lib = joinpath(abspath(root), "lib")
    skipped(p) = skip_runtime_libs && startswith(abspath(p), runtime_lib)
    alias_dirs = String[]
    links = String[]
    for (dir, dirs, files) in walkdir(root; follow_symlinks=false)
        if "ncurses" in dirs && "ncursesw" in dirs
            push!(alias_dirs, joinpath(dir, "ncurses"))
        end
        if basename(dir) == "icu" && "current" in dirs
            push!(alias_dirs, joinpath(dir, "current"))
        end
        for name in Iterators.flatten((dirs, files))
            p = joinpath(dir, name)
            islink(p) && !skipped(p) && push!(links, p)
        end
    end
    for p in alias_dirs
        ispath(p) && rm(p; recursive=true)
    end
    sort!(links; by=p -> count(c -> c == '/' || c == '\\', p), rev=true)
    for p in links
        islink(p) || continue
        if isdir(p)
            rm(p)
            continue
        end
        target = try
            realpath(p)
        catch
            @warn "Skipping dangling symlink $p"
            continue
        end
        tmp = p * ".materialized"
        ispath(tmp) && rm(tmp; recursive=true)
        cp(target, tmp)
        rm(p)
        mv(tmp, p)
    end
    println("Flattened depot tree under $root (removed $(length(alias_dirs)) alias dir(s), $(length(links)) symlink(s))")
end

@testset "All tests" begin
    include(joinpath(@__DIR__, "unit", "unittests.jl"))
    @testset "Unit tests" begin
        @debug "Running unit tests"
        UnitTests.run_unit_tests()
    end

    cd(joinpath(ROOTDIR, "src"))
    @testset "Battler" begin
        @debug "Running Battler"
        # ENV["TEST_MODE"] = "true"
        # @test Battler.run() == 0
    end

    @testset "Generate precompile statements" begin
        @debug "Generating precompile statements"
        #ENV["JULIA_DEBUG"] = "all"
        ENV["TEST_MODE"] = "true"
        ENV["TEST_LENGTH"] = "300.0"
        ENV["SKIP_PRECOMPILE"] = "true"
        ENV["SKIP"] = "true"
        ENV["JULIA_DEBUG"] = "TestManagerModule"
        ENV["BATTLER_DEV"] = "1"
        # Run with real-time output
        @debug "Running precompile with real-time output:"
        # --threads=auto prevents Run.jl's single-thread re-exec, which would run the
        # game in a child process that --trace-compile doesn't follow.
        result = run(`
            julia --project=.. --threads=auto --trace-compile=additional_precompile.jl Run.jl
        `, wait=true)
        @test result.exitcode == 0
        traced = count(l -> startswith(strip(l), "precompile("), readlines(joinpath(ROOTDIR, "src", "additional_precompile.jl")))
        println("Traced $traced precompile statements")
        @test traced > 100  # a real game run traces thousands; a handful means tracing missed the game process

        # clean precompile statements
        @debug "Cleaning precompile statements with real-time output:"
        cd(joinpath(ROOTDIR, ".."))
        result = run(`julia clean_precompile.jl`, wait=true)
        @test result.exitcode == 0
    end

    @testset "Build and run app" begin
        @debug "Building and running app"
        file_extension = Sys.iswindows() ? ".exe" : ""
        # Check the environment variable to conditionally run create_app
        if get(ENV, "SHOULD_BUILD", "false") == "true"
            println("Building the app...")
            cd(joinpath(ROOTDIR, ".."))
            
            ENV["PackageCompiling"] = "true"
            ENV["SKIP_PRECOMPILE"] = "false"

            # Wrapped try/catch file for include() during module load (dev startup).
            println("Syncing wrapped precompile statements into always_precompile.jl...")
            cp(
                joinpath(ROOTDIR, "src", "additional_precompile.jl"),
                joinpath(ROOTDIR, "src", "always_precompile.jl");
                force=true
            )

            # Bare precompile(...) lines for PackageCompiler's sysimage staging pass.
            statements_file = joinpath(ROOTDIR, "src", "additional_precompile_statements.jl")
            isfile(statements_file) || error("missing $statements_file — clean_precompile.jl should have written it")
            println("Using PackageCompiler precompile_statements_file → $statements_file")

            println("Preparing release asset bundle...")
            # npm is a .cmd batch file on Windows, which can't be spawned directly
            npm_cmd = Sys.iswindows() ?
                `cmd /c npm --prefix Battler run prepare:release-bundle` :
                `npm --prefix Battler run prepare:release-bundle`
            prepare_result = run(npm_cmd, wait=true)
            @test prepare_result.exitcode == 0

            # PackageCompiler's force cleanup can fail with ENOTEMPTY on nested dirs (e.g. artifacts).
            build_output = joinpath(pwd(), "Build")
            isdir(build_output) && rm(build_output; recursive=true)

            project_toml = joinpath("Battler", "Project.toml")
            manifest_toml = joinpath("Battler", "Manifest.toml")
            project_bak = read(project_toml)
            manifest_bak = isfile(manifest_toml) ? read(manifest_toml) : nothing
            try
                if Sys.isapple()
                    # Evict GameDataManager/XLSX so create_app cannot copy their JLLs
                    # even with include_lazy_artifacts=true.
                    import Pkg
                    Pkg.activate("Battler")
                    Pkg.rm(["GameDataManager", "XLSX"])
                end
                create_app(
                    "Battler",
                    "Build";
                    precompile_statements_file=statements_file,
                    sysimage_build_args=`--strip-metadata`,
                    # Linux keeps GDM and must omit those lazy JLL trees.
                    # Mac drops GDM/XLSX above, so leftover lazy artifacts are fine.
                    include_lazy_artifacts=!Sys.islinux(),
                    force=true,
                )
            finally
                write(project_toml, project_bak)
                if manifest_bak !== nothing
                    write(manifest_toml, manifest_bak)
                end
            end
            # Same Steam "missing downloaded files" fix as Linux. On macOS,
            # flatten leaves Build/lib dylibs alone so the sysimage still loads.
            flatten_depot_tree!(build_output)

            # Live-data / GameDataManager needs config.json + xlsx/json on disk next
            # to the relocated app (sysimage @__DIR__ points at the CI checkout).
            # Mac release does not compile live data, so skip the extra copy.
            if !Sys.isapple()
                gdm_src = joinpath(ROOTDIR, "assets", "game-data-manager")
                gdm_dst = joinpath(build_output, "assets", "game-data-manager")
                isdir(gdm_src) || error("missing game-data-manager at $gdm_src")
                mkpath(dirname(gdm_dst))
                cp(gdm_src, gdm_dst; force=true)
                println("Bundled game-data-manager → $gdm_dst")
            else
                println("Skipping game-data-manager bundle on macOS release")
            end

            @debug("App built successfully")
            @debug "Running built app with real-time output:"
            # Run in a subprocess so we can hide Battler subdirs without renaming
            # the project root (Windows locks the active --project=Battler path).
            relocation_script = joinpath(@__DIR__, "relocation_smoke_test.jl")
            battler_root = joinpath(pwd(), "Battler")
            result = 0
            try
                result = run(`julia $relocation_script $(pwd()) $file_extension`, wait=true).exitcode
            finally
                # Always restore — CI copies config/steam files from Battler/ after Pkg.test().
                include(relocation_script)
                ensure_battler_paths_restored!(battler_root)
            end
            for rel in ("config.julgame", "src/steam_appid.txt")
                @test isfile(joinpath(battler_root, split(rel, '/')...))
            end
            if Sys.islinux()
                @test isfile(joinpath(battler_root, "libsteam_api.so"))
            elseif Sys.isapple()
                @test isfile(joinpath(battler_root, "libsteam_api.dylib"))
            elseif Sys.iswindows()
                @test isfile(joinpath(battler_root, "steam_api64.dll"))
            end
            println("The command exited with code: ", result)
            @test result == 0
        else
            println("Skipping app build because SHOULD_BUILD is false.")
        end
    end
end
