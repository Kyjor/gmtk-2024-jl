# Scene Management Commands

"""
Register all scene management commands
"""
function register_scene_commands(console::DeveloperConsole)
    register_command(console, create_scene_switch_command())
    register_command(console, create_scene_list_command())
    register_command(console, create_scene_info_command())
    register_command(console, create_scene_reload_command())
    register_command(console, create_scene_entities_command())
end

"""
Create scene switch command
"""
function create_scene_switch_command()
    execute_func = function(args)
        validate_exact_args(args, 1, "scene_switch")
        
        scene_name = args[1]
        
        # Add .json extension if not present
        if !endswith(scene_name, ".json")
            scene_name *= ".json"
        end
        
        # Check if scene exists in cache
        if !haskey(JulGame.SCENE_CACHE, scene_name)
            available_scenes = collect(keys(JulGame.SCENE_CACHE))
            return CommandResult(false, "Scene '$(scene_name)' not found. Available scenes: $(join(available_scenes, ", "))")
        end
        
        try
            # Create new scene and switch to it
            new_scene = SceneBuilderModule.Scene(scene_name)
            SceneBuilderModule.switch_to_scene(new_scene)
            
            return CommandResult(true, "Switched to scene: $(scene_name)")
        catch e
            return CommandResult(false, "Failed to switch to scene '$(scene_name)': $(e)")
        end
    end
    
    validate_func = function(args)
        validate_exact_args(args, 1, "scene_switch")
        return true
    end
    
    return BaseCommand(
        "scene_switch",
        "Switch to a different scene",
        "scene_switch <scene_name>",
        "scene",
        execute_func,
        validate_func
    )
end

"""
Create scene list command
"""
function create_scene_list_command()
    execute_func = function(args)
        available_scenes = collect(keys(JulGame.SCENE_CACHE))
        
        if isempty(available_scenes)
            return "No scenes available in cache"
        end
        
        scenes_text = "Available Scenes:\n"
        for scene_name in sort(available_scenes)
            # Get basic scene info
            try
                scene_data = JulGame.SCENE_CACHE[scene_name]
                entity_count = haskey(scene_data, "entities") ? length(scene_data["entities"]) : 0
                scenes_text *= "• $(scene_name) ($(entity_count) entities)\n"
            catch e
                scenes_text *= "• $(scene_name) (failed to load info)\n"
            end
        end
        
        return CommandResult(true, scenes_text)
    end
    
    return create_simple_command(
        "scene_list",
        "List all available scenes",
        "scene",
        execute_func
    )
end

"""
Create scene info command
"""
function create_scene_info_command()
    execute_func = function(args)
        if isempty(args)
            # Show current scene info
            if MAIN.scene === nothing
                return "No scene currently loaded"
            end
            
            scene = MAIN.scene
            info_text = """
Current Scene Information:
• Scene Name: $(scene.sceneName)
• Entity Count: $(length(scene.entities))
• Camera Position: $(scene.camera.transform.position)
• Camera Size: $(scene.camera.size)
            """
            
            return CommandResult(true, info_text)
        else
            # Show specific scene info
            scene_name = args[1]
            if !endswith(scene_name, ".json")
                scene_name *= ".json"
            end
            
            if !haskey(JulGame.SCENE_CACHE, scene_name)
                return CommandResult(false, "Scene '$(scene_name)' not found")
            end
            
            try
                scene_data = JulGame.SCENE_CACHE[scene_name]
                entity_count = haskey(scene_data, "entities") ? length(scene_data["entities"]) : 0
                
                info_text = """
Scene Information: $(scene_name)
• Entity Count: $(entity_count)
• Cached: Yes
                """
                
                if haskey(scene_data, "camera")
                    camera_data = scene_data["camera"]
                    if haskey(camera_data, "size")
                        info_text *= "• Camera Size: $(camera_data["size"])\n"
                    end
                end
                
                return CommandResult(true, info_text)
            catch e
                return CommandResult(false, "Failed to get scene info: $(e)")
            end
        end
    end
    
    validate_func = function(args)
        return length(args) <= 1
    end
    
    return BaseCommand(
        "scene_info",
        "Show information about current or specified scene",
        "scene_info [scene_name]",
        "scene",
        execute_func,
        validate_func
    )
end

"""
Create scene reload command
"""
function create_scene_reload_command()
    execute_func = function(args)
        if MAIN.scene === nothing
            return CommandResult(false, "No scene currently loaded")
        end
        
        current_scene_name = MAIN.scene.sceneName
        
        try
            # Reload the current scene
            new_scene = SceneBuilderModule.Scene(current_scene_name)
            SceneBuilderModule.switch_to_scene(new_scene)
            
            return CommandResult(true, "Reloaded scene: $(current_scene_name)")
        catch e
            return CommandResult(false, "Failed to reload scene: $(e)")
        end
    end
    
    return create_simple_command(
        "scene_reload",
        "Reload the current scene",
        "scene",
        execute_func
    )
end

"""
Create scene entities command
"""
function create_scene_entities_command()
    execute_func = function(args)
        if MAIN.scene === nothing
            return "No scene currently loaded"
        end
        
        scene = MAIN.scene
        entities_text = "Scene Entities ($(length(scene.entities)) total):\n"
        
        for (i, entity) in enumerate(scene.entities)
            entity_name = entity.name !== nothing ? entity.name : "Unnamed"
            script_count = length(entity.scripts)
            component_count = length(entity.components)
            
            entities_text *= "$(i). $(entity_name)\n"
            entities_text *= "    Scripts: $(script_count), Components: $(component_count)\n"
            
            # List script types
            if script_count > 0
                script_types = [string(typeof(script)) for script in entity.scripts]
                entities_text *= "    Script Types: $(join(script_types, ", "))\n"
            end
            
            entities_text *= "\n"
        end
        
        return CommandResult(true, entities_text)
    end
    
    return create_simple_command(
        "scene_entities",
        "List all entities in the current scene",
        "scene",
        execute_func
    )
end

"""
Create scene camera command
"""
function create_scene_camera_command()
    execute_func = function(args)
        if MAIN.scene === nothing
            return CommandResult(false, "No scene currently loaded")
        end
        
        camera = MAIN.scene.camera
        
        if isempty(args)
            # Show camera info
            info_text = """
Camera Information:
• Position: $(camera.transform.position)
• Size: $(camera.size)
• Zoom: $(camera.zoom)
            """
            return CommandResult(true, info_text)
        end
        
        # Set camera properties
        if length(args) >= 2
            property = lowercase(args[1])
            value = args[2]
            
            if property == "zoom"
                zoom_value = parse_numeric_arg(value, "zoom")
                if zoom_value <= 0
                    return CommandResult(false, "Zoom must be greater than 0")
                end
                camera.zoom = Float32(zoom_value)
                return "Camera zoom set to $(zoom_value)"
            elseif property == "x"
                x_value = parse_numeric_arg(value, "x position")
                camera.transform.position = Math.Vector2(Float32(x_value), camera.transform.position.y)
                return "Camera X position set to $(x_value)"
            elseif property == "y"
                y_value = parse_numeric_arg(value, "y position")
                camera.transform.position = Math.Vector2(camera.transform.position.x, Float32(y_value))
                return "Camera Y position set to $(y_value)"
            else
                return CommandResult(false, "Unknown camera property: $(property). Available: zoom, x, y")
            end
        end
        
        return CommandResult(false, "Usage: scene_camera [property] [value]")
    end
    
    validate_func = function(args)
        return length(args) <= 2
    end
    
    return BaseCommand(
        "scene_camera",
        "Get or set camera properties",
        "scene_camera [property] [value]",
        "scene",
        execute_func,
        validate_func
    )
end

# Auto-register scene commands when this file is included
if ccall(:jl_generating_output, Cint, ()) != 1 && !JulGame.IS_PACKAGE_COMPILED
function __init__()
    if ConsoleInstance !== nothing
        register_scene_commands(ConsoleInstance)
        register_command(ConsoleInstance, create_scene_camera_command())
    end
end 
end
