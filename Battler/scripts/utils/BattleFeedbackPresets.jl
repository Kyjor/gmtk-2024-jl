# Battle Feedback Presets - High-level API for common battle feedback scenarios
# This module provides easy-to-use functions for common battle events
# Uses Observer pattern to respond to battle events

module BattleFeedbackPresetsModule
using JulGame
include("DisplayText.jl")
using .DisplayTextModule
using ..ActionResultDisplayModule
include("BattleFeedbackSystem.jl")
using .BattleFeedbackSystemModule
include("../localization/battle_strings.jl")
using .BattleStringsModule

# One global feedback observer per process (battle init may run many times per session).
feedback_observer_registered = false

"""
Initialize the feedback system observer.
Call this during battle initialization to start listening for events.
"""
function initialize_feedback_observer()
    global feedback_observer_registered
    if feedback_observer_registered
        return
    end
    try
        globals = JulGame.UserGlobals["Module"]
        globals.ObserverModule.add_observer((event, data) -> on_feedback_event(event, data))
        feedback_observer_registered = true
        @debug "Feedback system observer initialized"
    catch e
        @error "Failed to initialize feedback observer: $(e)"
    end
end

"""
Main event handler for all feedback events.
Responds to events emitted throughout the battle system.
"""
function on_feedback_event(event::Symbol, data::Any)
    try
        if event == :damage_dealt
            handle_damage_event(data)
        elseif event == :healing_received
            handle_healing_event(data)
        elseif event == :shield_gained
            handle_shield_event(data)
        elseif event == :status_applied
            handle_status_event(data)
        elseif event == :gold_collected
            handle_gold_event(data)
        elseif event == :attack_missed
            handle_miss_event(data)
        elseif event == :ability_activated
            handle_ability_event(data)
        elseif event == :enemy_attacking
            handle_enemy_attack_indicator(data)
        elseif event == :dodge_success
            handle_dodge_event(data)
        elseif event == :reflect_success
            handle_reflect_event(data)
        elseif event == :victory
            victory_feedback()
        elseif event == :defeat
            defeat_screen_feedback()
        elseif event == :enemy_defeated
            handle_enemy_defeat_event(data)
        elseif event == :combo_achieved
            handle_combo_event(data)
        elseif event == :match_made
            handle_match_event(data)
        elseif event == :special_text
            handle_special_text_event(data)
        end
    catch e
        @debug "Error handling feedback event $(event): $(e)"
    end
end

# === EVENT HANDLERS ===

function handle_damage_event(data)
    if haskey(data, :damage)
        is_critical = get(data, :is_critical, false)
        damage_type = get(data, :damage_type, :physical)
        is_recoil = get(data, :is_recoil, false)

        # Determine target
        if haskey(data, :target)
            # Direct target provided (from BattleManager)
            damage_feedback(data[:target], data[:damage]; is_critical=is_critical, damage_type=damage_type)

            # Show recoil text
            if is_recoil
                try
                    DisplayTextModule.display_text(
                        "recoil_$(rand(1000:9999))",
                        BattleStringsModule.BATTLE_STRINGS[:feedback_recoil];
                        fontSize=24,
                        anchor=:center,
                        lifetime=800,
                        color=(150, 50, 50, 255)
                    )
                catch e
                    @debug "Error showing recoil text: $(e)"
                end
            end
        elseif haskey(data, :battle_manager) && haskey(data, :target_type)
            # Get entity from battle_manager
            if data[:target_type] == :player
                player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
                if player_entity !== nothing
                    damage_feedback(player_entity, data[:damage]; is_critical=is_critical, damage_type=damage_type)

                    # Show recoil text
                    if is_recoil
                        try
                            DisplayTextModule.display_text(
                                "recoil_$(rand(1000:9999))",
                                BattleStringsModule.BATTLE_STRINGS[:feedback_recoil];
                                fontSize=24,
                                anchor=:center,
                                lifetime=800,
                                color=(150, 50, 50, 255)
                            )
                        catch e
                            @debug "Error showing recoil text: $(e)"
                        end
                    end
                end
            end
        end
    end
end

function handle_healing_event(data)
    if haskey(data, :battle_manager) && haskey(data, :amount)
        # Get player entity
        player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        if player_entity !== nothing
            healing_feedback(player_entity, data[:amount])

            # Special lifesteal text
            if get(data, :is_lifesteal, false)
                try
                    DisplayTextModule.display_text(
                        "lifesteal_$(rand(1000:9999))",
                        BattleStringsModule.BATTLE_STRINGS[:feedback_lifesteal];
                        fontSize=24,
                        anchor=:center,
                        lifetime=1000,
                        color=(200, 50, 50, 255)
                    )
                catch e
                    @debug "Error showing lifesteal text: $(e)"
                end
            end
        end
    end
end

function handle_shield_event(data)
    if haskey(data, :battle_manager) && haskey(data, :amount)
        # Get player entity
        player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        if player_entity !== nothing
            shield_feedback(player_entity, data[:amount])
        end
    end
end

function handle_status_event(data)
    if haskey(data, :target) && haskey(data, :status_type) && haskey(data, :duration)
        target = data[:target]
        status_type = data[:status_type]
        duration = data[:duration]

        if status_type == :freeze
            freeze_feedback(target, duration)
        elseif status_type == :burn
            burn_feedback(target, duration)
        elseif status_type == :poison
            poison_feedback(target, duration)
        elseif status_type == :vulnerable
            # Purple flash + text
            BattleFeedbackSystemModule.add_visual_effect(
                target, :flash;
                duration=0.5,
                intensity=0.9,
                color=(200, 100, 255, 255)
            )
            show_status_text(target, "Vulnerable $(duration)", (200, 100, 255, 255))
        end
    end
end

function handle_gold_event(data)
    if haskey(data, :battle_manager) && haskey(data, :amount)
        amount = data[:amount]

        # Get player entity
        player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        if player_entity !== nothing
            # Golden sparkles
            BattleFeedbackSystemModule.add_particle_effect(
                player_entity, :sparkles;
                count=15,
                duration=0.7,
                spawn_rate=40.0
            )
            BattleFeedbackSystemModule.add_visual_effect(
                player_entity, :scale_pulse;
                duration=0.4,
                intensity=1.1
            )

            # Display gold text
            try
                DisplayTextModule.display_text(
                    "gold_$(rand(1000:9999))",
                    BattleStringsModule.format_string(:feedback_gold_collected, amount=amount);
                    fontSize=28,
                    anchor=:center,
                    lifetime=1000,
                    color=(255, 215, 0, 255)
                )
            catch e
                @debug "Error showing gold text: $(e)"
            end

            BattleFeedbackSystemModule.queue_audio("gold_collect", 0.0)
        end
    end
end

function handle_miss_event(data)
    if haskey(data, :target)
        show_status_text(data[:target], BattleStringsModule.BATTLE_STRINGS[:feedback_miss], (200, 200, 200, 255))
    end
end

function handle_ability_event(data)
    if haskey(data, :ability_type) && haskey(data, :battle_manager)
        ability_type = data[:ability_type]

        # Get player entity
        player_entity = JulGame.SceneModule.get_entity_by_id("95b3f5d9-a580-4a15-b745-9ecf1fc76620")
        if player_entity !== nothing
            if ability_type == :reflect_ready
                BattleFeedbackSystemModule.add_visual_effect(
                    player_entity, :flash;
                    duration=0.5,
                    intensity=0.7,
                    color=(200, 150, 255, 255)
                )
                show_status_text(player_entity, BattleStringsModule.BATTLE_STRINGS[:feedback_reflect_ready], (200, 150, 255, 255))
                try
                    globals = JulGame.UserGlobals["Module"]
                    globals.AudioManagerModule.play_audio_oneshot(
                        globals.get_audio_manager(),
                        globals.get_asset_path("sfx", "activeitemready"),
                        false, 1.0, 0, 1,
                    )
                catch
                end
            elseif ability_type == :dodge_ready
                BattleFeedbackSystemModule.add_visual_effect(
                    player_entity, :flash;
                    duration=0.4,
                    intensity=0.8,
                    color=(255, 255, 255, 255)
                )
                show_status_text(player_entity, BattleStringsModule.BATTLE_STRINGS[:feedback_dodge_ready], (255, 255, 255, 255))
                try
                    globals = JulGame.UserGlobals["Module"]
                    globals.AudioManagerModule.play_audio_oneshot(
                        globals.get_audio_manager(),
                        globals.get_asset_path("sfx", "activeitemready"),
                        false, 1.0, 0, 1,
                    )
                catch
                end
            end
        end
    end
end

function handle_enemy_attack_indicator(data)
    if haskey(data, :enemy) && haskey(data, :target)
        show_enemy_attack_indicator(data[:enemy], data[:target])
    end
end

function handle_dodge_event(data)
    if haskey(data, :target)
        dodge_feedback(data[:target])
    end
end

function handle_reflect_event(data)
    if haskey(data, :target) && haskey(data, :source)
        reflect_feedback(data[:target], data[:source])
    end
end

function handle_enemy_defeat_event(data)
    if haskey(data, :enemy)
        defeat_feedback(data[:enemy])
    end
end

function handle_combo_event(data)
    if haskey(data, :combo_count)
        combo_type = get(data, :combo_type, "")
        combo_feedback(data[:combo_count], combo_type)
    end
end

function handle_match_event(data)
    if haskey(data, :match_count) && haskey(data, :piece_type)
        match_feedback(data[:match_count], data[:piece_type])
    end
end

function handle_special_text_event(data)
    if haskey(data, :text) && haskey(data, :color)
        try
            DisplayTextModule.display_text(
                "special_$(rand(1000:9999))",
                data[:text];
                fontSize=28,
                anchor=:center,
                lifetime=1200,
                color=data[:color]
            )
        catch e
            @debug "Error showing special text: $(e)"
        end
    end
end

# === DAMAGE FEEDBACK ===

function damage_feedback(
    target::Any,
    damage_amount::Int;
    is_critical::Bool=false,
    damage_type::Symbol=:physical
)
    # Visual: flash red + shake
    intensity = is_critical ? 1.5 : 1.0
    duration = is_critical ? 0.5 : 0.3

    # Flash effect
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=duration,
        intensity=intensity,
        color=get_damage_color(damage_type),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Shake effect
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :shake;
        duration=duration * 0.8,
        intensity=0.15 * intensity,
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Floating damage number
    show_damage_number(target, damage_amount, is_critical, damage_type)

    # Impact particles
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :impact;
        count=is_critical ? 15 : 8,
        duration=0.4,
        spawn_rate=40.0
    )

    # Screen effect for player damage
    if is_player_entity(target)
        screen_intensity = min(damage_amount / 10.0, 0.7)
        BattleFeedbackSystemModule.add_screen_effect(
            :flash;
            duration=0.4,
            intensity=screen_intensity,
            color=(255, 0, 0, 100),
            easing=BattleFeedbackSystemModule.ease_out_cubic
        )
    end

    # Audio
    sound = is_critical ? "critical_hit" : "damage_hit"
    BattleFeedbackSystemModule.queue_audio(sound, 0.0)
end

function get_damage_color(damage_type::Symbol)
    if damage_type == :physical
        return (255, 50, 50, 255)
    elseif damage_type == :fire
        return (255, 100, 0, 255)
    elseif damage_type == :ice
        return (100, 150, 255, 255)
    elseif damage_type == :poison
        return (150, 255, 100, 255)
    else
        return (255, 255, 255, 255)
    end
end

function show_damage_number(target, damage_amount, is_critical, damage_type)
    # Numbers are owned by ActionResultDisplay via BattleJuice.
end

# === HEALING FEEDBACK ===

function healing_feedback(target::Any, heal_amount::Int)
    # Visual: flash green + pulse
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.5,
        intensity=0.8,
        color=(100, 255, 100, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :scale_pulse;
        duration=0.6,
        intensity=1.2,
        easing=BattleFeedbackSystemModule.ease_out_elastic
    )

    # Healing particles
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :healing;
        count=12,
        duration=1.0,
        spawn_rate=25.0
    )

    # Floating heal number
    show_heal_number(target, heal_amount)

    # Audio
    BattleFeedbackSystemModule.queue_audio("heal", 0.0)
end

function show_heal_number(target, heal_amount)
    # Numbers are owned by ActionResultDisplay via BattleJuice.
end

# === STATUS EFFECT FEEDBACK ===

function freeze_feedback(target::Any, freeze_duration::Int)
    # Blue flash + ice particles
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.6,
        intensity=1.0,
        color=(100, 150, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Ice particles around entity
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :ice;
        count=20,
        duration=Float64(freeze_duration),
        spawn_rate=8.0
    )

    # Status text
    show_status_text(target, "Frozen $(freeze_duration)", (150, 200, 255, 255))

    # Audio
    BattleFeedbackSystemModule.queue_audio("freeze", 0.0)
end

function burn_feedback(target::Any, burn_duration::Int)
    # Orange/red flash + fire particles
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.6,
        intensity=1.0,
        color=(255, 100, 50, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Fire particles
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :fire;
        count=15,
        duration=Float64(burn_duration),
        spawn_rate=10.0
    )

    # Status text
    show_status_text(target, "Burn $(burn_duration)", (255, 150, 50, 255))

    # Audio
    BattleFeedbackSystemModule.queue_audio("burn", 0.0)
end

function poison_feedback(target::Any, poison_duration::Int)
    # Purple-green flash
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.6,
        intensity=1.0,
        color=(150, 100, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Status text
    show_status_text(target, "Poison $(poison_duration)", (200, 100, 255, 255))

    # Audio
    BattleFeedbackSystemModule.queue_audio("poison", 0.0)
end

function shield_feedback(target::Any, shield_amount::Int)
    # Cyan flash + sparkles
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.5,
        intensity=0.9,
        color=(100, 200, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :scale_pulse;
        duration=0.5,
        intensity=1.15,
        easing=BattleFeedbackSystemModule.ease_out_elastic
    )

    # Sparkle particles
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :sparkles;
        count=15,
        duration=0.8,
        spawn_rate=30.0
    )

    # Shield number is owned by ActionResultDisplay via BattleJuice.

    # Audio
    BattleFeedbackSystemModule.queue_audio("shield", 0.0)
end

function show_status_text(target, text, color)
    ActionResultDisplayModule.push(target; kind = :status, value = text, color = color)
end

# === ENEMY ATTACK INDICATOR ===

function show_enemy_attack_indicator(enemy::Any, target::Any)
    # Flash the attacking enemy to identify them
    BattleFeedbackSystemModule.add_visual_effect(
        enemy,
        :flash;
        duration=0.4,
        intensity=0.8,
        color=(255, 255, 100, 255),
        easing=BattleFeedbackSystemModule.ease_in_out_cubic
    )

    BattleFeedbackSystemModule.add_visual_effect(
        enemy,
        :scale_pulse;
        duration=0.4,
        intensity=1.2,
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Audio cue
    BattleFeedbackSystemModule.queue_audio("enemy_telegraph", 0.0)
end

# === COMBO/CHAIN EFFECTS ===

function combo_feedback(combo_count::Int, combo_type::String="")
    # Screen flash that intensifies with combo count
    intensity = min(combo_count / 10.0, 1.0)

    BattleFeedbackSystemModule.add_screen_effect(
        :flash;
        duration=0.3,
        intensity=intensity,
        color=(255, 215, 0, 80),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Combo text
    combo_text = combo_type == "" ? BattleStringsModule.format_string(:feedback_combo_generic, count=combo_count) : BattleStringsModule.format_string(:feedback_combo_typed, count=combo_count, type=combo_type)

    try
        DisplayTextModule.display_text(
            "combo_$(rand(1000:9999))",
            combo_text;
            fontSize=42 + (combo_count * 2),
            anchor=:center,
            lifetime=1200,
            color=(255, 215, 0, 255)
        )
    catch e
        @debug "Error showing combo text: $(e)"
    end

    # Audio
    sound = combo_count >= 5 ? "combo_high" : "combo"
    BattleFeedbackSystemModule.queue_audio(sound, 0.0)
end

# === MATCH/PIECE EFFECTS ===

function match_feedback(match_count::Int, piece_type::String)
    # Flash effect at match location - more intense for larger matches
    intensity = min(0.5 + (match_count * 0.1), 1.2)

    # Color based on piece type
    match_color = get_piece_color(piece_type)

    # Screen flash for large matches
    if match_count >= 4
        BattleFeedbackSystemModule.add_screen_effect(
            :flash;
            duration=0.25,
            intensity=0.3,
            color=(match_color[1], match_color[2], match_color[3], 100),
            easing=BattleFeedbackSystemModule.ease_out_cubic
        )
    end

    # Audio
    BattleFeedbackSystemModule.queue_audio("match_$(match_count)", 0.0)
end

function piece_swap_feedback()
    # Subtle audio/visual feedback for swapping
    BattleFeedbackSystemModule.queue_audio("swap", 0.0)
end

function get_piece_color(piece_type::String)
    if contains(lowercase(piece_type), "sword")
        return (255, 100, 100, 255)
    elseif contains(lowercase(piece_type), "shield")
        return (100, 150, 255, 255)
    elseif contains(lowercase(piece_type), "heart") || contains(lowercase(piece_type), "potion")
        return (100, 255, 100, 255)
    elseif contains(lowercase(piece_type), "fire") || contains(lowercase(piece_type), "burn")
        return (255, 150, 50, 255)
    elseif contains(lowercase(piece_type), "ice") || contains(lowercase(piece_type), "freeze")
        return (150, 200, 255, 255)
    else
        return (255, 255, 255, 255)
    end
end

# === DEATH/DEFEAT FEEDBACK ===

function defeat_feedback(target::Any)
    # Create a dramatic death sequence
    effects = [
        () -> begin
            # Flash white
            BattleFeedbackSystemModule.add_visual_effect(
                target,
                :flash;
                duration=0.3,
                intensity=1.5,
                color=(255, 255, 255, 255)
            )
        end,
        () -> begin
            # Fade out
            BattleFeedbackSystemModule.add_visual_effect(
                target,
                :tint;
                duration=0.8,
                intensity=1.0,
                color=(0, 0, 0, 0)
            )
        end
    ]

    delays = [0.0, 0.3]

    BattleFeedbackSystemModule.create_effect_chain(effects, delays)

    # Audio
    BattleFeedbackSystemModule.queue_audio("enemy_defeat", 0.0)
end

# === UTILITY FUNCTIONS ===

function is_player_entity(entity::Any)
    try
        # Check if this is the player entity (adjust based on your game's structure)
        if isdefined(entity, :name) && contains(lowercase(string(entity.name)), "player")
            return true
        end
        if isdefined(entity, :health) && isdefined(entity, :gold)
            return true  # Likely player if has both health and gold
        end
    catch e
        @debug "Error checking if player entity: $(e)"
    end
    return false
end

# === VICTORY/DEFEAT SCREEN EFFECTS ===

function victory_feedback()
    # Screen flash gold
    BattleFeedbackSystemModule.add_screen_effect(
        :flash;
        duration=1.0,
        intensity=0.6,
        color=(255, 215, 0, 100),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Audio
    BattleFeedbackSystemModule.queue_audio("victory", 0.0)
end

function defeat_screen_feedback()
    # Screen flash dark red
    BattleFeedbackSystemModule.add_screen_effect(
        :flash;
        duration=1.5,
        intensity=0.8,
        color=(100, 0, 0, 120),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Audio
    BattleFeedbackSystemModule.queue_audio("defeat", 0.0)
end

# === DODGE FEEDBACK ===

function dodge_feedback(target::Any)
    # Quick flash + scale pulse for "miss" effect
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.25,
        intensity=0.8,
        color=(255, 255, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Status text
    show_status_text(target, BattleStringsModule.BATTLE_STRINGS[:feedback_dodge], (255, 255, 255, 255))

    # Audio
    BattleFeedbackSystemModule.queue_audio("dodge", 0.0)
end

# === REFLECT FEEDBACK ===

function reflect_feedback(target::Any, source::Any)
    # Flash effect on both entities
    BattleFeedbackSystemModule.add_visual_effect(
        target,
        :flash;
        duration=0.3,
        intensity=1.0,
        color=(200, 150, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    BattleFeedbackSystemModule.add_visual_effect(
        source,
        :flash;
        duration=0.3,
        intensity=1.0,
        color=(200, 150, 255, 255),
        easing=BattleFeedbackSystemModule.ease_out_cubic
    )

    # Sparkle particles
    BattleFeedbackSystemModule.add_particle_effect(
        target,
        :sparkles;
        count=20,
        duration=0.5,
        spawn_rate=60.0
    )

    # Status text
    show_status_text(target, BattleStringsModule.BATTLE_STRINGS[:feedback_reflected], (200, 150, 255, 255))

    # Audio
    BattleFeedbackSystemModule.queue_audio("reflect", 0.0)
end

end # module
