module ConsoleIntegrationModule
    using JulGame
    using ..Scripts
    
    """
    Add the developer console to the current scene
    """
    function add_console_to_scene()
        try
            # Check if console already exists
            existing_console = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "DeveloperConsole")
            if existing_console !== nothing
                @debug "Developer console already exists in scene"
                return existing_console
            end
            
            # Create console entity
            console_entity = JulGame.EntityModule.Entity("DeveloperConsole")
            console_entity = JulGame.create_entity(console_entity)
            
            # Add console script
            console_script = Scripts.DeveloperConsoleModule.DeveloperConsole()
            push!(console_entity.scripts, console_script)
            
            @debug "Developer console added to scene successfully"
            return console_entity
            
        catch e
            @error "Failed to add developer console to scene: $e"
            return nothing
        end
    end
    
    """
    Remove the developer console from the current scene
    """
    function remove_console_from_scene()
        try
            console_entity = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "DeveloperConsole")
            if console_entity !== nothing
                JulGame.destroy_entity(console_entity)
                @debug "Developer console removed from scene"
                return true
            else
                @warn "Developer console not found in scene"
                return false
            end
        catch e
            @error "Failed to remove developer console: $e"
            return false
        end
    end
    
    """
    Check if the developer console is available and active
    """
    function is_console_available()
        return Scripts.DeveloperConsoleModule.ConsoleInstance !== nothing
    end
    
    """
    Safely log a message to the console (if available)
    """
    function console_log(message::String, color::Tuple{Int,Int,Int,Int} = (255,255,255,255))
        if is_console_available()
            Scripts.DeveloperConsoleModule.add_console_output(message, color)
        else
            # Fallback to regular logging
            @debug "Console: $message"
        end
    end
    
    """
    Log an info message to console (blue text)
    """
    function console_info(message::String)
        console_log("[INFO] $message", (100, 200, 255, 255))
    end
    
    """
    Log a warning message to console (yellow text)
    """
    function console_warn(message::String)
        console_log("[WARN] $message", (255, 255, 100, 255))
    end
    
    """
    Log an error message to console (red text)
    """
    function console_error(message::String)
        console_log("[ERROR] $message", (255, 100, 100, 255))
    end
    
    """
    Log a success message to console (green text)
    """
    function console_success(message::String)
        console_log("[SUCCESS] $message", (100, 255, 100, 255))
    end
    
    """
    Toggle the console visibility (convenience function)
    """
    function toggle_console()
        if is_console_available()
            Scripts.DeveloperConsoleModule.toggle_console()
        else
            @warn "Developer console not available"
        end
    end
    
    """
    Execute a console command programmatically
    """
    function execute_console_command(command::String)
        if is_console_available()
            try
                console = Scripts.DeveloperConsoleModule.ConsoleInstance
                Scripts.DeveloperConsoleModule.execute_command(console, command)
                return true
            catch e
                @error "Failed to execute console command '$command': $e"
                return false
            end
        else
            @warn "Cannot execute console command: console not available"
            return false
        end
    end
    
    """
    Register a custom command with the console
    """
    function register_custom_command(name::String, description::String, category::String, execute_func::Function)
        if is_console_available()
            try
                command = Scripts.DeveloperConsoleModule.create_simple_command(
                    name, description, category, execute_func
                )
                Scripts.DeveloperConsoleModule.register_command(
                    Scripts.DeveloperConsoleModule.ConsoleInstance, 
                    command
                )
                console_success("Registered custom command: $name")
                return true
            catch e
                console_error("Failed to register command '$name': $e")
                return false
            end
        else
            @warn "Cannot register command: console not available"
            return false
        end
    end
    
    """
    Integration helper: Add console debug hooks to common game events
    """
    function setup_debug_hooks()
        if !is_console_available()
            @warn "Console not available for debug hooks"
            return
        end
        
        # Register some helpful debug commands
        register_custom_command(
            "debug_scene_stats",
            "Show detailed scene statistics",
            "debug",
            function(args)
                scene = MAIN.scene
                if scene === nothing
                    return "No scene loaded"
                end
                
                stats = """
Scene Debug Statistics:
• Scene Name: $(scene.sceneName)
• Total Entities: $(length(scene.entities))
• Camera Position: $(scene.camera.transform.position)
• Camera Zoom: $(scene.camera.zoom)
• Render Layer Count: $(length(scene.renderLayers))
                """
                
                # Count scripts by type
                script_counts = Dict{String, Int}()
                for entity in scene.entities
                    for script in entity.scripts
                        script_type = string(typeof(script))
                        script_counts[script_type] = get(script_counts, script_type, 0) + 1
                    end
                end
                
                if !isempty(script_counts)
                    stats *= "\nScript Distribution:\n"
                    for (script_type, count) in sort(collect(script_counts))
                        stats *= "• $script_type: $count\n"
                    end
                end
                
                return stats
            end
        )
        
        register_custom_command(
            "debug_performance",
            "Show basic performance information",
            "debug",
            function(args)
                # Get basic Julia performance stats
                return """
Performance Information:
• Julia Version: $(VERSION)
• Memory Usage: $(Base.gc_live_bytes() / 1024 / 1024) MB
• GC Time: $(Base.gc_time_ns() / 1e9) seconds
• Allocated Memory: $(Base.gc_bytes() / 1024 / 1024) MB
                """
            end
        )
        
        console_success("Debug hooks initialized")
    end
    
    """
    Convenience function to set up console in a game manager
    """
    function initialize_console_for_game()
        @debug "Initializing developer console for game..."
        
        # Add console to scene
        console_entity = add_console_to_scene()
        if console_entity === nothing
            @error "Failed to initialize console"
            return false
        end
        
        # Set up debug hooks
        # Wait a moment for console to fully initialize
        Timer(1.0) do timer
            setup_debug_hooks()
        end
        
        console_success("Developer console initialization complete!")
        console_info("Press ~ (tilde) to toggle console visibility")
        
        return true
    end
    
    # Export main functions
    export add_console_to_scene, remove_console_from_scene, is_console_available
    export console_log, console_info, console_warn, console_error, console_success
    export toggle_console, execute_console_command, register_custom_command
    export setup_debug_hooks, initialize_console_for_game
    
end 