# Worker-thread effect prewarm needs nthreads ≥ 2. `julia Run.jl` defaults to 1.
# `--trace-compile` belongs to this process only, so the restart has to carry it
# or additional_precompile.jl stays empty while the game runs in the child.
if Threads.nthreads() < 2 && get(ENV, "BATTLER_SKIP_THREAD_REEXEC", "0") != "1"
    env = copy(ENV)
    env["JULIA_NUM_THREADS"] = "auto"
    env["BATTLER_SKIP_THREAD_REEXEC"] = "1"
    project = something(Base.active_project(), joinpath(@__DIR__, ".."))
    script = abspath(PROGRAM_FILE)
    trace_ptr = Base.JLOptions().trace_compile
    trace = trace_ptr == C_NULL ? "" : unsafe_string(trace_ptr)
    trace_arg = isempty(trace) ? `` : `--trace-compile=$(abspath(trace))`
    run(setenv(`$(Base.julia_cmd()) --threads=auto --project=$(project) $trace_arg $(script) $(ARGS)`, env))
    exit()
end

if get(ENV, "BATTLER_DEV", "0") == "1"
    # Dev/trace-compile path: always fresh by directly including sources.
    include(joinpath(@__DIR__, "Battler.jl"))
    using .Battler
else
    # Default path: rely on package precompilation/pkgsystem cache.
    using Battler
end

if get(ENV, "PROFILE", "0") != "1"
    Battler.julia_main()
end
