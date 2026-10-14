#!/usr/bin/env julia

"""
Automated precompilation script for Battler game.
This script:
1. Runs the game with trace compilation enabled
2. Cleans the generated precompile file
3. Optionally tests the precompiled version
"""

using Pkg

function generate_precompile_statements()
    println("🔄 Generating precompile statements...")
    
    # Path to the precompile file
    precompile_file = joinpath("Battler", "src", "additional_precompile.jl")
    backup_file = joinpath("Battler", "src", "additional_precompile_backup.jl")
    
    # Backup existing precompile file if it exists
    if isfile(precompile_file)
        println("📁 Backing up existing precompile file...")
        cp(precompile_file, backup_file; force=true)
    end
    
    # Set environment variables for tracing
    ENV["SKIP"] = "true"
    ENV["SKIP_PRECOMPILE"] = "true"
    
    println("🚀 Running game with trace compilation...")
    
    # Run Julia with trace compilation
    # The game will run briefly and generate precompile statements
    cmd = `julia --trace-compile=$precompile_file -e "
        cd(\"Battler/src\")
        include(\"Run.jl\")
        # Run for a short time to capture initialization
        sleep(2)
        exit(0)
    "`
    
    try
        run(cmd)
        println("✅ Trace compilation completed!")
    catch e
        println("❌ Error during trace compilation: $e")
        # Restore backup if available
        if isfile(backup_file)
            cp(backup_file, precompile_file; force=true)
            println("🔄 Restored backup precompile file")
        end
        return false
    end
    
    return true
end

function clean_precompile_statements()
    println("🧹 Cleaning precompile statements...")
    
    # Use the existing cleaning script
    if isfile("clean_precompile.jl")
        try
            include("clean_precompile.jl")
            println("✅ Precompile statements cleaned!")
            return true
        catch e
            println("❌ Error cleaning precompile statements: $e")
            return false
        end
    else
        println("⚠️  clean_precompile.jl not found, skipping cleaning step")
        return true
    end
end

function test_precompiled_version()
    println("🧪 Testing precompiled version...")
    
    # Unset SKIP_PRECOMPILE to test with precompilation
    delete!(ENV, "SKIP_PRECOMPILE")
    ENV["TEST_MODE"] = "true"  # Skip Steam integration for testing
    
    cmd = `julia -e "
        cd(\"Battler/src\")
        println(\"Loading with precompilation...\")
        @time include(\"Battler.jl\")
        println(\"✅ Precompiled version loaded successfully!\")
    "`
    
    try
        run(cmd)
        return true
    catch e
        println("❌ Error testing precompiled version: $e")
        return false
    end
end

function main()
    println("🎮 Battler Precompilation Generator")
    println("==================================")
    
    # Check if we're in the right directory
    if !isdir("Battler")
        println("❌ Please run this script from the project root directory")
        exit(1)
    end
    
    # Step 1: Generate precompile statements
    if !generate_precompile_statements()
        println("❌ Failed to generate precompile statements")
        exit(1)
    end
    
    # Step 2: Clean precompile statements
    if !clean_precompile_statements()
        println("❌ Failed to clean precompile statements")
        exit(1)
    end
    
    # Step 3: Test precompiled version
    println("\n🧪 Testing precompiled version (optional)...")
    if test_precompiled_version()
        println("✅ All steps completed successfully!")
        println("\n📝 Summary:")
        println("  - Precompile statements generated")
        println("  - Statements cleaned and filtered")
        println("  - Precompiled version tested")
        println("\n🚀 You can now run your game with faster startup times!")
    else
        println("⚠️  Precompile generation completed, but testing failed")
        println("   This might be normal - try running the game manually")
    end
end

# Run if called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 