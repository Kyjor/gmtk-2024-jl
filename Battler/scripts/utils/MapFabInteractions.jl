module MapFabInteractionsModule
    using JulGame
    using Random

    export MapFabInteraction,
           map_fab_asset_path,
           map_fab_prefixed_asset,
           register_map_fab_interaction!,
           start_crow_flight!,
           update_map_fab_interactions!

    struct MapFabInteractionSpec
        animation::Symbol
        duration::Float64
        crowChance::Float64
    end

    const MAP_FAB_INTERACTIONS = Dict{String, MapFabInteractionSpec}(
        "grass" => MapFabInteractionSpec(:hoverSway, 0.0, 0.0),
        "tree" => MapFabInteractionSpec(:shake, 0.65, 0.25),
        "bush" => MapFabInteractionSpec(:shake, 0.45, 0.12),
        "grave" => MapFabInteractionSpec(:shake, 0.45, 0.0),
        "fence" => MapFabInteractionSpec(:shake, 0.35, 0.0),
        "skull" => MapFabInteractionSpec(:spin, 0.55, 0.0),
        "hatandwand" => MapFabInteractionSpec(:spin, 0.7, 0.0),
        "knife" => MapFabInteractionSpec(:spin, 0.5, 0.0),
        "groundhand" => MapFabInteractionSpec(:retreat, 0.8, 0.0),
        "bench" => MapFabInteractionSpec(:shake, 0.4, 0.0),
        "cone" => MapFabInteractionSpec(:shake, 0.35, 0.0),
        "can" => MapFabInteractionSpec(:spin, 0.45, 0.0),
        "cup" => MapFabInteractionSpec(:spin, 0.45, 0.0),
        "firehydrant" => MapFabInteractionSpec(:shake, 0.4, 0.0),
        "trashcan" => MapFabInteractionSpec(:shake, 0.45, 0.0),
        "trashbag" => MapFabInteractionSpec(:shake, 0.4, 0.0),
        "paperstack" => MapFabInteractionSpec(:shake, 0.35, 0.0),
        "papercrumpled" => MapFabInteractionSpec(:paperFlee, 0.0, 0.0),
        "rat" => MapFabInteractionSpec(:ratFlee, 0.0, 0.0),
        "balloon" => MapFabInteractionSpec(:balloonPop, 0.0, 0.0),
        "streetlight" => MapFabInteractionSpec(:streetlightToggle, 0.0, 0.0),
        "trafficlight" => MapFabInteractionSpec(:trafficCycle, 0.0, 0.0),
        "suitcase" => MapFabInteractionSpec(:suitcaseOpen, 0.0, 0.0),
        "pothole" => MapFabInteractionSpec(:potholeOpen, 0.0, 0.0),
        "paper" => MapFabInteractionSpec(:paperFlee, 0.0, 0.0),
        "missingposter" => MapFabInteractionSpec(:paperFlee, 0.0, 0.0),
    )

    const CROW_IDLE_ACTIVITIES = ["crowcaw", "crowclean", "crowpeck"]
    const CROW_FLIGHT_DURATION = 2.25
    const CROW_SOUND_COUNT = 13
    const CROW_CHIRP_VOLUME = 0.4
    # Next ambient caw. Negative until the first perched crow is seen.
    const _crow_ambient_wait = Ref(-1.0)
    # Crow entity id => whether its current pose is the caw frame.
    const _crow_cawing = Dict{UInt, Bool}()
    const RAT_FLEE_DURATION = 1.8
    const PAPER_FLEE_DURATION = 2.4
    const TRAFFIC_LIGHT_STATES = ["trafficlightred", "trafficlightgreen", "trafficlightyellow"]
    const TRAFFIC_LIGHT_INTERVAL = 2.4
    const MISSING_POSTER_VARIANTS = [
        "missingposterboy1",
        "missingposterboy2",
        "missingpostergirl1",
        "missingpostergirl2",
    ]
    const SUITCASE_LOOT = [
        ("paper", 4, 0.40),
        ("paperstack", 2, 0.20),
        ("papercrumpled", 4, 0.25),
        ("missingposter", 1, 0.15),
    ]
    const BALLOON_POP_SOUND = "sfx-clickswoosh"

    mutable struct MapFabInteraction
        entity
        name::String
        animation::Symbol
        duration::Float64
        elapsed::Float64
        isAnimating::Bool
        isFlying::Bool
        hasReleasedCrow::Bool
        previousHovered::Bool
        basePosition::Math.Vector3f
        baseScale::Math.Vector3f
        baseRotation::Float64
        flightVelocity::Math.Vector2f
        spawnCrow::Function
        spawnNearbyFab::Function
        assetPrefix::String
        variant::Int
        state::Symbol
        trafficIndex::Int
        autoTimer::Float64
        consumed::Bool
    end

    function map_fab_prefixed_asset(globals, assetPrefix::String, assetName::String)::String
        return globals.get_asset_path("mapfab", "$(assetPrefix)$(assetName)")
    end

    function map_fab_asset_path(
        globals,
        name::String,
        assetCount::Int,
        rng::AbstractRNG,
        assetPrefix::String,
    )::String
        prefix = assetPrefix
        # Shared graveyard fog until other themes have their own.
        if name == "fog"
            return globals.get_asset_path("mapfab", "graveyardfog$(rand(rng, 1:assetCount))")
        elseif name == "crow"
            activity = rand(rng, ["crowidle"; CROW_IDLE_ACTIVITIES])
            return globals.get_asset_path("mapfab", "$(prefix)$(activity)")
        elseif name == "streetlight"
            state = rand(rng) < 0.45 ? "streetlighton" : "streetlightoff"
            return globals.get_asset_path("mapfab", "$(prefix)$(state)")
        elseif name == "trafficlight"
            state = rand(rng, TRAFFIC_LIGHT_STATES)
            return globals.get_asset_path("mapfab", "$(prefix)$(state)")
        elseif name == "suitcase"
            return globals.get_asset_path("mapfab", "$(prefix)suitcaseclosed")
        elseif name == "mailbox"
            return globals.get_asset_path("mapfab", "$(prefix)mailboxclosed")
        elseif name == "pothole"
            return globals.get_asset_path("mapfab", "$(prefix)potholeclosed")
        elseif name == "rat"
            return globals.get_asset_path("mapfab", "$(prefix)ratidle")
        end
        return globals.get_asset_path("mapfab", "$(prefix)$(name)$(rand(rng, 1:assetCount))")
    end

    function _variant_from_image_path(imagePath::String, name::String)::Int
        m = match(Regex("$(name)(\\d+)"), imagePath)
        m === nothing && return 1
        return parse(Int, m.captures[1])
    end

    function _streetlight_state_from_path(imagePath::String)::Symbol
        return occursin("streetlighton", imagePath) ? :on : :off
    end

    function _traffic_index_from_path(imagePath::String)::Int
        occursin("trafficlightgreen", imagePath) && return 2
        occursin("trafficlightyellow", imagePath) && return 3
        return 1
    end

    function _set_fab_sprite!(entity, globals, assetPrefix::String, assetName::String)
        entity.sprite.imagePath = map_fab_prefixed_asset(globals, assetPrefix, assetName)
    end

    function _play_crow_sound(rng::AbstractRNG; volume::Float64 = 1.0)
        n = rand(rng, 1:CROW_SOUND_COUNT)
        try
            globals = JulGame.UserGlobals["Module"]
            _play_fab_sound(globals.get_asset_path("sfx", "crow$n"); volume)
        catch e
            @debug "Could not play crow sound: $e"
        end
    end

    function _update_crow_chirps!(interactions::Vector, rng::AbstractRNG)
        for interaction in interactions
            interaction.name == "crow" || continue
            interaction.entity.isActive || continue
            id = objectid(interaction.entity)
            cawing = !interaction.isFlying && occursin("crowcaw", interaction.entity.sprite.imagePath)
            if cawing && !get(_crow_cawing, id, false)
                _play_crow_sound(rng; volume = CROW_CHIRP_VOLUME)
            end
            _crow_cawing[id] = cawing
        end
    end

    function _update_crow_ambience!(interactions::Vector, deltaTime::Float64, rng::AbstractRNG)
        perched = false
        for interaction in interactions
            if interaction.name == "crow" && interaction.entity.isActive && !interaction.isFlying
                perched = true
                break
            end
        end
        perched || return
        if _crow_ambient_wait[] < 0
            _crow_ambient_wait[] = 4.0 + rand(rng) * 8.0
            return
        end
        _crow_ambient_wait[] -= deltaTime
        if _crow_ambient_wait[] <= 0
            _play_crow_sound(rng)
            _crow_ambient_wait[] = 7.0 + rand(rng) * 11.0
        end
    end
    function _play_fab_sound(path::String; volume::Float64 = 1.0)
        try
            globals = JulGame.UserGlobals["Module"]
            # play_sound only works for sounds already registered. Oneshot registers first.
            globals.AudioManagerModule.play_audio_oneshot(
                globals.get_audio_manager(),
                path,
                false, volume, 0, 1,
            )
        catch e
            @debug "Could not play map fab sound: $e"
        end
    end

    function _attach_crow_animator!(entity, rng::AbstractRNG, assetPrefix::String)
        globals = JulGame.UserGlobals["Module"]
        # Hold each pose ~2–3s at 1 FPS so idle activities read as deliberate, not frantic.
        idleFrames = String[]
        for activity in shuffle(rng, CROW_IDLE_ACTIVITIES)
            idlePath = map_fab_prefixed_asset(globals, assetPrefix, "crowidle")
            activityPath = map_fab_prefixed_asset(globals, assetPrefix, activity)
            for _ in 1:rand(rng, 2:3)
                push!(idleFrames, idlePath)
            end
            for _ in 1:rand(rng, 2:3)
                push!(idleFrames, activityPath)
            end
        end
        flightFrames = [
            map_fab_prefixed_asset(globals, assetPrefix, "crowfly1"),
            map_fab_prefixed_asset(globals, assetPrefix, "crowfly2"),
        ]
        idleAnimation = JulGame.AnimationModule.Animation(
            JulGame.Math.Vector4[],
            1,
            idleFrames,
        )
        flightAnimation = JulGame.AnimationModule.Animation(
            JulGame.Math.Vector4[],
            rand(rng, 6:8),
            flightFrames,
        )
        animator = JulGame.add_animator(
            entity,
            JulGame.AnimatorModule.Animator([idleAnimation, flightAnimation]),
        )
        startFrame = rand(rng, eachindex(idleFrames))
        animator.lastFrame = startFrame
        entity.sprite.imagePath = idleFrames[startFrame]
    end

    function register_map_fab_interaction!(
        interactions::Vector,
        entity,
        name::String,
        rng::AbstractRNG,
        assetPrefix::String;
        spawnCrow::Function = () -> nothing,
        spawnNearbyFab::Function = (args...; kwargs...) -> nothing,
    )
        spec = get(MAP_FAB_INTERACTIONS, name, nothing)
        if name != "crow" && spec === nothing
            return nothing
        end
        spec === nothing && (spec = MapFabInteractionSpec(:none, 0.0, 0.0))

        variant = _variant_from_image_path(entity.sprite.imagePath, name)
        state = :idle
        trafficIndex = 1
        if name == "streetlight"
            state = _streetlight_state_from_path(entity.sprite.imagePath)
        elseif name == "trafficlight"
            trafficIndex = _traffic_index_from_path(entity.sprite.imagePath)
            state = :cycling
        elseif name == "suitcase"
            state = :closed
        elseif name == "pothole"
            state = :closed
        elseif name == "balloon"
            state = :intact
        elseif name == "paper"
            state = :flat
        end

        interaction = MapFabInteraction(
            entity,
            name,
            spec.animation,
            spec.duration,
            0.0,
            false,
            false,
            false,
            false,
            entity.transform.position,
            entity.transform.scale,
            entity.sprite.rotation,
            Math.Vector2f(0.0, 0.0),
            spawnCrow,
            spawnNearbyFab,
            assetPrefix,
            variant,
            state,
            trafficIndex,
            rand(rng) * TRAFFIC_LIGHT_INTERVAL,
            false,
        )
        push!(interactions, interaction)

        entity.sprite.interactionScale = name == "crow" || name == "rat" ? 0.75 : 0.85
        if name == "crow"
            _attach_crow_animator!(entity, rng, assetPrefix)
        elseif name == "rat"
            # Flee on hover or click.
            entity.clickEvents = Function[() -> _start_rat_flee!(interaction, rng)]
        elseif spec.animation != :none && spec.animation != :hoverSway
            entity.clickEvents = Function[() -> _trigger_interaction!(interaction, spec, rng)]
        end
        return interaction
    end

    function _trigger_interaction!(
        interaction::MapFabInteraction,
        spec::MapFabInteractionSpec,
        rng::AbstractRNG,
    )
        anim = spec.animation
        if anim == :streetlightToggle
            _toggle_streetlight!(interaction)
            return
        elseif anim == :trafficCycle
            _advance_traffic_light!(interaction)
            return
        elseif anim == :suitcaseOpen
            _open_suitcase!(interaction, rng)
            return
        elseif anim == :potholeOpen
            _open_pothole!(interaction, rng)
            return
        elseif anim == :balloonPop
            _pop_balloon!(interaction, rng)
            return
        elseif anim == :paperFlee
            _start_paper_flee!(interaction, rng)
            return
        elseif anim == :ratFlee
            _start_rat_flee!(interaction, rng)
            return
        end

        interaction.isAnimating && return
        interaction.elapsed = 0.0
        interaction.isAnimating = true
        # Crow assets are graveyard-only; never release them from other themes.
        if !interaction.hasReleasedCrow &&
           interaction.assetPrefix == "graveyard" &&
           spec.crowChance > 0.0 &&
           rand(rng) < spec.crowChance
            interaction.hasReleasedCrow = true
            interaction.spawnCrow()
        end
    end

    function _toggle_streetlight!(interaction::MapFabInteraction)
        globals = JulGame.UserGlobals["Module"]
        if interaction.state == :on
            interaction.state = :off
            _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, "streetlightoff")
        else
            interaction.state = :on
            _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, "streetlighton")
        end
    end

    function _set_traffic_sprite!(interaction::MapFabInteraction)
        globals = JulGame.UserGlobals["Module"]
        assetName = TRAFFIC_LIGHT_STATES[interaction.trafficIndex]
        _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, assetName)
    end

    function _advance_traffic_light!(interaction::MapFabInteraction)
        interaction.trafficIndex = interaction.trafficIndex % length(TRAFFIC_LIGHT_STATES) + 1
        interaction.autoTimer = 0.0
        _set_traffic_sprite!(interaction)
    end

    function _update_traffic_light!(interaction::MapFabInteraction, deltaTime::Float64)
        interaction.autoTimer += deltaTime
        if interaction.autoTimer >= TRAFFIC_LIGHT_INTERVAL
            interaction.autoTimer = 0.0
            interaction.trafficIndex = interaction.trafficIndex % length(TRAFFIC_LIGHT_STATES) + 1
            _set_traffic_sprite!(interaction)
        end
    end

    function _pick_suitcase_loot(rng::AbstractRNG)
        roll = rand(rng)
        cumulative = 0.0
        for (name, assetCount, weight) in SUITCASE_LOOT
            cumulative += weight
            if roll <= cumulative
                return (name, assetCount)
            end
        end
        return ("paper", 4)
    end

    function _open_suitcase!(interaction::MapFabInteraction, rng::AbstractRNG)
        interaction.consumed && return
        interaction.consumed = true
        interaction.state = :open
        globals = JulGame.UserGlobals["Module"]
        _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, "suitcaseopen")
        interaction.entity.clickEvents = Function[]

        lootCount = rand(rng, 3:5)
        for _ in 1:lootCount
            lootName, assetCount = _pick_suitcase_loot(rng)
            if lootName == "missingposter"
                assetName = rand(rng, MISSING_POSTER_VARIANTS)
                interaction.spawnNearbyFab(
                    "missingposter",
                    1;
                    assetName = assetName,
                    scatter = 2.4,
                )
            else
                interaction.spawnNearbyFab(lootName, assetCount; scatter = 2.4)
            end
        end
    end

    function _open_pothole!(interaction::MapFabInteraction, rng::AbstractRNG)
        interaction.consumed && return
        interaction.consumed = true
        globals = JulGame.UserGlobals["Module"]
        if rand(rng) < 0.28
            interaction.state = :evil
            _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, "potholeevil")
        else
            interaction.state = :open
            _set_fab_sprite!(interaction.entity, globals, interaction.assetPrefix, "potholeopen")
        end
        interaction.entity.clickEvents = Function[]
    end

    function _pop_balloon!(interaction::MapFabInteraction, rng::AbstractRNG)
        interaction.consumed && return
        interaction.consumed = true
        interaction.state = :popped
        globals = JulGame.UserGlobals["Module"]
        _play_fab_sound(JulGame.UserGlobals["Module"].get_asset_path(BALLOON_POP_SOUND))
        _set_fab_sprite!(
            interaction.entity,
            globals,
            interaction.assetPrefix,
            "balloonpopped$(interaction.variant)",
        )
        interaction.entity.clickEvents = Function[]
        interaction.entity.ignoreInputEvents = true
        interaction.spawnNearbyFab(
            "popeffect",
            1;
            assetName = "popeffect1",
            lifetime = 0.35,
            offsetY = -0.25,
        )
    end

    function _start_rat_flee!(interaction::MapFabInteraction, rng::AbstractRNG)
        (interaction.name != "rat" || interaction.isFlying) && return
        interaction.isFlying = true
        interaction.isAnimating = false
        interaction.consumed = true
        interaction.elapsed = 0.0
        interaction.animation = :ratFlee
        interaction.entity.clickEvents = Function[]
        interaction.entity.ignoreInputEvents = true
        horizontalDirection = rand(rng) < 0.5 ? -1.0 : 1.0
        # Mostly horizontal scurry along the ground.
        interaction.flightVelocity = Math.Vector2f(
            horizontalDirection * (5.5 + rand(rng) * 2.5),
            (rand(rng) - 0.5) * 0.6,
        )
        interaction.entity.sprite.isFlipped = horizontalDirection > 0
    end

    function _start_paper_flee!(interaction::MapFabInteraction, rng::AbstractRNG)
        interaction.isFlying && return
        interaction.isFlying = true
        interaction.isAnimating = false
        interaction.consumed = true
        interaction.elapsed = 0.0
        interaction.animation = :paperFlee
        interaction.entity.clickEvents = Function[]
        interaction.entity.ignoreInputEvents = true

        # Flat paper crumples as it catches the wind.
        if interaction.name == "paper"
            globals = JulGame.UserGlobals["Module"]
            _set_fab_sprite!(
                interaction.entity,
                globals,
                interaction.assetPrefix,
                "papercrumpled$(interaction.variant)",
            )
            interaction.state = :crumpled
        end

        horizontalDirection = rand(rng) < 0.5 ? -1.0 : 1.0
        interaction.flightVelocity = Math.Vector2f(
            horizontalDirection * (2.8 + rand(rng) * 2.2),
            -(1.8 + rand(rng) * 2.2),
        )
    end

    function start_crow_flight!(interaction::MapFabInteraction, rng::AbstractRNG)
        if interaction.name != "crow" || interaction.isFlying
            return
        end
        interaction.isFlying = true
        interaction.isAnimating = false
        interaction.elapsed = 0.0
        horizontalDirection = rand(rng) < 0.5 ? -1.0 : 1.0
        interaction.flightVelocity = Math.Vector2f(
            horizontalDirection * (4.5 + rand(rng) * 2.5),
            -(2.0 + rand(rng) * 2.0),
        )
        interaction.entity.sprite.isFlipped = horizontalDirection > 0
        _play_crow_sound(rng)

        animator = interaction.entity.animator
        if animator !== nothing && animator != C_NULL && length(animator.animations) >= 2
            animator.currentAnimation = animator.animations[2]
            animator.lastFrame = 0
            animator.playOnce = false
        end
    end

    function _update_click_animation!(interaction::MapFabInteraction, deltaTime::Float64)
        interaction.elapsed += deltaTime
        progress = clamp(interaction.elapsed / interaction.duration, 0.0, 1.0)
        fade = 1.0 - progress

        if interaction.animation == :shake
            interaction.entity.sprite.rotation =
                interaction.baseRotation + sin(progress * 8π) * 12.0 * fade
        elseif interaction.animation == :spin
            interaction.entity.sprite.rotation =
                interaction.baseRotation + 360.0 * sin(progress * π)
        elseif interaction.animation == :retreat
            retreat = sin(progress * π)
            interaction.entity.transform.scale = Math.Vector3f(
                interaction.baseScale.x,
                interaction.baseScale.y * (1.0 - 0.8 * retreat),
                interaction.baseScale.z,
            )
            interaction.entity.transform.position = Math.Vector3f(
                interaction.basePosition.x,
                interaction.basePosition.y + 0.4 * retreat,
                interaction.basePosition.z,
            )
        end

        if progress >= 1.0
            interaction.entity.sprite.rotation = interaction.baseRotation
            interaction.entity.transform.position = interaction.basePosition
            interaction.entity.transform.scale = interaction.baseScale
            interaction.isAnimating = false
        end
    end

    function _update_flee_motion!(interaction::MapFabInteraction, deltaTime::Float64)
        interaction.elapsed += deltaTime
        position = interaction.entity.transform.position
        interaction.entity.transform.position = Math.Vector3f(
            position.x + interaction.flightVelocity.x * deltaTime,
            position.y + interaction.flightVelocity.y * deltaTime,
            position.z,
        )

        duration = if interaction.animation == :ratFlee
            RAT_FLEE_DURATION
        elseif interaction.animation == :paperFlee
            # Flutter / tumble while drifting away.
            interaction.entity.sprite.rotation =
                interaction.baseRotation + interaction.elapsed * 520.0
            interaction.flightVelocity = Math.Vector2f(
                interaction.flightVelocity.x,
                interaction.flightVelocity.y + sin(interaction.elapsed * 14.0) * 1.8 * deltaTime,
            )
            PAPER_FLEE_DURATION
        else
            CROW_FLIGHT_DURATION
        end

        if interaction.elapsed >= duration
            interaction.entity.isActive = false
        end
    end

    function _update_hover_sway!(interaction::MapFabInteraction, deltaTime::Float64)
        if interaction.entity.isHovered
            interaction.elapsed += deltaTime
            interaction.entity.sprite.rotation =
                interaction.baseRotation + sin(interaction.elapsed * 8π) * 1.25
        else
            interaction.elapsed = 0.0
            interaction.entity.sprite.rotation = interaction.baseRotation
        end
    end

    function update_map_fab_interactions!(
        interactions::Vector,
        deltaTime::Float64,
        rng::AbstractRNG,
    )
        _update_crow_ambience!(interactions, deltaTime, rng)
        _update_crow_chirps!(interactions, rng)
        for interaction in interactions
            interaction.entity.isActive || continue

            if interaction.animation == :hoverSway
                _update_hover_sway!(interaction, deltaTime)
                continue
            elseif interaction.animation == :trafficCycle
                _update_traffic_light!(interaction, deltaTime)
                continue
            elseif interaction.name == "crow"
                if interaction.entity.isHovered &&
                   !interaction.previousHovered &&
                   !interaction.isFlying
                    start_crow_flight!(interaction, rng)
                end
                interaction.previousHovered = interaction.entity.isHovered
            elseif interaction.name == "rat"
                if interaction.entity.isHovered &&
                   !interaction.previousHovered &&
                   !interaction.isFlying
                    _start_rat_flee!(interaction, rng)
                end
                interaction.previousHovered = interaction.entity.isHovered
            end

            if interaction.isFlying
                _update_flee_motion!(interaction, deltaTime)
            elseif interaction.isAnimating
                _update_click_animation!(interaction, deltaTime)
            end
        end
    end
end
