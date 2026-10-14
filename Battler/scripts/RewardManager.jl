module RewardManagerModule
using JulGame
using JulGame.SceneManagement.SceneBuilderModule
using JulGame.EffectsModule
include("localization/battle_strings.jl")
using .BattleStringsModule
include("utils/Easings.jl")
include("utils/DisplayText.jl")
using .DisplayTextModule
include("utils/WeightPreviewPanel.jl")
using .WeightPreviewPanelModule
include("rewards/RewardPackages.jl")
include("rewards/RewardChoiceLines.jl")
using Random
using ..Scripts

const REWARD_SLOT_LABEL_EFFECTS = [
    RoughEdgeEffect(amount=3, seed=123, erosion=true),
    DropShadowEffect(distance=20.0, angle=80.0, blur_radius=6, color=(0,0,0,20), opacity=20)
]
const REWARD_SLOT_TEXT_EFFECTS = [
    RoughEdgeEffect(amount=3, seed=123, erosion=true),
    DropShadowEffect(distance=20.0, angle=80.0, blur_radius=6, color=(0,0,0,20), opacity=20),
    OuterGlowEffect(radius=4, color=(50,49,70,255), blur=0.7, force_white=true)
]
const HEART_IMAGE_PATH = "ui-healthheart"
const HEART_IMAGE_SIZE = Math.Vector2(125, 125)
const HEART_IMAGE_OFFSET_X = 50.0
const HEART_IMAGE_EFFECTS = [
    RoughEdgeEffect(amount=2, seed=42, erosion=true),
    DropShadowEffect(distance=6.0, angle=90.0, blur_radius=4, color=(0, 0, 0, 255), opacity=160),
]
const HOVER_SHAKE_DURATION = 0.18
const HOVER_SHAKE_AMOUNT = 8.0

#region Layout and choreography constants

const GOLD_SLOT_Y = 275.0            # 25px above the old single-column rest position 
const OPTION_START_Y = 520.0
const OPTION_SPACING = 160.0
const OFFSCREEN_Y = 1280.0           # below the 1080 screen edge
const TREE_GUTTER = 80.0             # gap between the spine and an option's left edge
const TITLE_ABOVE_SLOT = 60.0        # "Choose wisely" sits just above the first option

# Absolute times from the start of the entry sequence.
const T_GOLD = 0.0
const T_TITLE = 0.25
const T_SPINE = 0.40
const T_BRANCH = 0.48
const T_OPTIONS = 0.55
const T_FLARE = 0.95

const SLIDE_DURATION = 0.5
const TITLE_DURATION = 0.35
const SPINE_DURATION = 0.2
const BRANCH_DURATION = 0.12
const BRANCH_STAGGER = 0.08
const OPTION_STAGGER = 0.1

const HOVER_SCALE = 1.06
const HOVER_BLEND = 0.12
const DIM_ALPHA = 0.45

const COMMIT_DURATION = 0.3
const COMMIT_POP = 1.12
const RETRACT_DURATION = 0.25
const NUMBER_TWEEN_DURATION = 0.4
const EXIT_DURATION = 0.25
const EXIT_STAGGER = 0.04

const MYSTERY_FAST_INTERVAL = 0.08
const MYSTERY_SLOW_INTERVAL = 0.4
const MYSTERY_ROLL_DURATION = 0.9
const MYSTERY_HOLD_DURATION = 0.5

#endregion

# Isolated from piecePlacementRNG / global Random. Same node always yields the same rewards.
function _reward_rng(psm)::Random.Xoshiro
    psm === nothing && return Random.Xoshiro(0x1)
    h = UInt64(hash((Int(psm.seed), Int(psm.currentFloor), Int(psm.currentLevel), 0x52455744)))
    return Random.Xoshiro(h == 0 ? 0x1 : h)
end

mutable struct RewardManager <: Script
    parent

    # Offer
    state::Symbol                    # :empty, :rolled, :entering, :idle, :committing, :resolved
    goldReward                       # Dict, always offered, never forced
    goldClaimed::Bool
    choices::Vector{Any}             # RewardPackagesModule.ResolvedSlot
    packageId::String
    packageTier::Symbol
    chosenIndex::Int                 # 0 while nothing has been taken
    inputBlocked::Bool               # skip-confirm modal is up; slots stay inert

    user
    persistentStateManager
    rewardsDisplayed::Bool

    # UI
    goldSlot                         # slot data Dict for the dollars offer
    rewardSlots::Vector{Any}         # slot data Dicts for the three options
    titleElement

    # Choreography
    sequenceTime::Float64
    commitTime::Float64
    exitTime::Float64
    flarePlayed::Bool
    landedSlots::Set{Int}
    hoverIndex::Int
    slotScales::Dict{Int, Float64}
    slotAlphas::Dict{Int, Float64}
    branchProgress::Vector{Float64}
    numberProgress::Dict{Int, Float64}
    pendingTextEffects::Vector{Any}

    # Mystery slot
    mysteryCycleIndex::Int
    mysteryCycleTimer::Float64
    mysteryRollTime::Float64
    mysteryRolling::Bool
    mysteryLanded::Bool
    mysteryHoldTime::Float64
    hoverSfxIndex::Int

    # UI element references (prefab elements)
    rewardBorderPrefab  # The Reward_Border UIImage
    rewardSlotPrefab  # The Reward_Slot UIImage
    rewardSlotLabelPrefab  # The Reward_Slot_Label TextBox
    rewardSlotImagePrefab  # The Reward_Slot_Image UIImage
    rewardSlotTextPrefab  # The Reward_Slot_Text TextBox
    weightPreview         # WeightPreviewPanel, reused for any share-changing hover
    weightPreviewPinned::Bool  # stays up after a mystery weight lands
    weightPreviewHold::Float64
    exitQueued::Bool

    function RewardManager()
        this = new()
        this.state = :empty
        this.goldReward = nothing
        this.goldClaimed = false
        this.choices = []
        this.packageId = ""
        this.packageTier = :common
        this.chosenIndex = 0
        this.inputBlocked = false
        this.rewardsDisplayed = false
        this.goldSlot = nothing
        this.rewardSlots = []
        this.titleElement = nothing
        this.sequenceTime = 0.0
        this.commitTime = 0.0
        this.exitTime = -1.0
        this.flarePlayed = false
        this.landedSlots = Set{Int}()
        this.hoverIndex = 0
        this.slotScales = Dict{Int, Float64}()
        this.slotAlphas = Dict{Int, Float64}()
        this.branchProgress = Float64[]
        this.numberProgress = Dict{Int, Float64}()
        this.pendingTextEffects = []
        this.mysteryCycleIndex = 1
        this.mysteryCycleTimer = 0.0
        this.mysteryRollTime = 0.0
        this.mysteryRolling = false
        this.mysteryLanded = false
        this.mysteryHoldTime = 0.0
        this.hoverSfxIndex = 0
        this.weightPreview = WeightPreviewPanelModule.WeightPreviewPanel("reward_weight_preview")
        this.weightPreviewPinned = false
        this.weightPreviewHold = 0.0
        this.exitQueued = false
        return this
    end
end

#region Context helpers

function _event_category(this::RewardManager)::String
    psm = this.persistentStateManager
    psm === nothing && return ""
    ev = psm.currentEvent
    (ev !== nothing && hasproperty(ev, :category)) || return ""
    return string(ev.category)
end

function _current_floor(this::RewardManager)::Int
    psm = this.persistentStateManager
    return psm === nothing ? 1 : max(1, Int(psm.currentFloor))
end

function _game_tooltip_manager(this::RewardManager)
    try
        return this.parent.scripts[1].tooltipManager
    catch
        return nothing
    end
end

const REWARD_TOOLTIP_FONT_SIZE = 22
const REWARD_TOOLTIP_MAX_WIDTH = 380
const DEFAULT_BATTLE_TOOLTIP_FONT_SIZE = 16
const DEFAULT_BATTLE_TOOLTIP_MAX_WIDTH = 300

function _set_reward_tooltip_style!(this::RewardManager; active::Bool)
    tm = _game_tooltip_manager(this)
    tm === nothing && return
    Scripts.TooltipManagerModule.set_tooltip_style(
        tm;
        fontSize = active ? REWARD_TOOLTIP_FONT_SIZE : DEFAULT_BATTLE_TOOLTIP_FONT_SIZE,
        maxWidth = active ? REWARD_TOOLTIP_MAX_WIDTH : DEFAULT_BATTLE_TOOLTIP_MAX_WIDTH,
    )
end

function _is_weight_down(resolved)::Bool
    return resolved.new_share + 0.001 < resolved.old_share
end

function _play_sfx(name::String)
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", name),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "reward sfx ($(name)): $e"
    end
end

function play_gold_reward_sfx(amount)
    n = Int(amount)
    name = if n <= 10
        "getmoneyalittle"
    elseif n <= 20
        "getmoneyagoodbit"
    elseif n <= 30
        "getmoneyalot"
    else
        "getmoneyamillion"
    end
    _play_sfx(name)
end

#endregion

function JulGame.initialize(this::RewardManager)
    globals = JulGame.UserGlobals["Module"]
    this.user = globals.get_user_data()
    this.persistentStateManager = globals.get_data_manager().persistent_state_manager

    # Get prefab UI elements
    this.rewardBorderPrefab = JulGame.SceneModule.get_ui_element_by_id("68d2f0d5-e82f-495c-9578-cf1967f580c6")
    this.rewardSlotPrefab = JulGame.SceneModule.get_ui_element_by_id("956ef760-de09-4ec1-af40-22a6e4e4b6c9")
    this.rewardSlotLabelPrefab = JulGame.SceneModule.get_ui_element_by_id("410d2b73-5d8f-4427-864c-c3066f3aa294")
    this.rewardSlotImagePrefab = JulGame.SceneModule.get_ui_element_by_id("4e67ac7c-22e2-4eb3-b6cd-cd1261088c22")
    this.rewardSlotTextPrefab = JulGame.SceneModule.get_ui_element_by_id("1c1c452e-0de3-4560-b2c5-3dbac0b7b23d")

    # Hide prefab elements initially
    if this.rewardBorderPrefab !== nothing
        this.rewardBorderPrefab.isActive = false
    end
    if this.rewardSlotPrefab !== nothing
        this.rewardSlotPrefab.isActive = false
    end
    if this.rewardSlotLabelPrefab !== nothing
        this.rewardSlotLabelPrefab.isActive = false
    end
    if this.rewardSlotImagePrefab !== nothing
        this.rewardSlotImagePrefab.isActive = false
    end
    if this.rewardSlotTextPrefab !== nothing
        this.rewardSlotTextPrefab.isActive = false
    end

    roll_rewards!(this)
    prewarm_reward_text_effects!(this)
end

#region Rolling

"""
Roll the guaranteed dollars plus one three-option package for this node.
Deterministic per map node; bosses and elites shift the rarity curve upward.
"""
function roll_rewards!(this::RewardManager, gold_reward::Int = 0)
    reset_rewards(this)

    rng = _reward_rng(this.persistentStateManager)
    floor = _current_floor(this)
    category = _event_category(this)

    this.goldReward = generate_gold_reward(floor, rng, gold_reward)

    package, resolved = RewardPackagesModule.roll_package(rng, floor, category)
    if package !== nothing
        this.packageId = package.id
        this.packageTier = package.tier
        this.choices = collect(Any, resolved)
    end

    this.branchProgress = zeros(Float64, length(this.choices))
    this.state = :rolled
    _restore_claim_state!(this)

    @debug "Rolled reward package $(this.packageId) [$(this.packageTier)] with $(length(this.choices)) options"
    _recorder().record!("reward_offered"; package = string(this.packageId), tier = string(this.packageTier),
        gold = this.goldReward === nothing ? 0 : this.goldReward["amount"],
        options = [_reward_summary(c) for c in this.choices])
    return this.choices
end

_recorder() = JulGame.UserGlobals["Module"].RunRecorderModule

function _reward_summary(resolved)
    key = if resolved.item !== nothing
        string(resolved.item.key)
    elseif resolved.piece !== nothing
        string(hasproperty(resolved.piece, :key) ? resolved.piece.key : resolved.piece)
    else
        ""
    end
    return Dict{String, Any}("kind" => string(resolved.kind), "effect" => string(resolved.effect),
        "key" => key, "amount" => resolved.amount)
end

function generate_gold_reward(floor::Int, rng::AbstractRNG, extra_gold::Int = 0)
    base_gold_amounts = [
        (amount=5, weight=40.0),
        (amount=10, weight=30.0),
        (amount=15, weight=20.0),
        (amount=25, weight=8.0),
        (amount=50, weight=2.0)
    ]

    total_weight = sum(item.weight for item in base_gold_amounts)
    roll = rand(rng) * total_weight
    acc = 0.0
    selected_base = 5

    for item in base_gold_amounts
        acc += item.weight
        if roll <= acc
            selected_base = item.amount
            break
        end
    end

    scaled_amount = round(Int, selected_base * max(1, floor))

    return Dict(
        "type" => "gold",
        "amount" => scaled_amount + extra_gold,
        "name" => "Dollars",
        "description" => "Gain $(scaled_amount) dollars"
    )
end

#endregion

#region Persistence of claims

# Claims are spent per node: reloading mid-screen must not hand them out twice.
function _claim_state_key(this::RewardManager)::String
    psm = this.persistentStateManager
    psm === nothing && return "reward_claim"
    return "reward_claim_$(psm.currentFloor)_$(psm.currentLevel)"
end

function _persist_claim_state!(this::RewardManager)
    psm = this.persistentStateManager
    psm === nothing && return
    psm.playerData[_claim_state_key(this)] = Dict{String, Any}(
        "gold" => this.goldClaimed,
        "chosen" => this.chosenIndex,
    )
end

function _restore_claim_state!(this::RewardManager)
    psm = this.persistentStateManager
    psm === nothing && return
    saved = get(psm.playerData, _claim_state_key(this), nothing)
    saved isa AbstractDict || return
    this.goldClaimed = Bool(get(saved, "gold", false))
    this.chosenIndex = Int(get(saved, "chosen", 0))
    if this.chosenIndex > 0
        this.state = :resolved
        # A mystery option that was already taken has nothing left to hide.
        if this.chosenIndex <= length(this.choices)
            this.choices[this.chosenIndex].hidden = false
        end
    end
end

#endregion

#region Display data

"""
True when dollars or a package choice is still unclaimed. False once the offer
is leaving, so Skip does not linger through the exit.
"""
function has_offer(this::RewardManager)::Bool
    this.exitTime >= 0.0 && return false
    return !this.goldClaimed || (this.chosenIndex == 0 && !isempty(this.choices))
end

"""
Whether the reward cluster should still be drawn. Nothing is ever forfeited by
dismissing it: claims are applied the moment they are clicked.
"""
function is_showing(this::RewardManager)::Bool
    (this.goldReward !== nothing || !isempty(this.choices)) || return false
    this.weightPreviewHold > 0.0 && return true
    this.exitQueued && return true
    this.exitTime < 0.0 && return true
    return this.exitTime < _exit_total(this)
end

function _exit_total(this::RewardManager)::Float64
    return EXIT_DURATION + EXIT_STAGGER * (length(this.choices) + 1)
end

"""
Send the offer away. Used by Continue when a post-run screen is queued behind it.
"""
function dismiss!(this::RewardManager)
    begin_exit!(this)
end

function _share_text(share::Float64)::String
    return string(round(share * 100.0, digits = 2), "%")
end

function _slot_body_text(info)::String
    info.subtitle != "" && return info.subtitle
    return info.text
end

function _asset_path_for(key::String)
    globals = JulGame.UserGlobals["Module"]
    parts = split(lowercase(key), "_")
    length(parts) < 2 && return ""
    return globals.get_asset_path(String(parts[1]), String(parts[2]))
end

"""
Everything the UI needs for one option: type label, icon, headline text and the
weight line underneath. Mystery slots stay masked until they are committed.
"""
function get_slot_display_info(this::RewardManager, resolved, index::Int)
    strings = BattleStringsModule.BATTLE_STRINGS
    default_size = Math.Vector2(0, 0)

    if resolved.kind == :mystery_weight && resolved.hidden
        piece = _mystery_display_piece(this)
        image_path = piece === nothing ? "" : _asset_path_for(string(piece.key))
        return (
            name = strings[:battle_reward_label_mystery],
            image_path = image_path,
            label = strings[:battle_reward_label_piece],
            text = _is_weight_down(resolved) ? strings[:battle_reward_weight_unknown_down] : strings[:battle_reward_weight_unknown_up],
            subtitle = "",
            image_size = Math.Vector2(201, 201),
            weight_icon = _is_weight_down(resolved) ? "arrowdebuff" : "arrowbuff",
        )
    end

    if resolved.kind == :owned_weight || resolved.kind == :mystery_weight || resolved.kind == :new_piece
        piece = resolved.piece
        piece === nothing && return (name = "", image_path = "", label = "", text = "", subtitle = "", image_size = default_size)
        # Preview the destination immediately. Only count up after this slot is claimed.
        shown = this.chosenIndex == index ? get(this.numberProgress, index, 0.0) : 1.0
        current = resolved.old_share + (resolved.new_share - resolved.old_share) * clamp(shown, 0.0, 1.0)
        is_weight = resolved.kind == :owned_weight || resolved.kind == :mystery_weight
        return (
            name = string(piece.name),
            image_path = _asset_path_for(string(piece.key)),
            label = strings[:battle_reward_label_piece],
            text = BattleStringsModule.format_string(
                :battle_reward_weight_change;
                old = _share_text(resolved.old_share),
                new = _share_text(current),
            ),
            subtitle = "",
            image_size = Math.Vector2(201, 201),
            weight_icon = is_weight ? (_is_weight_down(resolved) ? "arrowdebuff" : "arrowbuff") : "",
        )

    elseif resolved.kind == :treasure
        treasure = resolved.item
        return (
            name = string(treasure.name),
            image_path = _asset_path_for(string(treasure.key)),
            label = strings[:battle_reward_label_treasure],
            text = string(treasure.name),
            subtitle = "",
            image_size = Math.Vector2(174, 174),
        )

    elseif resolved.kind == :potion
        potion = resolved.item
        return (
            name = string(potion.name),
            image_path = _asset_path_for(string(potion.key)),
            label = strings[:battle_reward_label_potion],
            text = string(potion.name),
            subtitle = "",
            image_size = Math.Vector2(200, 200),
        )

    elseif resolved.effect == :max_hp
        return (
            name = strings[:battle_reward_label_max_health],
            image_path = JulGame.UserGlobals["Module"].get_asset_path(HEART_IMAGE_PATH),
            label = strings[:battle_reward_label_max_health],
            text = BattleStringsModule.format_string(:battle_reward_max_health_amount; amount = resolved.amount),
            subtitle = "",
            image_size = HEART_IMAGE_SIZE,
        )

    elseif resolved.effect == :heal_full
        return (
            name = strings[:battle_reward_heal_full],
            image_path = JulGame.UserGlobals["Module"].get_asset_path(HEART_IMAGE_PATH),
            label = strings[:battle_reward_label_health],
            text = strings[:battle_reward_heal_full],
            subtitle = "",
            image_size = HEART_IMAGE_SIZE,
        )

    elseif resolved.effect == :heal
        return (
            name = strings[:battle_reward_label_health],
            image_path = JulGame.UserGlobals["Module"].get_asset_path(HEART_IMAGE_PATH),
            label = strings[:battle_reward_label_health],
            text = BattleStringsModule.format_string(:battle_reward_heal_amount; amount = resolved.amount),
            subtitle = "",
            image_size = HEART_IMAGE_SIZE,
        )
    end

    return (
        name = strings[:battle_reward_label_dollars],
        image_path = JulGame.UserGlobals["Module"].get_asset_path("ui", "darkdollars"),
        label = strings[:battle_reward_label_dollars],
        text = "x$(resolved.amount)",
        subtitle = "",
        image_size = Math.Vector2(251, 161),
    )
end

function get_gold_display_info(this::RewardManager)
    strings = BattleStringsModule.BATTLE_STRINGS
    amount = this.goldReward === nothing ? 0 : this.goldReward["amount"]
    return (
        name = strings[:battle_reward_label_dollars],
        image_path = JulGame.UserGlobals["Module"].get_asset_path("ui", "darkdollars"),
        label = strings[:battle_reward_label_dollars],
        text = "x$(amount)",
        subtitle = "",
        image_size = Math.Vector2(251, 161),
    )
end

"""
Tooltip body for an option (name, description, stats where applicable).
"""
function get_slot_tooltip_text(this::RewardManager, resolved)
    strings = BattleStringsModule.BATTLE_STRINGS
    if resolved.kind == :mystery_weight && resolved.hidden
        if _is_weight_down(resolved)
            return string(strings[:battle_reward_mystery_down_title], "\n", strings[:battle_reward_mystery_down_body])
        end
        return string(strings[:battle_reward_mystery_up_title], "\n", strings[:battle_reward_mystery_up_body])
    end
    if resolved.piece !== nothing
        user_pieces = this.user.pieces === nothing ? Any[] : collect(Any, this.user.pieces)
        pool = isempty(user_pieces) ? Any[resolved.piece] : vcat(user_pieces, Any[resolved.piece])
        share = if resolved.kind == :new_piece || resolved.kind == :owned_weight || resolved.kind == :mystery_weight
            resolved.new_share
        else
            nothing
        end
        weight_percent = share === nothing ? nothing : round(share * 100.0, digits = 2)
        body = Scripts.CurrentRunStatusModule.get_piece_tooltip_text(resolved.piece, pool; weight_percent = weight_percent)
        if resolved.kind == :owned_weight || resolved.kind == :mystery_weight
            note = _is_weight_down(resolved) ? strings[:battle_reward_weight_down_note] : strings[:battle_reward_weight_up_note]
            return string(body, "\n", note)
        end
        return body
    elseif resolved.kind == :treasure && resolved.item !== nothing
        return Scripts.CurrentRunStatusModule.get_treasure_tooltip_text(resolved.item)
    elseif resolved.kind == :potion && resolved.item !== nothing
        return Scripts.CurrentRunStatusModule.get_potion_tooltip_text(resolved.item)
    end
    info = get_slot_display_info(this, resolved, 0)
    return string(info.label, "\n", info.text)
end

#endregion

#region Text effect prewarm

function _prewarm_job_from_prefab(prefab, text::String, effects)
    prefab === nothing && return nothing
    return JulGame.UI.TextBoxModule.TextEffectPrewarmJob(
        text,
        String(prefab.fontPath),
        Int(prefab.fontSize),
        prefab.color,
        Int(prefab.maxLineWidth),
        prefab.wrapWords,
        Any[e for e in effects],
    )
end

function prewarm_reward_text_effects!(this::RewardManager)
    jobs = JulGame.UI.TextBoxModule.TextEffectPrewarmJob[]

    infos = Any[]
    this.goldReward !== nothing && push!(infos, get_gold_display_info(this))
    for (index, resolved) in enumerate(this.choices)
        push!(infos, get_slot_display_info(this, resolved, index))
    end

    for info in infos
        if info.label != ""
            job = _prewarm_job_from_prefab(this.rewardSlotLabelPrefab, String(info.label), REWARD_SLOT_LABEL_EFFECTS)
            job !== nothing && push!(jobs, job)
        end
        body = _slot_body_text(info)
        if body != ""
            job = _prewarm_job_from_prefab(this.rewardSlotTextPrefab, String(body), REWARD_SLOT_TEXT_EFFECTS)
            job !== nothing && push!(jobs, job)
        end
    end

    isempty(jobs) && return
    if Threads.nthreads() <= 1
        @debug "[reward-timing] skipped text prewarm (start Julia with -t auto or -t 2; nthreads=1)"
        return
    end
    JulGame.UI.TextBoxModule.prewarm_text_effect_textures!(jobs)
    @debug "[reward-timing] queued $(length(jobs)) reward text prewarm jobs (isolated rng, worker thread, nthreads=$(Threads.nthreads()))"
end

function _apply_or_defer_effects!(this::RewardManager, textbox, effects)
    if JulGame.UI.TextBoxModule.try_apply_effects_from_cache!(textbox, effects)
        return
    end
    push!(this.pendingTextEffects, (textbox, effects))
end

function _flush_pending_text_effects!(this::RewardManager)
    isempty(this.pendingTextEffects) && return
    JulGame.UI.TextBoxModule.pump_text_effect_prewarm!()
    still = []
    for (textbox, effects) in this.pendingTextEffects
        if JulGame.UI.TextBoxModule.try_apply_effects_from_cache!(textbox, effects)
            continue
        end
        # Cache miss (nthreads=1, or text that wasn't prewarmed): bake live so
        # a slot never shows as plain text.
        try
            JulGame.apply_effects!(textbox, effects)
        catch
            push!(still, (textbox, effects))
        end
    end
    this.pendingTextEffects = still
end

#endregion

#region Slot construction

function _slot_base_x(this::RewardManager)::Float64
    return this.rewardSlotPrefab === nothing ? 0.0 : Float64(this.rewardSlotPrefab.position.x)
end

function _slot_size(this::RewardManager)
    this.rewardSlotPrefab === nothing && return Math.Vector2(600, 140)
    return this.rewardSlotPrefab.size
end

function _option_target_y(index::Int)::Float64
    return OPTION_START_Y + (index - 1) * OPTION_SPACING
end

"""
Build one slot (frame, label, icon, headline). `on_click` is nothing for slots
that are already spent, which leaves them visible but inert.
"""
function _create_slot_ui(this::RewardManager, info, index::Int, target_y::Float64,
                         frame_path::String, frame_tint::NTuple{4, Int}, on_click, tooltip_text::String)
    slot = JulGame.UI.duplicate(this.rewardSlotPrefab)
    slot.name = "Reward_Slot_$(index)"
    if frame_path != ""
        slot.path = frame_path
    end
    slot.anchor.current_state = :none
    slot.position = Math.Vector2(_slot_base_x(this), OFFSCREEN_Y)
    slot.layer = 11  # Above dimming layer (10)
    slot.color = frame_tint
    slot.isActive = true
    # Duplicate copies the prefab's event arrays by reference. A fresh list per
    # slot keeps hover/click from firing every handler at once.
    slot.clickEvents = Function[]
    if hasproperty(slot, :hoverEnterEvents)
        slot.hoverEnterEvents = Function[]
    end
    if hasproperty(slot, :hoverExitEvents)
        slot.hoverExitEvents = Function[]
    end
    slot.forceClickCheck = on_click !== nothing

    if on_click !== nothing
        JulGame.UI.add_click_event(slot, on_click)
    end

    tm = _game_tooltip_manager(this)
    if tm !== nothing && tooltip_text != ""
        try
            Scripts.TooltipManagerModule.register_tooltip_item(tm, slot, tooltip_text)
        catch e
            @debug "Could not register reward slot tooltip: $e"
        end
    end

    label = JulGame.UI.duplicate(this.rewardSlotLabelPrefab)
    label.name = "Reward_Slot_Label_$(index)"
    label.text = info.label
    label.layer = 11
    label.parent = slot
    label.isActive = true
    label.ignoreInputEvents = true
    _apply_or_defer_effects!(this, label, REWARD_SLOT_LABEL_EFFECTS)

    image = nothing
    if info.image_path != ""
        image = JulGame.UI.duplicate(this.rewardSlotImagePrefab)
        image.name = "Reward_Slot_Image_$(index)"
        image.path = info.image_path
        # Set size AFTER setting path (to override any auto-set size from loading)
        if info.image_size != Math.Vector2(0, 0)
            image.size = info.image_size
            image.originalSize = info.image_size
        end
        image.layer = 11
        image.parent = slot
        image.isActive = true
        image.ignoreInputEvents = true
        if info.image_path == JulGame.UserGlobals["Module"].get_asset_path(HEART_IMAGE_PATH)
            image.color = (255, 70, 127, 255)
            image.anchorOffset = Math.Vector2(Float64(image.anchorOffset.x) + HEART_IMAGE_OFFSET_X, image.anchorOffset.y)
            try
                JulGame.apply_effects!(image, HEART_IMAGE_EFFECTS)
            catch e
                @debug "heart image effects: $e"
            end
        end
    end

    text = JulGame.UI.duplicate(this.rewardSlotTextPrefab)
    text.name = "Reward_Slot_Text_$(index)"
    body = _slot_body_text(info)
    text.text = body
    text.layer = 11
    text.parent = slot
    text.isActive = body != ""
    text.ignoreInputEvents = true
    weight_icon = hasproperty(info, :weight_icon) ? String(info.weight_icon) : ""
    if body != ""
        _apply_or_defer_effects!(this, text, REWARD_SLOT_TEXT_EFFECTS)
    end

    return Dict(
        "slot" => slot,
        "label" => label,
        "image" => image,
        "text" => text,
        "index" => index,
        "targetY" => target_y,
        "currentY" => OFFSCREEN_Y,
        "animFromY" => OFFSCREEN_Y,
        "animTargetY" => target_y,
        "animTime" => 0.0,
        "leaving" => false,
        "fade" => 0.0,
        "baseSize" => Math.Vector2(slot.size.x, slot.size.y),
        "baseTint" => frame_tint,
        "subtitle" => info.subtitle,
        "imageOffsetX" => image === nothing ? 0.0 : Float64(image.anchorOffset.x),
        "shakeTime" => nothing,
        "weightIcon" => weight_icon,
    )
end

function display_rewards(this::RewardManager)
    if this.rewardsDisplayed
        return
    end

    JulGame.UI.TextBoxModule.pump_text_effect_prewarm!()
    clear_reward_slots(this)

    this.state = :entering
    this.sequenceTime = 0.0
    this.flarePlayed = false
    empty!(this.landedSlots)
    empty!(this.slotScales)
    empty!(this.slotAlphas)
    empty!(this.numberProgress)
    this.branchProgress = zeros(Float64, length(this.choices))
    # Rebuilding a screen where a choice was already made (save/load): the commit
    # beat is over, so start it finished rather than replaying it.
    this.commitTime = this.chosenIndex == 0 ? 0.0 : max(COMMIT_DURATION, RETRACT_DURATION)

    if this.rewardBorderPrefab !== nothing
        this.rewardBorderPrefab.isActive = true
        this.rewardBorderPrefab.layer = 11
    end

    if this.goldReward !== nothing && !this.goldClaimed
        manager = this
        this.goldSlot = _create_slot_ui(
            this,
            get_gold_display_info(this),
            0,
            GOLD_SLOT_Y,
            "",
            (255, 255, 255, 255),
            () -> claim_gold!(manager),
            "",
        )
    end

    frame_path = RewardPackagesModule.frame_for_tier(this.packageTier)
    frame_tint = RewardPackagesModule.frame_tint_for_tier(this.packageTier)
    for (index, resolved) in enumerate(this.choices)
        this.numberProgress[index] = index == this.chosenIndex ? 1.0 : 0.0
        this.slotScales[index] = 1.0
        this.slotAlphas[index] = 1.0
        manager = this
        slot_index = index
        # An option already taken on a previous visit stays visible but inert.
        on_click = this.chosenIndex != 0 ? nothing : () -> choose!(manager, slot_index)
        slot_data = _create_slot_ui(
            this,
            get_slot_display_info(this, resolved, index),
            index,
            _option_target_y(index),
            frame_path,
            frame_tint,
            on_click,
            get_slot_tooltip_text(this, resolved),
        )
        push!(this.rewardSlots, slot_data)
    end

    this.rewardsDisplayed = true
    _set_reward_tooltip_style!(this; active = true)
    @debug "Displayed reward package $(this.packageId) with $(length(this.choices)) options"
end

function clear_reward_slots(this::RewardManager)
    tm = _game_tooltip_manager(this)
    all_slots = Any[]
    this.goldSlot !== nothing && push!(all_slots, this.goldSlot)
    append!(all_slots, this.rewardSlots)

    for slot_data in all_slots
        if tm !== nothing && haskey(slot_data, "slot") && slot_data["slot"] !== nothing
            try
                Scripts.TooltipManagerModule.deregister_tooltip_item(tm, slot_data["slot"])
            catch e
                @debug "Could not deregister reward slot tooltip: $e"
            end
        end
        # Remove UI elements from scene
        for key in ("slot", "label", "image", "text")
            if haskey(slot_data, key) && slot_data[key] !== nothing
                filter!(e -> e.id != slot_data[key].id, MAIN.scene.uiElements)
            end
        end
    end

    empty!(this.rewardSlots)
    empty!(this.pendingTextEffects)
    this.goldSlot = nothing
    WeightPreviewPanelModule.hide!(this.weightPreview)
    this.weightPreviewPinned = false
    this.weightPreviewHold = 0.0
    this.exitQueued = false

    if this.rewardBorderPrefab !== nothing
        this.rewardBorderPrefab.isActive = false
    end
    _set_reward_tooltip_style!(this; active = false)
end

function reset_rewards(this::RewardManager)
    clear_reward_slots(this)
    this.state = :empty
    this.goldReward = nothing
    this.goldClaimed = false
    this.choices = []
    this.packageId = ""
    this.packageTier = :common
    this.chosenIndex = 0
    this.inputBlocked = false
    this.rewardsDisplayed = false
    this.sequenceTime = 0.0
    this.commitTime = 0.0
    this.exitTime = -1.0
    this.flarePlayed = false
    this.hoverIndex = 0
    this.mysteryRolling = false
    this.mysteryLanded = false
    this.mysteryRollTime = 0.0
    this.mysteryHoldTime = 0.0
    empty!(this.landedSlots)
    empty!(this.slotScales)
    empty!(this.slotAlphas)
    empty!(this.numberProgress)
    this.branchProgress = Float64[]
end

#endregion

#region Interaction

function _slot_is_hovered(slot_data)::Bool
    get(slot_data, "leaving", false) && return false
    slot = slot_data["slot"]
    slot === nothing && return false
    return slot.isActive && slot.forceClickCheck && slot.isHovered
end

function _start_hover_shake!(slot_data)
    slot_data === nothing && return
    slot_data["shakeTime"] = 0.0
end

"""
Read hover from the slots themselves. Enter/exit callbacks on duplicated UIImages
share one event list, so the last option always won. Gold is -1, nothing is 0.
"""
function _poll_hover!(this::RewardManager)
    if this.inputBlocked || !(this.state == :entering || this.state == :idle)
        this.hoverIndex = 0
        return
    end

    hovered = 0
    if this.goldSlot !== nothing && _slot_is_hovered(this.goldSlot)
        hovered = -1
    elseif this.chosenIndex == 0
        for slot_data in this.rewardSlots
            _slot_is_hovered(slot_data) || continue
            hovered = slot_data["index"]
            break
        end
    end

    hovered == this.hoverIndex && return
    this.hoverIndex = hovered
    hovered == 0 && return

    _play_hover_sfx!(this, hovered)
    _start_hover_shake!(hovered == -1 ? this.goldSlot : _slot_data_for(this, hovered))
end

function _play_hover_sfx!(this::RewardManager, hovered::Int)
    if hovered == -1
        _play_sfx("getmoneyalittle")
        return
    end
    (hovered >= 1 && hovered <= length(this.choices)) || return
    resolved = this.choices[hovered]

    if resolved.kind == :potion
        this.hoverSfxIndex = this.hoverSfxIndex % 4 + 1
        _play_sfx("potionhover$(this.hoverSfxIndex)")
    elseif resolved.kind == :gold || resolved.effect == :gold
        _play_sfx("getmoneyalittle")
    elseif resolved.effect == :heal || resolved.effect == :heal_full || resolved.effect == :max_hp
        _play_sfx("healsmall")
    elseif resolved.kind == :treasure
        _play_sfx("thud1")
    elseif resolved.piece !== nothing
        key = uppercase(string(resolved.piece.key))
        piece_sfx = if occursin("VAMPIRE", key)
            "piecevampiresword"
        elseif occursin("SWORD", key) || occursin("BLADE", key)
            "piecesword"
        elseif occursin("REFLECTIVE", key)
            "piecereflectiveshield"
        elseif occursin("SHIELD", key)
            "pieceshield"
        elseif occursin("BURN", key) || occursin("FIRE", key)
            "piecefire"
        elseif occursin("FREEZE", key) || occursin("ICE", key)
            "pieceice"
        elseif occursin("POISON", key)
            "piecepoison"
        elseif occursin("SKULL", key)
            "pieceskull"
        elseif occursin("DODGE", key)
            "piecedodge"
        elseif occursin("BLUEGEM", key)
            "piecebluegem"
        elseif occursin("GREENGEM", key)
            "piecegreengem"
        elseif occursin("REDGEM", key)
            "pieceredgem"
        elseif occursin("YELLOWGEM", key)
            "pieceyellowgem"
        elseif occursin("LUCK", key) || occursin("DICE", key) || occursin("WAND", key)
            "pieceluck"
        else
            "thud2"
        end
        _play_sfx(piece_sfx)
    end
end

function _update_image_shake!(slot_data, deltaTime::Float64)
    image = slot_data["image"]
    image === nothing && return
    base_x = get(slot_data, "imageOffsetX", 0.0)
    t = get(slot_data, "shakeTime", nothing)
    if t === nothing
        image.anchorOffset = Math.Vector2(base_x, 0)
        return
    end
    t += deltaTime
    if t >= HOVER_SHAKE_DURATION
        slot_data["shakeTime"] = nothing
        image.anchorOffset = Math.Vector2(base_x, 0)
        return
    end
    slot_data["shakeTime"] = t
    progress = t / HOVER_SHAKE_DURATION
    amount = HOVER_SHAKE_AMOUNT * (1.0 - progress)
    image.anchorOffset = Math.Vector2(base_x + sin(progress * 20.0) * amount, cos(progress * 17.0) * amount)
end

"""
Claim the guaranteed dollars. Independent of the package choice, and never forced.
"""
function claim_gold!(this::RewardManager)
    this.inputBlocked && return
    this.goldClaimed && return
    this.goldReward === nothing && return
    _skip_entry_if_animating(this)

    amount = this.goldReward["amount"]
    this.user.gold += amount
    this.goldClaimed = true
    _recorder().record!("reward_gold"; amount = amount)
    play_gold_reward_sfx(amount)
    _persist_claim_state!(this)

    if this.goldSlot !== nothing
        this.goldSlot["leaving"] = true
        slot = this.goldSlot["slot"]
        if slot !== nothing
            slot.clickEvents = Function[]
            slot.forceClickCheck = false
        end
    end
    _repack_visible_slots!(this)
    @debug "Claimed $(amount) dollars"
end

"""
Take one of the three options. Locks the other two; a second call is ignored.
"""
function choose!(this::RewardManager, index::Int)
    this.inputBlocked && return
    this.chosenIndex == 0 || return
    (index >= 1 && index <= length(this.choices)) || return
    _skip_entry_if_animating(this)

    this.chosenIndex = index
    this.state = :committing
    this.commitTime = 0.0
    this.hoverIndex = 0

    resolved = this.choices[index]
    keep_mystery = resolved.kind == :mystery_weight && resolved.hidden
    for slot_data in this.rewardSlots
        slot = slot_data["slot"]
        if slot !== nothing
            slot.clickEvents = Function[]
            slot.forceClickCheck = false
        end
        keep_mystery && slot_data["index"] == index && continue
        slot_data["leaving"] = true
    end
    _repack_visible_slots!(this)

    if keep_mystery
        # The dice roll resolves the piece on screen before anything is granted.
        this.mysteryRolling = true
        this.mysteryRollTime = 0.0
        this.mysteryLanded = false
        this.mysteryHoldTime = 0.0
        _play_sfx("piecedicerollingloop")
    else
        _dismiss_weight_preview!(this)
        _commit_choice!(this)
    end
end

function _commit_choice!(this::RewardManager)
    index = this.chosenIndex
    (index >= 1 && index <= length(this.choices)) || return
    resolved = this.choices[index]

    granted = RewardPackagesModule.apply_slot!(this.user, resolved)
    if !granted
        # Nothing could be applied (inventory changed since the roll): pay out
        # gold instead so a claimed reward is never silently empty.
        fallback = RewardPackagesModule.gold_slot(
            RewardPackagesModule.build_context(_current_floor(this), this.packageTier),
        )
        RewardPackagesModule.apply_slot!(this.user, fallback)
        this.choices[index] = fallback
        _refresh_slot_text(this, index)
    end

    _recorder().record!("reward_chosen"; index = index, option = _reward_summary(this.choices[index]),
        package = string(this.packageId))
    _play_commit_sfx(this, this.choices[index])
    _persist_claim_state!(this)
    @debug "Chose option $(index) from $(this.packageId)"
end

function _play_commit_sfx(this::RewardManager, resolved)
    if resolved.kind == :treasure
        _play_sfx("activetreasurenail")
    elseif resolved.kind == :potion
        _play_sfx("drink")
    elseif resolved.kind == :new_piece || resolved.kind == :owned_weight || resolved.kind == :mystery_weight
        _play_sfx("buyitem")
    elseif resolved.effect == :heal || resolved.effect == :heal_full
        _play_sfx(resolved.amount >= 12 || resolved.effect == :heal_full ? "healbig" : "healsmall")
    elseif resolved.effect == :max_hp
        _play_sfx("buff")
    else
        play_gold_reward_sfx(resolved.amount)
    end
end

function _skip_entry_if_animating(this::RewardManager)
    this.state == :entering || return
    skip_entry_animation(this)
end

function skip_entry_animation(this::RewardManager)
    this.sequenceTime = max(this.sequenceTime, T_FLARE + 0.35)
    this.state = this.chosenIndex == 0 ? :idle : :resolved
    for slot_data in this.rewardSlots
        push!(this.landedSlots, slot_data["index"])
        slot_data["currentY"] = slot_data["targetY"]
        slot_data["animFromY"] = slot_data["targetY"]
        slot_data["animTargetY"] = slot_data["targetY"]
    end
    if this.goldSlot !== nothing
        this.goldSlot["currentY"] = this.goldSlot["targetY"]
        this.goldSlot["animFromY"] = this.goldSlot["targetY"]
        this.goldSlot["animTargetY"] = this.goldSlot["targetY"]
    end
    for i in eachindex(this.branchProgress)
        this.branchProgress[i] = 1.0
    end
end

"""
Start the exit slide. The screen leaves as one object regardless of what was claimed.
"""
function begin_exit!(this::RewardManager)
    this.exitTime < 0.0 || return
    this.chosenIndex == 0 && _recorder().record!("reward_skipped"; gold_claimed = this.goldClaimed,
        package = string(this.packageId))
    _dismiss_weight_preview!(this)
    this.exitQueued = false
    this.exitTime = 0.0
end

function _begin_slot_slide!(slot_data, new_y::Float64)
    slot_data["targetY"] == new_y && return
    slot_data["animFromY"] = get(slot_data, "currentY", slot_data["targetY"])
    slot_data["animTargetY"] = new_y
    slot_data["animTime"] = 0.0
    slot_data["targetY"] = new_y
end

"""
Pack whatever is still on offer into a single column. Claiming gold slides the
three options up into its place; claiming an option leaves only gold, if unclaimed.
"""
function _repack_visible_slots!(this::RewardManager)
    y = GOLD_SLOT_Y
    if this.goldSlot !== nothing && !get(this.goldSlot, "leaving", false)
        _begin_slot_slide!(this.goldSlot, y)
        y = OPTION_START_Y
    end
    for slot_data in this.rewardSlots
        get(slot_data, "leaving", false) && continue
        _begin_slot_slide!(slot_data, y)
        y += OPTION_SPACING
    end
end

function _slot_current_y(slot_data)::Float64
    return get(slot_data, "currentY", slot_data["targetY"])
end

function _advance_slot_y!(slot_data, entry_progress::Float64, deltaTime::Float64)::Float64
    target_y = slot_data["targetY"]
    if entry_progress < 1.0
        y = OFFSCREEN_Y + (target_y - OFFSCREEN_Y) * ease_out_back(entry_progress)
        slot_data["currentY"] = y
        slot_data["animFromY"] = y
        slot_data["animTargetY"] = target_y
        return y
    end

    anim_target = get(slot_data, "animTargetY", target_y)
    if anim_target != target_y
        slot_data["animFromY"] = get(slot_data, "currentY", target_y)
        slot_data["animTargetY"] = target_y
        slot_data["animTime"] = 0.0
        anim_target = target_y
    end

    anim_from = get(slot_data, "animFromY", target_y)
    if anim_from == anim_target
        slot_data["currentY"] = target_y
        return target_y
    end

    slot_data["animTime"] = get(slot_data, "animTime", 0.0) + deltaTime
    t = clamp(slot_data["animTime"] / SLIDE_DURATION, 0.0, 1.0)
    y = anim_from + (anim_target - anim_from) * ease_out_back(t)
    slot_data["currentY"] = y
    return y
end

function _hide_slot!(slot_data)
    slot = slot_data["slot"]
    slot === nothing && return
    slot.isActive = false
    for key in ("label", "image", "text")
        slot_data[key] !== nothing && (slot_data[key].isActive = false)
    end
end

#endregion

#region Mystery slot

function _owned_pieces(this::RewardManager)
    this.user === nothing && return Any[]
    return Any[p for p in this.user.pieces if p !== nothing]
end

function _mystery_display_piece(this::RewardManager)
    pieces = _owned_pieces(this)
    isempty(pieces) && return nothing
    index = mod1(this.mysteryCycleIndex, length(pieces))
    return pieces[index]
end

function _mystery_interval(this::RewardManager)::Float64
    this.mysteryRolling || return MYSTERY_FAST_INTERVAL
    t = clamp(this.mysteryRollTime / MYSTERY_ROLL_DURATION, 0.0, 1.0)
    # Slow the cycle down rather than stopping it dead.
    return MYSTERY_FAST_INTERVAL + (MYSTERY_SLOW_INTERVAL - MYSTERY_FAST_INTERVAL) * ease_out_quart(t)
end

function _mystery_slot_index(this::RewardManager)::Int
    if this.chosenIndex > 0 && this.chosenIndex <= length(this.choices)
        resolved = this.choices[this.chosenIndex]
        resolved.kind == :mystery_weight && resolved.hidden && return this.chosenIndex
    end
    for (index, resolved) in enumerate(this.choices)
        resolved.kind == :mystery_weight && resolved.hidden && return index
    end
    return 0
end

function _refresh_hidden_mystery_images!(this::RewardManager)
    for (index, resolved) in enumerate(this.choices)
        resolved.kind == :mystery_weight && resolved.hidden && _refresh_slot_image(this, index)
    end
end

function _update_mystery(this::RewardManager, deltaTime::Float64)
    index = _mystery_slot_index(this)
    index == 0 && return

    if this.mysteryLanded
        this.mysteryHoldTime += deltaTime
        this.mysteryHoldTime >= MYSTERY_HOLD_DURATION || return
        resolved = this.choices[index]
        if resolved.hidden
            resolved.hidden = false
            _refresh_slot_text(this, index)
            _dismiss_weight_preview!(this)
            _commit_choice!(this)
            for slot_data in this.rewardSlots
                slot_data["index"] == index || continue
                slot_data["leaving"] = true
            end
            _repack_visible_slots!(this)
        end
        # Hand control back to the normal commit beat, timed from the reveal.
        this.mysteryLanded = false
        this.commitTime = 0.0
        return
    end

    if this.mysteryRolling
        this.mysteryRollTime += deltaTime
        if this.mysteryRollTime >= MYSTERY_ROLL_DURATION
            _land_mystery!(this, index)
            return
        end
    end

    this.mysteryCycleTimer += deltaTime
    if this.mysteryCycleTimer >= _mystery_interval(this)
        this.mysteryCycleTimer = 0.0
        this.mysteryCycleIndex += 1
        _refresh_hidden_mystery_images!(this)
    end
end

function _land_mystery!(this::RewardManager, index::Int)
    resolved = this.choices[index]
    pieces = _owned_pieces(this)
    if resolved.piece !== nothing && !isempty(pieces)
        landed = findfirst(p -> string(p.key) == string(resolved.piece.key), pieces)
        landed !== nothing && (this.mysteryCycleIndex = landed)
    end
    this.mysteryRolling = false
    this.mysteryLanded = true
    this.mysteryHoldTime = 0.0
    _refresh_slot_image(this, index)
    _pin_weight_preview!(this, resolved)
    _play_sfx("piecediceresult$(rand(1:3))")
end

function _refresh_slot_image(this::RewardManager, index::Int)
    slot_data = _slot_data_for(this, index)
    slot_data === nothing && return
    image = slot_data["image"]
    image === nothing && return
    info = get_slot_display_info(this, this.choices[index], index)
    info.image_path == "" && return
    # Assigning `path` reloads the texture, so only touch it on a real change.
    String(image.path) == info.image_path && return
    image.path = info.image_path
    if info.image_size != Math.Vector2(0, 0)
        image.size = info.image_size
        image.originalSize = info.image_size
    end
end

function _refresh_slot_text(this::RewardManager, index::Int)
    slot_data = _slot_data_for(this, index)
    slot_data === nothing && return
    info = get_slot_display_info(this, this.choices[index], index)
    label = slot_data["label"]
    if label !== nothing && String(label.text) != info.label
        label.text = info.label
    end
    text = slot_data["text"]
    if text !== nothing
        body = _slot_body_text(info)
        text.isActive = body != ""
        # Re-rendering a TextBox rebakes its effects; skip when nothing changed.
        if String(text.text) != body
            text.text = body
            body != "" && _apply_or_defer_effects!(this, text, REWARD_SLOT_TEXT_EFFECTS)
        end
    end
    _refresh_slot_image(this, index)
end

function _slot_data_for(this::RewardManager, index::Int)
    for slot_data in this.rewardSlots
        slot_data["index"] == index && return slot_data
    end
    return nothing
end

#endregion

#region Juice

function _tier_flare!(this::RewardManager)
    tier = this.packageTier
    if tier == :unlucky
        # Deliberately silent: the absence of a flare is the tell.
        return
    elseif tier == :rare
        _play_sfx("buff")
    elseif tier == :epic
        _play_sfx("critnoise1")
        _camera_shake(0.18)
    elseif tier == :enchanted
        _play_sfx("pieceluck")
        _camera_shake(0.35)
        _screen_flash((255, 236, 170, 255))
    end
end

# Both respect the accessibility toggles inside BattleJuice.
function _camera_shake(amount::Float64)
    try
        Scripts.BattleManagerModule.BattleJuiceModule.camera_shake!(amount)
    catch e
        @debug "reward camera shake: $e"
    end
end

function _screen_flash(color::NTuple{4, Int})
    try
        Scripts.BattleManagerModule.BattleJuiceModule.screen_flash!(color; intensity = 0.28, duration = 0.4)
    catch e
        @debug "reward screen flash: $e"
    end
end

# Alpha pulse on the frame; strength scales with tier.
function _flare_pulse(this::RewardManager)::Float64
    elapsed = this.sequenceTime - T_FLARE
    (elapsed < 0.0 || elapsed > 0.25) && return 0.0
    strength = if this.packageTier == :unlucky
        0.0
    elseif this.packageTier == :enchanted || this.packageTier == :epic
        0.5
    else
        0.3
    end
    return sin(elapsed / 0.25 * π) * strength
end

function _set_slot_alpha(slot_data, alpha::Float64, tint::NTuple{4, Int})
    a = round(Int, clamp(alpha, 0.0, 1.0) * 255)
    slot = slot_data["slot"]
    if slot !== nothing
        slot.color = (tint[1], tint[2], tint[3], a)
    end
    for key in ("label", "image", "text")
        element = slot_data[key]
        element === nothing && continue
        c = element.color
        element.color = (c[1], c[2], c[3], a)
    end
end

function _apply_slot_scale(this::RewardManager, slot_data, scale::Float64)
    slot = slot_data["slot"]
    slot === nothing && return
    base = slot_data["baseSize"]
    width = base.x * scale
    height = base.y * scale
    slot.size = Math.Vector2(round(Int, width), round(Int, height))
    # Grow around the centre so the slot does not drift as it scales.
    offset_x = (width - base.x) / 2.0
    offset_y = (height - base.y) / 2.0
    slot_data["scaleOffset"] = Math.Vector2(offset_x, offset_y)
end

function _slide_progress(start_time::Float64, now::Float64, duration::Float64)::Float64
    now < start_time && return 0.0
    return clamp((now - start_time) / duration, 0.0, 1.0)
end

#endregion

#region Update

function JulGame.update(this::RewardManager, deltaTime::Float64)
    _flush_pending_text_effects!(this)
    this.rewardsDisplayed || return

    if this.weightPreviewHold > 0.0
        this.weightPreviewHold = max(0.0, this.weightPreviewHold - deltaTime)
        if this.weightPreviewHold <= 0.0 && this.exitQueued
            this.exitQueued = false
            begin_exit!(this)
        end
    end

    if this.state == :entering
        this.sequenceTime += deltaTime
        if !this.flarePlayed && this.sequenceTime >= T_FLARE
            this.flarePlayed = true
            _tier_flare!(this)
        end
        if this.sequenceTime >= T_FLARE + 0.3
            this.state = this.chosenIndex == 0 ? :idle : :resolved
        end
    elseif this.state == :idle
        this.sequenceTime += deltaTime
    elseif this.state == :committing
        this.commitTime += deltaTime
        if this.mysteryRolling || this.mysteryLanded
            _update_mystery(this, deltaTime)
        elseif this.commitTime >= max(COMMIT_DURATION, RETRACT_DURATION)
            this.state = :resolved
        end
    end

    if this.state == :idle || this.state == :entering
        index = _mystery_slot_index(this)
        index != 0 && _update_mystery(this, deltaTime)
    end

    _poll_hover!(this)
    _sync_weight_preview!(this)
    WeightPreviewPanelModule.tick!(this.weightPreview, deltaTime)
    _update_number_tweens(this, deltaTime)
    _update_gold_slot(this, deltaTime)
    _update_option_slots(this, deltaTime)
    _update_exit(this, deltaTime)
end

function _update_number_tweens(this::RewardManager, deltaTime::Float64)
    this.chosenIndex == 0 && return
    index = this.chosenIndex
    haskey(this.numberProgress, index) || return
    current = this.numberProgress[index]
    current >= 1.0 && return
    # Hold the count-up until a mystery slot has revealed which piece it landed on.
    if this.mysteryRolling || this.mysteryLanded
        return
    end
    this.numberProgress[index] = clamp(current + deltaTime / NUMBER_TWEEN_DURATION, 0.0, 1.0)
    _refresh_slot_text(this, index)
end

function _update_gold_slot(this::RewardManager, deltaTime::Float64)
    this.goldSlot === nothing && return
    slot_data = this.goldSlot
    slot = slot_data["slot"]
    slot === nothing && return
    slot.isActive || return

    progress = _slide_progress(T_GOLD, this.sequenceTime, SLIDE_DURATION)
    y = _advance_slot_y!(slot_data, progress, deltaTime)

    target_scale = this.hoverIndex == -1 ? HOVER_SCALE : 1.0
    scale = get(this.slotScales, 0, 1.0)
    scale += (target_scale - scale) * min(1.0, deltaTime / HOVER_BLEND)
    this.slotScales[0] = scale
    _apply_slot_scale(this, slot_data, scale)
    offset = get(slot_data, "scaleOffset", Math.Vector2(0, 0))
    slot.anchor.current_state = :none
    slot.position = Math.Vector2(_slot_base_x(this) - offset.x, y - offset.y + _exit_offset(this, 0))
    _update_image_shake!(slot_data, deltaTime)

    if get(slot_data, "leaving", false)
        slot_data["fade"] = clamp(get(slot_data, "fade", 0.0) + deltaTime / RETRACT_DURATION, 0.0, 1.0)
    end
    alpha = 1.0 - get(slot_data, "fade", 0.0)
    _set_slot_alpha(slot_data, alpha * _exit_alpha(this), slot_data["baseTint"])
    alpha <= 0.01 && get(slot_data, "leaving", false) && _hide_slot!(slot_data)
end

function _update_option_slots(this::RewardManager, deltaTime::Float64)
    isempty(this.rewardSlots) && return
    blend = min(1.0, deltaTime / HOVER_BLEND)
    pulse = _flare_pulse(this)

    for slot_data in this.rewardSlots
        index = slot_data["index"]
        slot = slot_data["slot"]
        slot === nothing && continue
        slot.isActive || continue

        entry_start = T_OPTIONS + (index - 1) * OPTION_STAGGER
        progress = _slide_progress(entry_start, this.sequenceTime, SLIDE_DURATION)
        if progress >= 1.0 && !(index in this.landedSlots)
            push!(this.landedSlots, index)
            _play_sfx("thud$(mod1(index, 3))")
        end

        y = _advance_slot_y!(slot_data, progress, deltaTime)

        # Hover: the focused option grows and holds full alpha, the rest recede.
        hovered = this.hoverIndex == index
        leaving = get(slot_data, "leaving", false)
        chosen = this.chosenIndex == index

        target_scale = if chosen
            commit_t = clamp(this.commitTime / COMMIT_DURATION, 0.0, 1.0)
            1.0 + (COMMIT_POP - 1.0) * (1.0 - ease_out_back(commit_t))
        elseif hovered
            HOVER_SCALE
        else
            1.0
        end

        if leaving
            slot_data["fade"] = clamp(get(slot_data, "fade", 0.0) + deltaTime / RETRACT_DURATION, 0.0, 1.0)
        end
        target_alpha = if leaving
            1.0 - get(slot_data, "fade", 0.0)
        elseif this.hoverIndex > 0 && !hovered
            DIM_ALPHA
        else
            1.0
        end

        scale = get(this.slotScales, index, 1.0)
        alpha = get(this.slotAlphas, index, 1.0)
        scale += (target_scale - scale) * blend
        alpha += (target_alpha - alpha) * blend
        this.slotScales[index] = scale
        this.slotAlphas[index] = alpha

        _apply_slot_scale(this, slot_data, scale)
        offset = get(slot_data, "scaleOffset", Math.Vector2(0, 0))
        slot.anchor.current_state = :none
        slot.position = Math.Vector2(
            _slot_base_x(this) - offset.x,
            y - offset.y + _exit_offset(this, index),
        )

        _update_image_shake!(slot_data, deltaTime)

        display_alpha = clamp(alpha + pulse, 0.0, 1.0) * _exit_alpha(this)
        _set_slot_alpha(slot_data, display_alpha, slot_data["baseTint"])

        if leaving && alpha <= 0.01
            _hide_slot!(slot_data)
        end

        # Branches draw on with their slot, then retract into the spine on commit.
        if index <= length(this.branchProgress)
            branch_start = T_BRANCH + (index - 1) * BRANCH_STAGGER
            draw_on = _slide_progress(branch_start, this.sequenceTime, BRANCH_DURATION)
            this.branchProgress[index] = leaving ?
                draw_on * (1.0 - get(slot_data, "fade", 0.0)) :
                draw_on
        end
    end
end

function _exit_offset(this::RewardManager, index::Int)::Float64
    this.exitTime < 0.0 && return 0.0
    start = index * EXIT_STAGGER
    progress = _slide_progress(start, this.exitTime, EXIT_DURATION)
    return (OFFSCREEN_Y - GOLD_SLOT_Y) * ease_in_quad(progress)
end

function _exit_alpha(this::RewardManager)::Float64
    this.exitTime < 0.0 && return 1.0
    return 1.0 - clamp(this.exitTime / EXIT_DURATION, 0.0, 1.0)
end

function _update_exit(this::RewardManager, deltaTime::Float64)
    this.exitTime < 0.0 && return
    this.exitTime += deltaTime
    # Once off screen the elements are dead weight; is_showing stays false
    # afterwards so nothing rebuilds them.
    if this.exitTime >= _exit_total(this) && this.rewardsDisplayed
        clear_reward_slots(this)
        this.rewardsDisplayed = false
        this.state = :resolved
    end
end

#endregion

#region Immediate-mode drawing

"""
Draw the "Choose wisely" prompt and the tree lines. Called every frame from the
battle victory screen while the offer is on screen.
"""
const WEIGHT_ICON_SIZE = 36
const WEIGHT_PREVIEW_GUTTER = 24.0

function _hovered_weight_resolved(this::RewardManager)
    this.chosenIndex != 0 && return nothing
    this.inputBlocked && return nothing
    (this.hoverIndex >= 1 && this.hoverIndex <= length(this.choices)) || return nothing
    resolved = this.choices[this.hoverIndex]
    kind = resolved.kind
    (kind == :owned_weight || kind == :mystery_weight || kind == :new_piece) || return nothing
    kind == :mystery_weight && resolved.hidden && return nothing
    resolved.piece === nothing && return nothing
    return resolved
end

function _weight_preview_rows(this::RewardManager, resolved)
    owned = this.user === nothing || this.user.pieces === nothing ? [] : this.user.pieces
    return WeightPreviewPanelModule.rows_for_change(
        owned,
        resolved.piece,
        resolved.new_rarity;
        is_new = resolved.kind == :new_piece,
    )
end

function _dismiss_weight_preview!(this::RewardManager)
    WeightPreviewPanelModule.hide!(this.weightPreview)
    this.weightPreviewPinned = false
    this.weightPreviewHold = 0.0
end

function _pin_weight_preview!(this::RewardManager, resolved)
    (resolved === nothing || resolved.kind != :mystery_weight || resolved.piece === nothing) && return
    rows = _weight_preview_rows(this, resolved)
    isempty(rows) && return
    WeightPreviewPanelModule.show!(this.weightPreview, rows)
    this.weightPreviewPinned = true
end

function _sync_weight_preview!(this::RewardManager)
    this.weightPreviewPinned && return
    resolved = _hovered_weight_resolved(this)
    if resolved === nothing
        WeightPreviewPanelModule.hide!(this.weightPreview)
        return
    end
    WeightPreviewPanelModule.show!(this.weightPreview, _weight_preview_rows(this, resolved))
end

function _draw_weight_preview!(this::RewardManager, visible, alpha::Float64)
    this.weightPreview.progress <= 0.0 && return
    center_y = if !isempty(visible)
        first_y = minimum(_slot_current_y(sd) + _exit_offset(this, sd["index"]) for sd in visible)
        last = visible[argmax([_slot_current_y(sd) for sd in visible])]
        last_bottom = _slot_current_y(last) + Float64(last["baseSize"].y) + _exit_offset(this, last["index"])
        (first_y + last_bottom) / 2.0
    else
        (GOLD_SLOT_Y + OPTION_START_Y) / 2.0
    end
    WeightPreviewPanelModule.draw!(
        this.weightPreview;
        right_x = _slot_base_x(this) - WEIGHT_PREVIEW_GUTTER,
        center_y = center_y,
        alpha = this.weightPreviewPinned ? 1.0 : alpha,
    )
end

function _weight_arrow_x_from_slot_center(slot, text)::Float64
    body = String(text.text)
    slot_w = Float64(slot.size.x)
    text_w = Float64(text.size.x)
    font_size = hasproperty(text, :fontSize) ? Float64(text.fontSize) : 64.0
    text_w < 80.0 && (text_w = max(length(body), 1) * font_size * 0.55)
    text_right = slot_w + Float64(text.anchorOffset.x)
    text_left = text_right - text_w
    n = max(length(body), 1)
    arrow = findfirst("->", body)
    arrow_x = arrow === nothing ? text_left + text_w / 2.0 : text_left + text_w * (first(arrow) / n)
    return arrow_x - slot_w / 2.0
end

function _draw_weight_icons!(this::RewardManager, visible, alpha::Float64)
    (alpha <= 0.01 || this.chosenIndex != 0) && return
    globals = JulGame.UserGlobals["Module"]
    label_str = BattleStringsModule.BATTLE_STRINGS[:battle_reward_weight_label]
    label_w = length(label_str) * 22 * 0.56
    gap = 6.0
    group_w = WEIGHT_ICON_SIZE + gap + label_w
    for slot_data in visible
        index = slot_data["index"]
        (index >= 1 && index <= length(this.choices)) || continue
        resolved = this.choices[index]
        (resolved.kind == :owned_weight || resolved.kind == :mystery_weight) || continue
        slot = get(slot_data, "slot", nothing)
        text = get(slot_data, "text", nothing)
        (slot === nothing || text === nothing) && continue
        slot_alpha = get(this.slotAlphas, index, 1.0) * alpha
        slot_alpha <= 0.01 && continue
        icon = _is_weight_down(resolved) ? "arrowdebuff" : "arrowbuff"
        a = round(Int, 255 * slot_alpha)
        group_left = _weight_arrow_x_from_slot_center(slot, text) - group_w / 2.0
        top_y = -Float64(slot.size.y) / 2.0 + 18.0
        DisplayTextModule.display_text(
            "reward_weight_label_$(index)",
            label_str;
            fontSize = 22,
            color = (236, 231, 216, a),
            parent = slot,
            anchor = :center,
            anchorOffset = Math.Vector2(group_left + WEIGHT_ICON_SIZE + gap + label_w / 2.0, top_y),
            layer = 14,
        )
        JulGame.ImmediateUIModule.immediate_image(
            "reward_weight_icon_$(index)",
            globals.get_asset_path("status", icon);
            parent = slot,
            anchor = :center,
            anchorOffset = Math.Vector2(group_left + WEIGHT_ICON_SIZE / 2.0, top_y),
            size = Math.Vector2(WEIGHT_ICON_SIZE, WEIGHT_ICON_SIZE),
            layer = 14,
            color = (255, 255, 255, a),
        )
    end
end

function _draw_new_badges!(this::RewardManager, visible, alpha::Float64)
    alpha <= 0.01 && return
    badge = BattleStringsModule.BATTLE_STRINGS[:battle_reward_new_badge]
    for slot_data in visible
        get(slot_data, "leaving", false) && continue
        index = slot_data["index"]
        (index >= 1 && index <= length(this.choices)) || continue
        this.choices[index].kind == :new_piece || continue
        slot = slot_data["slot"]
        slot_alpha = get(this.slotAlphas, index, 1.0) * alpha
        slot_alpha <= 0.01 && continue
        flash = 0.5 + 0.5 * sin(this.sequenceTime * 10.0)
        DisplayTextModule.display_text(
            "reward_new_badge_$(index)",
            badge;
            fontSize = 34,
            color = (255, round(Int, 214 + 41 * flash), round(Int, 50 + 205 * flash), round(Int, 255 * slot_alpha)),
            parent = slot,
            anchor = :topRight,
            anchorOffset = Math.Vector2(-36, 6),
            layer = 14,
            rotation = -18.0,
        )
    end
end

function draw_choice_prompt(this::RewardManager)
    (this.rewardsDisplayed && !isempty(this.rewardSlots)) || return

    title_progress = _slide_progress(T_TITLE, this.sequenceTime, TITLE_DURATION)
    pinned = this.weightPreviewPinned && this.weightPreview.progress > 0.0
    preview_active = this.weightPreview.progress > 0.0
    title_progress <= 0.0 && !pinned && !preview_active && return

    # Prefab position.x is the slot's left edge, not its centre.
    slot_left = _slot_base_x(this)
    slot_width = Float64(_slot_size(this).x)

    exit_alpha = _exit_alpha(this)
    exit_alpha <= 0.01 && !pinned && !preview_active && return

    visible = [sd for sd in this.rewardSlots if sd["slot"] !== nothing && sd["slot"].isActive]
    isempty(visible) && !pinned && !preview_active && return

    if !isempty(visible) && title_progress > 0.0 && exit_alpha > 0.01
        first_y = minimum(_slot_current_y(sd) + _exit_offset(this, sd["index"]) for sd in visible)
        settle = ease_out_back(title_progress)
        drift = sin(this.sequenceTime * 1.2) * 2.0
        title_y = first_y - TITLE_ABOVE_SLOT + 40.0 * (1.0 - settle)
        title_progress >= 1.0 && (title_y += drift)

        DisplayTextModule.display_text(
            "reward_choose_title",
            BattleStringsModule.BATTLE_STRINGS[:battle_reward_choose];
            fontSize = 32,
            color = (236, 231, 216, round(Int, 255 * title_progress * exit_alpha)),
            anchor = :centerTop,
            anchorOffset = Math.Vector2(0, round(Int, title_y)),
            layer = 13,
        )

        _draw_new_badges!(this, visible, title_progress * exit_alpha)
        _draw_weight_icons!(this, visible, title_progress * exit_alpha)
    end

    _draw_weight_preview!(this, visible, pinned ? 1.0 : title_progress * exit_alpha)

    # Break the guaranteed dollars away from the pick-one column.
    if !isempty(visible) && this.goldSlot !== nothing && this.goldSlot["slot"] !== nothing && this.goldSlot["slot"].isActive
        first_y = minimum(_slot_current_y(sd) + _exit_offset(this, sd["index"]) for sd in visible)
        gold_bottom = _slot_current_y(this.goldSlot) + Float64(this.goldSlot["baseSize"].y) + _exit_offset(this, 0)
        sep_y = (gold_bottom + first_y) / 2.0
        RewardChoiceLinesModule.draw_separator(
            "reward_gold_separator",
            slot_left + 24.0,
            slot_left + slot_width - 24.0,
            sep_y;
            alpha = title_progress * exit_alpha,
            layer = 12,
        )
    end
end

#endregion

function JulGame.on_shutdown(this::RewardManager)
    clear_reward_slots(this)
end

end # module
