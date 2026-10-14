# Battle Feedback System - Modular, extensible feedback for all battle actions
# Provides visual, audio, and haptic feedback for combat events

module BattleFeedbackSystemModule
    using JulGame
    using ...Scripts

    # Effect data structures
    mutable struct VisualEffect
        entity::Any
        effect_type::Symbol  # :flash, :shake, :tint, :scale, :particles
        duration::Float64
        elapsed::Float64
        intensity::Float64
        color::Tuple{Int, Int, Int, Int}  # RGBA
        original_position::Any
        original_color::Tuple{Int, Int, Int, Int}
        easing_function::Function
        on_complete::Union{Function, Nothing}
        metadata::Dict{Symbol, Any}  # For additional effect-specific data
    end

    mutable struct ScreenEffect
        effect_type::Symbol  # :flash, :shake, :vignette, :blur
        duration::Float64
        elapsed::Float64
        intensity::Float64
        color::Tuple{Int, Int, Int, Int}
        easing_function::Function
        on_complete::Union{Function, Nothing}
    end

    mutable struct ParticleEffect
        entity::Any
        particle_type::Symbol  # :ice, :fire, :healing, :impact, :blood, :sparkles
        count::Int
        duration::Float64
        elapsed::Float64
        spawn_rate::Float64  # particles per second
        particles::Vector{Any}
        metadata::Dict{Symbol, Any}
    end

    mutable struct ChainEffect
        effects::Vector{Function}  # Functions to execute in sequence
        delays::Vector{Float64}  # Delay before each effect
        current_index::Int
        elapsed::Float64
    end

    # Active effects tracking
    mutable struct FeedbackManager
        visual_effects::Vector{VisualEffect}
        screen_effects::Vector{ScreenEffect}
        particle_effects::Vector{ParticleEffect}
        chain_effects::Vector{ChainEffect}
        audio_queue::Vector{Tuple{String, Float64}}  # (sound_name, delay)
    end

    function FeedbackManager()
        return FeedbackManager(
            VisualEffect[],
            ScreenEffect[],
            ParticleEffect[],
            ChainEffect[],
            Tuple{String, Float64}[]
        )
    end

    # Global feedback manager instance
    global FEEDBACK_MANAGER = FeedbackManager()

    # === EASING FUNCTIONS ===
    ease_linear(t) = t
    ease_out_cubic(t) = 1 - (1 - t)^3
    ease_in_out_cubic(t) = t < 0.5 ? 4 * t^3 : 1 - (-2 * t + 2)^3 / 2
    ease_out_elastic(t) = t == 0 ? 0 : t == 1 ? 1 : 2^(-10t) * sin((t * 10 - 0.75) * (2π / 3)) + 1
    ease_out_bounce(t) = begin
        if t < 1/2.75
            7.5625 * t^2
        elseif t < 2/2.75
            7.5625 * (t -= 1.5/2.75) * t + 0.75
        elseif t < 2.5/2.75
            7.5625 * (t -= 2.25/2.75) * t + 0.9375
        else
            7.5625 * (t -= 2.625/2.75) * t + 0.984375
        end
    end

    # === CORE FEEDBACK FUNCTIONS ===

    # Add a visual effect to an entity
    function add_visual_effect(
        entity::Any, 
        effect_type::Symbol; 
        duration::Float64 = 0.3,
        intensity::Float64 = 1.0,
        color::Tuple{Int, Int, Int, Int} = (255, 255, 255, 255),
        easing::Function = ease_out_cubic,
        on_complete::Union{Function, Nothing} = nothing,
        metadata::Dict{Symbol, Any} = Dict{Symbol, Any}()
    )
        original_pos = Math.Vector3f(0.0, 0.0, 0.0)
        if isdefined(entity, :transform) && isdefined(entity.transform, :position)
            original_pos = entity.transform.position
        end

        original_color = (255, 255, 255, 255)
        try
            if isdefined(entity, :sprite) && isdefined(entity.sprite, :color)
                original_color = entity.sprite.color
            end
        catch e
            @debug "Could not get original color: $(e)"
        end

        effect = VisualEffect(
            entity,
            effect_type,
            duration,
            0.0,
            intensity,
            color,
            original_pos,
            original_color,
            easing,
            on_complete,
            metadata
        )

        push!(FEEDBACK_MANAGER.visual_effects, effect)
        return effect
    end

    # Add a screen-wide effect
    function add_screen_effect(
        effect_type::Symbol;
        duration::Float64 = 0.3,
        intensity::Float64 = 1.0,
        color::Tuple{Int, Int, Int, Int} = (255, 0, 0, 128),
        easing::Function = ease_out_cubic,
        on_complete::Union{Function, Nothing} = nothing
    )
        effect = ScreenEffect(
            effect_type,
            duration,
            0.0,
            intensity,
            color,
            easing,
            on_complete
        )

        push!(FEEDBACK_MANAGER.screen_effects, effect)
        return effect
    end

    # Add a particle effect
    function add_particle_effect(
        entity::Any,
        particle_type::Symbol;
        count::Int = 10,
        duration::Float64 = 1.0,
        spawn_rate::Float64 = 20.0,
        metadata::Dict{Symbol, Any} = Dict{Symbol, Any}()
    )
        effect = ParticleEffect(
            entity,
            particle_type,
            count,
            duration,
            0.0,
            spawn_rate,
            Any[],
            metadata
        )

        push!(FEEDBACK_MANAGER.particle_effects, effect)
        return effect
    end

    # Create a chain of effects that execute in sequence
    function create_effect_chain(effects::Vector{Function}, delays::Vector{Float64})
        chain = ChainEffect(effects, delays, 1, 0.0)
        push!(FEEDBACK_MANAGER.chain_effects, chain)
        return chain
    end

    # Queue audio effect (to be integrated with game's audio system)
    function queue_audio(sound_name::String, delay::Float64 = 0.0)
        push!(FEEDBACK_MANAGER.audio_queue, (sound_name, delay))
    end

    # === UPDATE FUNCTIONS ===

    function update(deltaTime::Float64)
        return
        # TODO: Implement this
        update_visual_effects(deltaTime)
        update_screen_effects(deltaTime)
        update_particle_effects(deltaTime)
        update_chain_effects(deltaTime)
        update_audio_queue(deltaTime)
    end

    function update_visual_effects(deltaTime::Float64)
        completed = Int[]

        for (i, effect) in enumerate(FEEDBACK_MANAGER.visual_effects)
            effect.elapsed += deltaTime
            progress = min(effect.elapsed / effect.duration, 1.0)
            eased_progress = effect.easing_function(progress)

            try
                if effect.effect_type == :flash
                    apply_flash_effect(effect, eased_progress)
                elseif effect.effect_type == :shake
                    apply_shake_effect(effect, eased_progress, deltaTime)
                elseif effect.effect_type == :tint
                    apply_tint_effect(effect, eased_progress)
                elseif effect.effect_type == :scale_pulse
                    apply_scale_pulse_effect(effect, eased_progress)
                elseif effect.effect_type == :float_up
                    apply_float_up_effect(effect, eased_progress)
                end
            catch e
                @debug "Error applying visual effect: $(e)"
            end

            if progress >= 1.0
                push!(completed, i)
                if effect.on_complete !== nothing
                    try
                        effect.on_complete()
                    catch e
                        @debug "Error in effect on_complete callback: $(e)"
                    end
                end
            end
        end

        # Remove completed effects (reverse order to maintain indices)
        for i in reverse(completed)
            effect = FEEDBACK_MANAGER.visual_effects[i]
            # Reset entity to original state
            try
                if isdefined(effect.entity, :transform) && isdefined(effect.entity.transform, :position)
                    effect.entity.transform.position = effect.original_position
                end
                if isdefined(effect.entity, :sprite) && isdefined(effect.entity.sprite, :color)
                    effect.entity.sprite.color = effect.original_color
                end
            catch e
                @debug "Error resetting entity state: $(e)"
            end
            deleteat!(FEEDBACK_MANAGER.visual_effects, i)
        end
    end

    function apply_flash_effect(effect::VisualEffect, progress::Float64)
        # Flash between original color and effect color
        if isdefined(effect.entity, :sprite) && isdefined(effect.entity.sprite, :color)
            # Use a sine wave for smooth pulsing flash
            flash_intensity = sin(progress * π) * effect.intensity
            
            r = Int(floor(effect.original_color[1] * (1 - flash_intensity) + effect.color[1] * flash_intensity))
            g = Int(floor(effect.original_color[2] * (1 - flash_intensity) + effect.color[2] * flash_intensity))
            b = Int(floor(effect.original_color[3] * (1 - flash_intensity) + effect.color[3] * flash_intensity))
            a = Int(floor(effect.original_color[4] * (1 - flash_intensity) + effect.color[4] * flash_intensity))
            
            effect.entity.sprite.color = (r, g, b, a)
        end
    end

    function apply_shake_effect(effect::VisualEffect, progress::Float64, deltaTime::Float64)
        if isdefined(effect.entity, :transform) && isdefined(effect.entity.transform, :position)
            # Shake intensity decreases over time
            current_intensity = effect.intensity * (1.0 - progress)
            
            # High frequency shake
            shake_x = (rand() - 0.5) * 2.0 * current_intensity
            shake_y = (rand() - 0.5) * 2.0 * current_intensity
            
            effect.entity.transform.position = Math.Vector3f(
                effect.original_position.x + shake_x,
                effect.original_position.y + shake_y,
                effect.original_position.z
            )
        end
    end

    function apply_tint_effect(effect::VisualEffect, progress::Float64)
        if isdefined(effect.entity, :sprite) && isdefined(effect.entity.sprite, :color)
            # Fade from effect color back to original
            inv_progress = 1.0 - progress
            
            r = Int(floor(effect.original_color[1] * progress + effect.color[1] * inv_progress))
            g = Int(floor(effect.original_color[2] * progress + effect.color[2] * inv_progress))
            b = Int(floor(effect.original_color[3] * progress + effect.color[3] * inv_progress))
            a = Int(floor(effect.original_color[4] * progress + effect.color[4] * inv_progress))
            
            effect.entity.sprite.color = (r, g, b, a)
        end
    end

    function apply_scale_pulse_effect(effect::VisualEffect, progress::Float64)
        if isdefined(effect.entity, :transform) && isdefined(effect.entity.transform, :scale)
            # Pulse scale up and back down
            scale_mult = 1.0 + (sin(progress * π) * effect.intensity * 0.3)
            
            current_scale = effect.entity.transform.scale
            effect.entity.transform.scale = Math.Vector3f(
                scale_mult,
                scale_mult,
                current_scale.z
            )
        end
    end

    function apply_float_up_effect(effect::VisualEffect, progress::Float64)
        if isdefined(effect.entity, :transform) && isdefined(effect.entity.transform, :position)
            # Float upward while fading
            float_distance = get(effect.metadata, :float_distance, 1.0)
            
            effect.entity.transform.position = Math.Vector3f(
                effect.original_position.x,
                effect.original_position.y + (progress * float_distance),
                effect.original_position.z
            )
            
            # Fade out
            if isdefined(effect.entity, :sprite) && isdefined(effect.entity.sprite, :color)
                alpha = Int(floor(255 * (1.0 - progress)))
                current = effect.entity.sprite.color
                effect.entity.sprite.color = (current[1], current[2], current[3], alpha)
            end
        end
    end

    function update_screen_effects(deltaTime::Float64)
        completed = Int[]

        for (i, effect) in enumerate(FEEDBACK_MANAGER.screen_effects)
            effect.elapsed += deltaTime
            progress = min(effect.elapsed / effect.duration, 1.0)
            eased_progress = effect.easing_function(progress)

            try
                if effect.effect_type == :flash
                    apply_screen_flash(effect, eased_progress)
                elseif effect.effect_type == :shake
                    apply_screen_shake(effect, eased_progress)
                end
            catch e
                @debug "Error applying screen effect: $(e)"
            end

            if progress >= 1.0
                push!(completed, i)
                if effect.on_complete !== nothing
                    try
                        effect.on_complete()
                    catch e
                        @debug "Error in screen effect on_complete callback: $(e)"
                    end
                end
            end
        end

        for i in reverse(completed)
            deleteat!(FEEDBACK_MANAGER.screen_effects, i)
        end
    end

    function apply_screen_flash(effect::ScreenEffect, progress::Float64)
        # Create a screen-wide flash overlay
        alpha = Int(floor(effect.color[4] * sin(progress * π) * effect.intensity))
        
        JulGame.ImmediateUIModule.immediate_rect(
            "screen_flash_$(effect.effect_type)";
            size = Math.Vector2(1920, 1080),
            color = (effect.color[1], effect.color[2], effect.color[3], alpha),
            anchor = :center,
            layer = 999
        )
    end

    function apply_screen_shake(effect::ScreenEffect, progress::Float64)
        # Check if screen shake is enabled before triggering
        if !Scripts.MainSettingsModule.is_screen_shake_enabled()
            return
        end
        
        # Trigger camera shake through game manager
        try
            game_manager = JulGame.SceneModule.get_entity_by_name(MAIN.scene, "Game Manager")
            if game_manager !== nothing && length(game_manager.scripts) >= 7
                camera_shake = game_manager.scripts[7]
                camera_shake.duration = effect.duration
                camera_shake.elapsed = effect.elapsed
                camera_shake.shaking = true
            end
        catch e
            @debug "Could not trigger camera shake: $(e)"
        end
    end

    function update_particle_effects(deltaTime::Float64)
        completed = Int[]

        for (i, effect) in enumerate(FEEDBACK_MANAGER.particle_effects)
            effect.elapsed += deltaTime
            progress = min(effect.elapsed / effect.duration, 1.0)

            try
                # Spawn particles based on spawn rate
                particles_to_spawn = Int(floor(effect.spawn_rate * deltaTime))
                for _ in 1:min(particles_to_spawn, effect.count - length(effect.particles))
                    spawn_particle(effect)
                end

                # Update existing particles
                update_particles(effect, deltaTime)
            catch e
                @debug "Error updating particle effect: $(e)"
            end

            if progress >= 1.0
                push!(completed, i)
                # Clean up particles
                cleanup_particles(effect)
            end
        end

        for i in reverse(completed)
            deleteat!(FEEDBACK_MANAGER.particle_effects, i)
        end
    end

    function spawn_particle(effect::ParticleEffect)
        # Get entity position
        pos = Math.Vector3f(0.0, 0.0, 0.0)
        if isdefined(effect.entity, :transform) && isdefined(effect.entity.transform, :position)
            pos = effect.entity.transform.position
        end

        # Create particle based on type
        particle = create_particle_entity(effect.particle_type, pos)
        if particle !== nothing
            push!(effect.particles, particle)
        end
    end

    function create_particle_entity(particle_type::Symbol, position::Math.Vector3f)
        # Create visual particle entity
        try
            particle = JulGame.EntityModule.Entity("Particle_$(rand(1000:9999))")
            
            # Particle properties based on type
            sprite_name, color, velocity, lifetime = get_particle_properties(particle_type)
            
            particle.sprite = JulGame.SpriteModule.InternalSprite(
                particle,
                sprite_name,
                Math.Vector4(0, 0, 0, 0),
                false,
                color,
                false;
                pixelsPerUnit = 200,
                layer = 15
            )
            
            particle = JulGame.create_entity(particle)
            
            # Random offset from center
            offset_x = (rand() - 0.5) * 0.5
            offset_y = (rand() - 0.5) * 0.5
            particle.transform.position = Math.Vector3f(
                position.x + offset_x,
                position.y + offset_y,
                position.z
            )
            
            # Store metadata on particle
            particle.velocity = velocity
            particle.lifetime = lifetime
            particle.age = 0.0
            
            return particle
        catch e
            @debug "Error creating particle: $(e)"
            return nothing
        end
    end

    function get_particle_properties(particle_type::Symbol)
        if particle_type == :ice
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "shield"), (150, 200, 255, 255), Math.Vector2f(0, 0.5), 0.8)
        elseif particle_type == :fire
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "sword"), (255, 100, 50, 255), Math.Vector2f(0, 0.8), 0.6)
        elseif particle_type == :healing
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "heart"), (100, 255, 100, 255), Math.Vector2f(0, 0.5), 1.0)
        elseif particle_type == :impact
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), (255, 255, 255, 255), Math.Vector2f(0, 0), 0.3)
        elseif particle_type == :sparkles
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), (255, 255, 0, 255), Math.Vector2f(0, 0.3), 0.5)
        else
            return (JulGame.UserGlobals["Module"].get_asset_path("piece", "error"), (255, 255, 255, 255), Math.Vector2f(0, 0), 0.5)
        end
    end

    function update_particles(effect::ParticleEffect, deltaTime::Float64)
        to_remove = Int[]
        
        for (i, particle) in enumerate(effect.particles)
            try
                if isdefined(particle, :age)
                    particle.age += deltaTime
                    
                    if particle.age >= particle.lifetime
                        push!(to_remove, i)
                        JulGame.destroy_entity(MAIN, particle)
                        continue
                    end
                    
                    # Update position based on velocity
                    if isdefined(particle, :velocity) && isdefined(particle, :transform)
                        particle.transform.position = Math.Vector3f(
                            particle.transform.position.x + particle.velocity.x * deltaTime,
                            particle.transform.position.y + particle.velocity.y * deltaTime,
                            particle.transform.position.z
                        )
                    end
                    
                    # Fade out over lifetime
                    if isdefined(particle, :sprite)
                        alpha = Int(floor(255 * (1.0 - particle.age / particle.lifetime)))
                        current = particle.sprite.color
                        particle.sprite.color = (current[1], current[2], current[3], alpha)
                    end
                end
            catch e
                @debug "Error updating particle: $(e)"
            end
        end
        
        for i in reverse(to_remove)
            deleteat!(effect.particles, i)
        end
    end

    function cleanup_particles(effect::ParticleEffect)
        for particle in effect.particles
            try
                JulGame.destroy_entity(MAIN, particle)
            catch e
                @debug "Error cleaning up particle: $(e)"
            end
        end
        empty!(effect.particles)
    end

    function update_chain_effects(deltaTime::Float64)
        completed = Int[]

        for (i, chain) in enumerate(FEEDBACK_MANAGER.chain_effects)
            chain.elapsed += deltaTime

            if chain.current_index <= length(chain.effects)
                current_delay = chain.delays[chain.current_index]
                
                if chain.elapsed >= current_delay
                    # Execute current effect
                    try
                        chain.effects[chain.current_index]()
                    catch e
                        @debug "Error executing chain effect: $(e)"
                    end
                    
                    chain.current_index += 1
                    chain.elapsed = 0.0
                end
            else
                # Chain complete
                push!(completed, i)
            end
        end

        for i in reverse(completed)
            deleteat!(FEEDBACK_MANAGER.chain_effects, i)
        end
    end

    function update_audio_queue(deltaTime::Float64)
        to_remove = Int[]
        
        for (i, (sound_name, delay)) in enumerate(FEEDBACK_MANAGER.audio_queue)
            if delay <= 0.0
                # Play sound (integrate with game's audio system)
                try
                    play_sound_effect(sound_name)
                catch e
                    @debug "Error playing sound: $(e)"
                end
                push!(to_remove, i)
            else
                # Decrease delay
                FEEDBACK_MANAGER.audio_queue[i] = (sound_name, delay - deltaTime)
            end
        end
        
        for i in reverse(to_remove)
            deleteat!(FEEDBACK_MANAGER.audio_queue, i)
        end
    end

    function play_sound_effect(sound_name::String)
        # Integrate with JulGame's audio system
        try
            globals = JulGame.UserGlobals["Module"]
            if isdefined(globals, :DJModule)
                # Play through DJ (audio manager)
                # globals.DJModule.play_sfx(sound_name)
                @debug "Playing sound: $(sound_name)"
            end
        catch e
            @debug "Could not play sound: $(e)"
        end
    end

    # === CLEANUP ===
    function clear_all_effects()
        # Clean up all particles
        for effect in FEEDBACK_MANAGER.particle_effects
            cleanup_particles(effect)
        end
        
        empty!(FEEDBACK_MANAGER.visual_effects)
        empty!(FEEDBACK_MANAGER.screen_effects)
        empty!(FEEDBACK_MANAGER.particle_effects)
        empty!(FEEDBACK_MANAGER.chain_effects)
        empty!(FEEDBACK_MANAGER.audio_queue)
    end

end # module

