module TreasureDisplayManagerModule
    using JulGame
    using ..Scripts

    # Base Animation System
    abstract type BaseAnimation end

    mutable struct AnimationState
        is_active::Bool
        elapsed_time::Float64
        duration::Float64
        start_time::Float64
        
        AnimationState(duration::Float64) = new(false, 0.0, duration, 0.0)
    end

    function start_animation!(state::AnimationState)
        state.is_active = true
        state.elapsed_time = 0.0
        state.start_time = 0.0
    end

    function update_animation!(state::AnimationState, delta_time::Float64)
        if !state.is_active
            return false
        end
        
        state.elapsed_time += delta_time
        return state.elapsed_time < state.duration
    end

    function get_progress(state::AnimationState)::Float64
        return state.is_active ? clamp(state.elapsed_time / state.duration, 0.0, 1.0) : 0.0
    end

    function is_finished(state::AnimationState)::Bool
        return !state.is_active || state.elapsed_time >= state.duration
    end

    # Shake Animation
    mutable struct ShakeAnimation <: BaseAnimation
        state::AnimationState
        intensity::Float64
        decay_rate::Float64
        frequency::Float64
        offset_x::Float64
        offset_y::Float64
        original_position::Math.Vector2f
        
        function ShakeAnimation(duration::Float64=0.5, intensity::Float64=5.0, frequency::Float64=20.0, decay_rate::Float64=2.0)
            new(AnimationState(duration), intensity, decay_rate, frequency, 0.0, 0.0, Math.Vector2f(0.0, 0.0))
        end
    end

    function start!(shake::ShakeAnimation, original_pos::Math.Vector2f)
        start_animation!(shake.state)
        shake.original_position = original_pos
        shake.offset_x = 0.0
        shake.offset_y = 0.0
    end

    function update!(shake::ShakeAnimation, delta_time::Float64)::Bool
        if !update_animation!(shake.state, delta_time)
            shake.offset_x = 0.0
            shake.offset_y = 0.0
            return false
        end
        
        progress = get_progress(shake.state)
        current_intensity = shake.intensity * exp(-shake.decay_rate * progress)
        time_factor = shake.state.elapsed_time * shake.frequency
        
        shake.offset_x = current_intensity * sin(time_factor) * (rand() - 0.5) * 2.0
        shake.offset_y = current_intensity * cos(time_factor * 1.3) * (rand() - 0.5) * 2.0
        
        return true
    end

    function get_current_position(shake::ShakeAnimation)::Math.Vector2f
        return Math.Vector2f(
            shake.original_position.x + shake.offset_x,
            shake.original_position.y + shake.offset_y
        )
    end

    # Flash Animation
    mutable struct FlashAnimation <: BaseAnimation
        state::AnimationState
        flash_color::Tuple{UInt8, UInt8, UInt8, UInt8}
        current_alpha::Float64
        fade_in_ratio::Float64
        
        function FlashAnimation(duration::Float64=0.3, color::Tuple{UInt8, UInt8, UInt8, UInt8}=(255, 255, 255, 255), fade_in_ratio::Float64=0.3)
            new(AnimationState(duration), color, 0.0, fade_in_ratio)
        end
    end

    function start!(flash::FlashAnimation)
        start_animation!(flash.state)
        flash.current_alpha = 0.0
    end

    function update!(flash::FlashAnimation, delta_time::Float64)::Bool
        if !update_animation!(flash.state, delta_time)
            flash.current_alpha = 0.0
            return false
        end
        
        progress = get_progress(flash.state)
        
        if progress <= flash.fade_in_ratio
            # Fade in
            flash.current_alpha = progress / flash.fade_in_ratio
        else
            # Fade out
            fade_out_progress = (progress - flash.fade_in_ratio) / (1.0 - flash.fade_in_ratio)
            flash.current_alpha = 1.0 - fade_out_progress
        end
        
        flash.current_alpha = clamp(flash.current_alpha, 0.0, 1.0)
        return true
    end

    function get_current_color(flash::FlashAnimation)::Tuple{UInt8, UInt8, UInt8, UInt8}
        alpha = UInt8(round(flash.current_alpha * 255))
        return (flash.flash_color[1], flash.flash_color[2], flash.flash_color[3], alpha)
    end

    # Animation Manager
    mutable struct AnimationManager
        animations::Dict{String, Vector{BaseAnimation}}
        
        AnimationManager() = new(Dict{String, Vector{BaseAnimation}}())
    end

    function add_animation!(manager::AnimationManager, target_id::String, animation::BaseAnimation)
        if !haskey(manager.animations, target_id)
            manager.animations[target_id] = BaseAnimation[]
        end
        push!(manager.animations[target_id], animation)
    end

    function update_animations!(manager::AnimationManager, delta_time::Float64)
        for (target_id, animations) in manager.animations
            # Update all animations and remove finished ones
            filter!(animations) do anim
                if isa(anim, ShakeAnimation)
                    return update!(anim, delta_time)
                elseif isa(anim, FlashAnimation)
                    return update!(anim, delta_time)
                else
                    return false
                end
            end
        end
        
        # Remove empty animation lists
        filter!(pair -> !isempty(pair.second), manager.animations)
    end

    function get_animations(manager::AnimationManager, target_id::String)::Vector{BaseAnimation}
        return get(manager.animations, target_id, BaseAnimation[])
    end

    # Treasure Display Manager
    mutable struct TreasureDisplayManager <: Script
        parent
        treasures::Vector{Any}
        animation_manager::AnimationManager
        bottom_padding::Float64
        treasure_size::Float64
        treasure_spacing::Float64

        battleManager::Any
        # Tooltip manager
        tooltipManager
        
        function TreasureDisplayManager()
            this = new()
            this.treasures = []
            this.animation_manager = AnimationManager()
            this.bottom_padding = 20.0
            this.treasure_size = 96.0
            this.treasure_spacing = 110.0
            return this
        end
    end

    function JulGame.initialize(this::TreasureDisplayManager)
        # Get the shared tooltip manager from the scene
        tooltipEntity = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "TooltipManager")
        if tooltipEntity !== nothing && length(tooltipEntity.scripts) > 0
            this.tooltipManager = tooltipEntity.scripts[1]
        else
            @warn "No TooltipManager found in scene. Treasures will not have tooltips."
            this.tooltipManager = nothing
        end
        this.battleManager = this.parent.scripts[4]  # BattleManager is script 4
        # Get current user treasures
        globals = JulGame.UserGlobals["Module"]
        user_data = globals.get_user_data()
        
        if user_data !== nothing && user_data.treasures !== nothing
            this.treasures = collect(user_data.treasures)
            @debug "User has $(length(this.treasures)) treasures"
        end
    end



    function use_treasure(this::TreasureDisplayManager, treasure_index::Int)
        if treasure_index < 1 || treasure_index > length(this.treasures)
            @warn "Invalid treasure index: $(treasure_index)"
            return
        end
        
        treasure = this.treasures[treasure_index]
        treasure_id = "treasure_$(treasure_index)_$(treasure.key)"
        
        # Create and start animations for immediate UI
        # Note: For immediate UI, animations are more limited, but we can still trigger them
        shake_anim = ShakeAnimation(0.5, 8.0, 25.0, 3.0)
        start!(shake_anim, Math.Vector2f(0.0, 0.0))  # Immediate UI will handle positioning
        add_animation!(this.animation_manager, treasure_id, shake_anim)
        
        flash_anim = FlashAnimation(0.4, (UInt8(255), UInt8(255), UInt8(255), UInt8(200)), 0.2)
        start!(flash_anim)
        add_animation!(this.animation_manager, treasure_id, flash_anim)
        
        @debug "Started usage animation for treasure: $(treasure.name)"
    end

    function refresh_treasures(this::TreasureDisplayManager)
        # Reload treasures from user data (no entities to clean up with immediate UI)
        globals = JulGame.UserGlobals["Module"]
        user_data = globals.get_user_data()
        
        if user_data !== nothing && user_data.treasures !== nothing
            this.treasures = collect(user_data.treasures)
        else
            this.treasures = []
        end
    end

    function JulGame.update(this::TreasureDisplayManager, deltaTime::Float64)
        # Update animations
        update_animations!(this.animation_manager, deltaTime)
        
        # Draw treasure bar if we have treasures
        if !isempty(this.treasures)
            draw_treasure_bar(this)
        end
    end

    """
    Draw the treasure bar at the bottom of the screen using immediate UI buttons
    """
    function draw_treasure_bar(this::TreasureDisplayManager)
        if isempty(this.treasures)
            return
        end
        
        # Calculate total width needed for all treasures
        start_x = 0
        # Draw each treasure as an immediate button
        for (index, treasure) in enumerate(this.treasures)
            treasure_x = start_x + (index - 1) * this.treasure_spacing
            
            # Get the appropriate sprite for this treasure
            sprite_name = get_treasure_sprite_name(treasure)
            
            # Calculate final position (including any shake effects)
            final_x = treasure_x
            final_y = -5

            # Apply any active animations to this treasure
            animations = get_animations(this.animation_manager, "treasure_$(index)_$(treasure.key)")
            
            # Apply shake animation to button position if active
            shake_anims = filter(a -> isa(a, ShakeAnimation), animations)
            if !isempty(shake_anims)
                shake = shake_anims[1]
                shake_offset = get_current_position(shake)
                final_x += shake_offset.x
                final_y += shake_offset.y
            end
            
            # Create the treasure button with proper position
            if this.battleManager !== nothing && this.battleManager.didClearEverything == false
                treasure_button = JulGame.ImmediateUIModule.immediate_button(
                    "treasure_button_$(index)",
                    () -> handle_treasure_click(this, index, treasure);
                    anchor = :bottomLeft,
                    anchorOffset = Math.Vector2(final_x, final_y),
                    size = Math.Vector2(this.treasure_size, this.treasure_size),
                    buttonUpPath = sprite_name,
                    buttonDownPath = sprite_name,
                    layer = 15
                )
                # Register tooltip for this treasure using the calculated position
                if this.tooltipManager !== nothing
                    tooltip_text = "$(treasure.name): $(treasure.description)"
                    
                    # Debug: Log the tooltip area registration
                    @debug "Registering tooltip area for treasure $(index): position ($final_x, $final_y), size ($(this.treasure_size), $(this.treasure_size))"
                    
                    Scripts.TooltipManagerModule.register_tooltip_item(
                        this.tooltipManager,
                        treasure_button,
                        tooltip_text
                    )
                end
            end
        end
    end
    
    """
    Handle clicking on a treasure button
    """
    function handle_treasure_click(this::TreasureDisplayManager, index::Int, treasure)
        @debug "Clicked on treasure: $(treasure.name)"
        # Trigger usage animation
        use_treasure(this, index)
    end
    
    function get_treasure_sprite_name(treasure)::String
        return JulGame.UserGlobals["Module"].get_asset_path("treasure", lowercase(split(treasure.key, "_")[2]))
    end

    function JulGame.on_shutdown(this::TreasureDisplayManager)
        # No entities to clean up with immediate UI system
    end
    
    # Export functions
    export use_treasure, refresh_treasures
end 