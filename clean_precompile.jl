#!/usr/bin/env julia

# This script removes lines containing 'var"#' from additional_precompile.jl

const MAX_PRECOMPILE_STATEMENTS = 4500

function wrap_in_try_catch(line)
    stripped = strip(line)
    if isempty(stripped)
        return line
    end
    return """try
    $stripped
catch e
    println(e)
end"""
end

function clean_precompile_file(input_file, output_file=input_file; progress_step=10)
    # Read the input file
    lines = readlines(input_file)

    filtered_lines = lines
    # Filter out lines containing 'var"#'
    #filtered_lines = filter(line -> !occursin("var\"#", line), lines)

    # Filter out lines containing 'julia_main'
    filtered_lines = filter(line -> !occursin("julia_main", line), filtered_lines)

    # Filter out lines containing '_jll'
    filtered_lines = filter(line -> !occursin("_jll", line), filtered_lines)

    # Filter out get_all_files
    filtered_lines = filter(line -> !occursin("get_all_files", line), filtered_lines)

    # Filter out lines containing 'precompile(Tuple{typeof(Battler.run)})'
    filtered_lines = filter(line -> !occursin("precompile(Tuple{typeof(Battler.run)})", line), filtered_lines)

    # Filter out lines containing 'precompile(Tuple{Type{Random.Sampler{E} where E}'
    filtered_lines = filter(line -> !occursin("Random.", line), filtered_lines)

    # Filter out lines containing 'Dates.'
    filtered_lines = filter(line -> !occursin("Dates.", line), filtered_lines)

    # Filter out lines containing 'OpenSSL.'
    filtered_lines = filter(line -> !occursin("OpenSSL.", line), filtered_lines)

    # Whenever we see 'SimpleDirectMediaLayer' without JulGame. in front of it, replace it with 'JulGame.SimpleDirectMediaLayer'
    filtered_lines = map(filtered_lines) do line
        # Use regex to replace SimpleDirectMediaLayer only when NOT preceded by JulGame.
        replace(line, r"(?<!JulGame\.)SimpleDirectMediaLayer" => "JulGame.SimpleDirectMediaLayer")
    end

    # Filter out lines containing 'JLLWrappers'
    filtered_lines = filter(line -> !occursin("JLLWrappers", line), filtered_lines)

    # Filter out lines containing 'Requires.'
    filtered_lines = filter(line -> !occursin("Requires.", line), filtered_lines)

    # Filter out lines containing '.__init__'
    filtered_lines = filter(line -> !occursin(".__init__", line), filtered_lines)
    
    # Filter out lines containing 'Base.var"##'
    filtered_lines = filter(line -> !occursin("Base.var\"#", line), filtered_lines)

    # Filter out lines containing 'MappingRF'
    filtered_lines = filter(line -> !occursin("MappingRF", line), filtered_lines)

    # Filter out lines containing 'var"##'
    filtered_lines = filter(line -> !occursin("var\"##", line), filtered_lines)

    # Filter out lines containing 'StructTypes'
    filtered_lines = filter(line -> !occursin("StructTypes", line), filtered_lines)

    # Filter out lines containing 'HTTP'
    filtered_lines = filter(line -> !occursin("HTTP", line), filtered_lines)

    # Filter out lines containing 'Sockets'
    filtered_lines = filter(line -> !occursin("Sockets", line), filtered_lines)

    # Filter out lines containing '#log_error'
    filtered_lines = filter(line -> !occursin("#log_error", line), filtered_lines)
    
    # Filter out lines containing '#log_warning'
    filtered_lines = filter(line -> !occursin("#log_warning", line), filtered_lines)
    
    # Filter out lines containing '#log_info'
    filtered_lines = filter(line -> !occursin("#log_info", line), filtered_lines)
    
    # Filter out lines containing '#log_debug'
    filtered_lines = filter(line -> !occursin("#log_debug", line), filtered_lines)
    
    # Filter out lines containing 'Mmap'
    filtered_lines = filter(line -> !occursin("Mmap", line), filtered_lines)

    # Filter out lines containing 'Downloads'
    filtered_lines = filter(line -> !occursin("Downloads", line), filtered_lines)

    # Filter out lines containing 'LibCURL'
    filtered_lines = filter(line -> !occursin("LibCURL", line), filtered_lines)

    # Filter out lines containing 'LibSSH2'
    filtered_lines = filter(line -> !occursin("LibSSH2", line), filtered_lines)

    # Filter out lines containing 'Bzip2_jll'
    filtered_lines = filter(line -> !occursin("Bzip2_jll", line), filtered_lines)

    # Filter out lines containing 'Parsers.'
    filtered_lines = filter(line -> !occursin("Parsers.", line), filtered_lines)
    
    # Filter out lines containing 'var"#'
   # filtered_lines = filter(line -> !occursin("var\"#", line), filtered_lines)
    # Filter out lines containing 'ExceptionUnwrapping'
    filtered_lines = filter(line -> !occursin("ExceptionUnwrapping", line), filtered_lines)

    # Filter out lines containing 'EzXML'
    filtered_lines = filter(line -> !occursin("EzXML", line), filtered_lines)

    # Filter out lines containing 'TestManager' (automated test run only)
    filtered_lines = filter(line -> !occursin("TestManager", line), filtered_lines)
    
    # Bare precompile(...) lines only — PackageCompiler's statements reader
    # parses one call per line and skips everything else.
    statement_lines = unique(strip.(filter(line -> startswith(strip(line), "precompile("), filtered_lines)))

    # Ubuntu hosted runners run out of memory building the sysimage above ~4.7k statements.
    # Trace order is first-compile order, so this keeps startup/early-run paths.
    statement_lines = first(statement_lines, MAX_PRECOMPILE_STATEMENTS)

    statements_file = replace(output_file, r"\.jl$" => "_statements.jl")
    if statements_file == output_file
        statements_file = output_file * "_statements.jl"
    end
    open(statements_file, "w") do f
        for line in statement_lines
            println(f, strip(line))
        end
    end
    println("Wrote $(length(statement_lines)) raw statements → $statements_file")

    # Wrapped + progress version for include() inside Battler.jl (dev loads).
    total_lines = length(statement_lines)
    lines_with_progress = String[]
    last_printed_percent = -progress_step

    for (index, line) in enumerate(statement_lines)
        percent_complete = total_lines == 0 ? 100 : Int(round((index / total_lines) * 100))
        if percent_complete >= last_printed_percent + progress_step || index == total_lines
            push!(lines_with_progress, "println(\"Precompile progress: $percent_complete% complete ($index/$total_lines lines)\")")
            last_printed_percent = percent_complete
        end
        push!(lines_with_progress, wrap_in_try_catch(line))
    end

    open(output_file, "w") do f
        for line in lines_with_progress
            println(f, line)
        end
    end

    removed_count = length(lines) - length(statement_lines)
    println("Removed $removed_count lines containing things we don't want to precompile from $input_file")
end

# Default path is relative to where the script is run
if length(ARGS) >= 1
    input_file = ARGS[1]
else
    input_file = "Battler/src/additional_precompile.jl"
end

# Optional output path
output_file = length(ARGS) >= 2 ? ARGS[2] : input_file

clean_precompile_file(input_file, output_file) 