module UserModule
using ..Globals
using JulGame
include("DisplayText.jl")
using .DisplayTextModule
using JulGame.FX.ImageFXModule  # Add import for ImageFXModule
import ...HeartFillFXModule
import ...CharacterPoseControllerModule
using JulGame.EffectsModule
using Random
include("../shared-types/Combatant.jl")
include("Constants.jl")
include("FloatingAnimation.jl")
using .FloatingAnimationModule

export has_treasure, take_damage, add_piece_with_gem_limit!, apply_out_of_combat_damage!, ensure_out_of_combat_survival!, add_potion!, with_weight, with_rarity, piece_board_share, rarity_for_share, NEW_PIECE_ENTRY_SHARE, owned_weight_total, weight_for_new_piece, with_new_piece_weight

# Easing functions for smooth animations
function ease_in_out_sine(x::Float64)::Float64
    return -(cos(π * x) - 1) / 2
end

function ease_out_sine(x::Float64)::Float64
    return sin((x * π) / 2)
end

mutable struct User <: Combatant
    parent # do not remove this line, this is a reference to the entity that this script is attached to
    # This is where you define your script's fields
    # Example: speed::Float64
    userName::String
    userScore::Int64
    playerEntity
    healthHeart::Any
    healthHeartBackground::Any
    pieceCollection
    shadowCloakUsed::Bool
    bag

    selectedCharacter::String
    # Floating animation
    floatingAnimation::FloatingAnimation
    shieldUI::Any

    first_attack_bonus::Bool
    """One-shot flag: Stake treasure max-HP reduction already applied (see BattleManager initialize)."""
    stake_applied::Bool
    """Per-floor: Ancient Shield death cheat already used (reset in PersistentStateManager on floor change)."""
    ancient_shield_used::Bool

    function User(piece_data)
        this = new() # do not remove this line

        this.userName = "User"
        this.userScore = 0
        this.pieceCollection = piece_data
        this.stake_applied = false
        this.ancient_shield_used = false
        reset_player(this)
        this.bag = nothing
        this.selectedCharacter = "CHARACTER_MAGICIAN"
        this.shadowCloakUsed = false
        this.first_attack_bonus = false
        # Initialize floating animation with custom settings
        this.floatingAnimation = FloatingAnimation(
            speed=1.5,
            verticalAmplitude=4.2 / 64.0,
            horizontalAmplitude=3.2 / 64.0,
            rotationAmplitude=4.0
        )

        return this # do not remove this line
    end
end

# This is called when a scene is loaded, or when script is added to an entity
# This is where you should register collision events or other events
# Do not remove this function
function initialize(this::User)
    this.playerEntity = JulGame.SceneModule.get_entity_by_id(Globals.MAIN.scene, "95b3f5d9-a580-4a15-b745-9ecf1fc76620")


    # Initialize the floating animation with the player sprite
    if this.playerEntity !== nothing && this.playerEntity.sprite !== nothing
        idle_path = CharacterPoseControllerModule.get_pose_art(this.selectedCharacter, :idle)
        idle_path === nothing || (this.playerEntity.sprite.imagePath = idle_path)

        initialize_floating_animation(this.floatingAnimation, this.playerEntity.sprite)
    end
    this.healthHeart = JulGame.SceneModule.get_entity_by_id("d861dd98-326e-4edd-b568-9c9d31c21e4e")
    this.healthHeartBackground = JulGame.SceneModule.get_entity_by_id("b003f09f-d13f-49ec-8515-64ae302e1a21")
    if this.healthHeart !== nothing && this.healthHeartBackground !== nothing
        fg_pos = this.healthHeart.transform.position
        this.healthHeartBackground.transform.position = Math.Vector3f(
            fg_pos.x + HEART_BACKGROUND_OFFSET,
            fg_pos.y + HEART_BACKGROUND_OFFSET,
            fg_pos.z,
        )
        this.healthHeartBackground.transform.scale = Math.Vector2f(1.04, 1.04)
        this.healthHeartBackground.sprite.layer = 3
        this.healthHeart.sprite.layer = 4
        this.healthHeartBackground.isActive = true
    end
    
    # Apply border effect to player heart sprite (thin black border)
    if this.healthHeart !== nothing && this.healthHeart.sprite !== nothing
        # heart_border_effect = [
        #     EffectsModule.StrokeEffect(width=3, color=(0,0,0,255))
        # ]
        # JulGame.apply_effects!(this.healthHeart.sprite, heart_border_effect)
    end
    
    this.shieldUI = JulGame.SceneModule.get_entity_by_id("91d4a2d0-ed2a-4a3c-bcc6-215e8f86dec3")
    this.shieldUI.isActive = false
    this.shieldUI.transform.position = this.healthHeart.transform.position
    this.shieldUI.sprite.layer = 4
end

# This is called every frame
# Do not remove this function
function update(this, deltaTime)
    try
        if parentmodule(parentmodule(@__MODULE__)).PlayerDeathAnimatorModule.owns(this.playerEntity)
            return
        end
    catch
    end
    # Update floating animation
    update_floating_animation(this.floatingAnimation, deltaTime)
    if this.healthHeart !== nothing && this.healthHeart.sprite !== nothing
        max_hp = max(this.maxHealth, 1)
        shown, highlight = HeartFillFXModule.present!("player", Float64(this.health) / Float64(max_hp), Float64(deltaTime))
        this.healthHeart.sprite.color = highlight >= 0 ? HeartFillFXModule.FLASH_COLOR : HeartFillFXModule.IDLE_COLOR
        gfx_clock_hand_sweep(
            this.healthHeart.sprite,
            shown;
            highlight_below=highlight,
            bake_tint=HeartFillFXModule.BAKE_TINT,
        )
    end

    if this.shield > 0 && this.shieldUI.isActive == false
        this.shieldUI.isActive = true
    elseif this.shield <= 0 && this.shieldUI.isActive == true
        this.shieldUI.isActive = false
    end

    if this.shieldUI.isActive
        # render immediate text with the shield value
        DisplayTextModule.display_text(
            "shield_text",
            "$(this.shield)";
            fontSize=BATTLE_NUMBER_FONT_SIZE,
            fontPath=BATTLE_NUMBER_FONT,
            anchor=:center,
            color=(255, 255, 255, 255),
            parent=this.shieldUI.sprite
        )
    end

    #render immediate text with the health value
    DisplayTextModule.display_text(
        "health_text",
        "$(this.health)";
        fontSize=BATTLE_NUMBER_FONT_SIZE,
        fontPath=BATTLE_NUMBER_FONT,
        anchor=:centerBottom,
        anchorOffset=JulGame.Math.Vector2(
            0,
            25
        ),
        color=(255, 255, 255, 255),
        parent=this.healthHeart.sprite
    )
    #@debug "lastRenderedScreenPosition: $(this.healthHeart.sprite.lastRenderedScreenPosition), lastRenderedScreenSize: $(this.healthHeart.sprite.lastRenderedScreenSize)"
end

# This is called when the script is removed from an entity (scene change, entity deletion)
# Do not remove this function

function is_automated_test_mode()::Bool
    return get(ENV, "BUILD_MODE_TEST", "false") == "true" || get(ENV, "TEST_MODE", "false") == "true"
end

function apply_automated_test_buffs!(this::User)
    if !is_automated_test_mode()
        return
    end
    this.maxHealth = 9999
    this.health = this.maxHealth
    this.attack = 500
    this.defense = 100
    this.gold = 99_999
    this.luck = 100
end

function reset_player(this::User)
    this.maxHealth = 40
    this.health = this.maxHealth

    this.maxShield = 999
    this.shield = 0

    this.attack = 0
    this.defense = 1
    this.speed = 1
    
    this.gold = 100
    
    this.luck = 0

    this.weaken = 0
    this.burn = 0
    this.freeze = 0
    this.poison = 0
    this.vulnerable = 0
    this.shock = 0
    this.dodge_chance = 0
    this.reflect_chance = 0
    
    this.inventory = []
    this.potions = []
    this.treasures = []
    this.stake_applied = false
    this.ancient_shield_used = false
    load_default_pieces(this)
end

function load_default_pieces(this::User)
    this.pieces = [
        get_piece_by_key(this, SWORD),
        get_piece_by_key(this, SHIELD),
        get_piece_by_key(this, POTION),
        get_piece_by_key(this, DODGE),
        get_piece_by_key(this, CRIMSON_BLADE),
        get_piece_by_key(this, GEM_GREEN)
    ]
end

function _parse_starting_piece_weights(char)::Vector{Union{Nothing, Float64}}
    raw = if hasproperty(char, :starting_pieces_weights) && char.starting_pieces_weights !== nothing
        string(char.starting_pieces_weights)
    else
        ""
    end
    weights = Vector{Union{Nothing, Float64}}()
    isempty(raw) && return weights
    for part in split(raw, ",")
        s = strip(part)
        if s == ""
            push!(weights, nothing)
            continue
        end
        push!(weights, tryparse(Float64, s))
    end
    return weights
end

function load_default_pieces_from_character(this::User, character_key::String)
    characters_data = Globals.get_characters_data()
    if !haskey(characters_data, character_key)
        return []
    end

    char = characters_data[character_key]
    piece_keys = [replace(strip(key), "PIECE_" => "") for key in split(string(char.starting_pieces), ",") if strip(key) != ""]
    weights = _parse_starting_piece_weights(char)
    if !isempty(weights) && length(weights) != length(piece_keys)
        @warn "starting_pieces_weights length $(length(weights)) != starting_pieces length $(length(piece_keys)) for $character_key"
    end

    pieces = []
    for (i, key) in enumerate(piece_keys)
        piece = get_piece_by_key(this, key)
        piece === nothing && continue
        if i <= length(weights) && weights[i] !== nothing
            piece = with_weight(piece, weights[i])
        end
        push!(pieces, piece)
    end
    return pieces
end

function get_piece_by_key(this::User, key::String)
    return this.pieceCollection["PIECE_$(uppercase(key))"]
end

"""
Rebuild an immutable piece struct with a new weight (its board weight).
Accepts a number or numeric string so old saves (`"0.75"`) still load.
"""
function _coerce_weight(new_weight, fallback::Float64 = 0.5)::Float64
    if new_weight === nothing
        return fallback
    elseif new_weight isa Number
        return Float64(new_weight)
    end
    n = tryparse(Float64, strip(string(new_weight)))
    return n === nothing ? fallback : n
end

function _fit_struct_number(piece, field::Symbol, value)
    T = fieldtype(typeof(piece), field)
    if T <: Integer
        return T(max(1, round(Int, Float64(value))))
    elseif T <: AbstractFloat
        return T(Float64(value))
    end
    return value
end

function with_weight(piece, new_weight)
    if piece === nothing
        return nothing
    end
    weight_val = _coerce_weight(new_weight, Float64(getfield(piece, :weight)))
    weight_val = _fit_struct_number(piece, :weight, weight_val)
    field_names = fieldnames(typeof(piece))
    field_values = [name == :weight ? weight_val : getfield(piece, name) for name in field_names]
    return typeof(piece)(field_values...)
end

"""Reward grants still call this. Board drop rate lives on `weight`."""
function with_rarity(piece, new_rarity)
    return with_weight(piece, new_rarity)
end

"""
Share of the board queue a piece occupies, as a 0-1 fraction of the owned pool.
Matches the "Weight: x%" tooltips.
"""
function piece_board_share(piece, pieces)::Float64
    if piece === nothing || pieces === nothing || isempty(pieces)
        return 0.0
    end
    total = 0.0
    for p in pieces
        p === nothing && continue
        total += Float64(p.weight)
    end
    total <= 0.0 && return 0.0
    return Float64(piece.weight) / total
end

"""
Weight value that makes a piece occupy `share` of the pool, where `others_total`
is the summed weight of every other owned piece. Inverse of `piece_board_share`.
"""
function rarity_for_share(share::Float64, others_total::Float64)::Float64
    s = clamp(share, 0.01, 0.95)
    others_total <= 0.0 && return 1.0
    return s * others_total / (1.0 - s)
end

# Shop (and other non-reward) adds: join the pool at this board share, not the CSV rarity.
const NEW_PIECE_ENTRY_SHARE = 0.10

function owned_weight_total(pieces)::Float64
    total = 0.0
    pieces === nothing && return total
    for p in pieces
        p === nothing && continue
        total += Float64(p.weight)
    end
    return total
end

function weight_for_new_piece(owned, share::Float64 = NEW_PIECE_ENTRY_SHARE)::Float64
    return rarity_for_share(share, owned_weight_total(owned))
end

function with_new_piece_weight(piece, owned, share::Float64 = NEW_PIECE_ENTRY_SHARE)
    return with_weight(piece, weight_for_new_piece(owned, share))
end

function is_gem_piece(piece)::Bool
    if piece === nothing || !hasproperty(piece, :key)
        return false
    end
    return occursin("GEM", uppercase(string(piece.key)))
end

function piece_quality_score(piece)
    avg_price = hasproperty(piece, :average_price) ? Float64(getproperty(piece, :average_price)) : 0.0
    rarity = hasproperty(piece, :rarity) ? Float64(getproperty(piece, :rarity)) : 0.0
    # Price is primary; rarity is tie-breaker.
    return (avg_price, rarity)
end

"""
Where `piece` lands in `pieces` under the one-gem limit: `:append`, the index of the
owned gem it replaces, or `:ignored` when the owned gem is at least as good.
"""
function gem_limit_slot(pieces, piece)
    is_gem_piece(piece) || return :append
    existing_gem_idx = findfirst(is_gem_piece, pieces)
    existing_gem_idx === nothing && return :append
    return piece_quality_score(piece) > piece_quality_score(pieces[existing_gem_idx]) ? existing_gem_idx : :ignored
end

"""
Add a piece to the player inventory while enforcing a one-gem limit.
Returns true if the piece was added/replaced, false if ignored.
"""
function add_piece_with_gem_limit!(this::User, piece)::Bool
    if piece === nothing
        return false
    end

    slot = gem_limit_slot(this.pieces, piece)
    slot === :ignored && return false
    if slot === :append
        push!(this.pieces, piece)
    else
        this.pieces[slot] = piece
    end
    return true
end

function has_treasure(treasure_key::String)
    for treasure in Globals.get_data_manager().user_data.treasures
        if treasure.key == treasure_key
            Globals.ObserverModule.notify(Globals.get_observer_data(), :used_treasure, treasure)
            return true
        end
    end

    return false
end

"""
Apply damage from non-combat sources (map events, etc.). Health cannot go below 1.
"""
function apply_out_of_combat_damage!(user::User, amount)
    amt = max(0, Int(amount))
    user.health = max(1, user.health - amt)
    user.health = min(user.health, user.maxHealth)
    return nothing
end

"""
After max/current health changes out of battle, keep the player at 1+ HP and within max.
"""
function ensure_out_of_combat_survival!(user::User)
    if user.maxHealth < 1
        user.maxHealth = 1
    end
    if user.health < 1
        user.health = 1
    end
    user.health = min(user.health, user.maxHealth)
    return nothing
end

function add_potion!(this::User, potion::String = "RANDOM", number::Int = 1)
    if length(this.potions) >= this.max_potions || number <= 0
        return
    end
    if potion == "RANDOM"
        potions = filter(Globals.item_available_in_game, collect(values(Globals.get_data_manager().potion_data)))
        if length(potions) > 0
            num_potions = min(number, length(potions))
            # Shuffle and take first N to avoid duplicates
            shuffled = Random.shuffle(potions)
            for i in 1:num_potions
                potion = shuffled[i]
                if length(this.potions) < this.max_potions
                    push!(this.potions, potion)
                end
            end
        end
        return
    end
    potion_to_add = Globals.get_data_manager().potion_data[potion]
    push!(this.potions, potion_to_add)
end
end