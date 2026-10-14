# Post-battle reward packages: a rarity-weighted table of three-option choices.
# Package ids are internal only; the player sees the resolved slots, never the names.
module RewardPackagesModule
using JulGame
using Random

# Weakest to strongest. Names match the ui-reward* frame assets; Unlucky has no
# art of its own and reuses the common frame drained of colour.
const TIER_ORDER = (:unlucky, :common, :uncommon, :rare, :epic, :enchanted)

const TIER_FRAMES = Dict{Symbol, String}(
    :unlucky => "ui-rewardcommon",
    :common => "ui-rewardcommon",
    :uncommon => "ui-rewarduncommon",
    :rare => "ui-rewardrare",
    :epic => "ui-rewardepic",
    :enchanted => "ui-rewardenchanted",
)

const TIER_FRAME_TINTS = Dict{Symbol, NTuple{4, Int}}(
    :unlucky => (105, 105, 112, 255),
)

# Bell curve peaking at Uncommon.
const TIER_WEIGHTS = (
    (:unlucky, 8.0),
    (:common, 16.0),
    (:uncommon, 32.0),
    (:rare, 24.0),
    (:epic, 13.0),
    (:enchanted, 7.0),
)

# Elites never roll Uncommon or below.
const ELITE_TIER_WEIGHTS = (
    (:rare, 34.0),
    (:epic, 18.0),
    (:enchanted, 10.0),
)

# Bosses never roll below Rare.
const BOSS_TIER_WEIGHTS = (
    (:rare, 50.0),
    (:epic, 32.0),
    (:enchanted, 18.0),
)

# Indexed by TIER_ORDER. Gold is further multiplied by the current floor.
const TIER_GOLD = (5, 10, 20, 35, 50, 80)
const TIER_HEAL = (4, 8, 12, 20, 0, 0)  # 0 means "full heal" at the top two tiers
const TIER_MAX_HP = (1, 2, 3, 5, 8, 10)

const MAGNITUDE_SCALE = Dict{Symbol, Float64}(
    :tiny => 0.5,
    :normal => 1.0,
    :large => 1.6,
    :huge => 2.5,
)

const COMMON_POTION_KEYS = ("POTION_BOMB", "POTION_DICE", "POTION_BASICBATTERY", "POTION_EYEDROPPER", "POTION_HERBALTEA")
const RARE_POTION_KEYS = ("POTION_GIGABOMB", "POTION_MEGABOMB", "POTION_ANGELTEARS", "POTION_ACTIVEBATTERY")

# A piece can never be squeezed out of the queue entirely, nor swallow it.
const MIN_SHARE = 0.05
const MAX_SHARE = 0.85
# One new gem per choice. Weight changes on the owned gem stay allowed.
const NEW_GEM_SLOT_KEY = "new_gem"

"""
One option in a package, before it is resolved against the player's inventory.
`kind` is one of :owned_weight, :mystery_weight, :new_piece, :potion, :resource, :treasure.
Negative `delta_pp` is a weight downgrade (named or mystery).
"""
struct Slot
    kind::Symbol
    delta_pp::Float64
    entry_share::Float64
    pool::Symbol
    magnitude::Symbol
end

function Slot(kind::Symbol; delta_pp::Real = 0.0, entry_share::Real = 0.0, pool::Symbol = :any, magnitude::Symbol = :normal)
    return Slot(kind, Float64(delta_pp), Float64(entry_share), pool, magnitude)
end

struct Package
    id::String
    tier::Symbol
    slots::Vector{Slot}
end

"""
A slot resolved against the current run: a concrete piece/potion/treasure or a
resource amount. `kind` here may differ from the authored slot when a fallback fired.
"""
mutable struct ResolvedSlot
    kind::Symbol
    effect::Symbol      # :gold, :heal, :heal_full, :max_hp, or :none
    piece               # weight slots: the piece being improved or granted
    item                # potion / treasure struct
    amount::Int
    old_share::Float64
    new_share::Float64
    new_rarity::Float64
    hidden::Bool        # mystery slots stay masked until the player commits
end

function ResolvedSlot(kind::Symbol; effect::Symbol = :none, piece = nothing, item = nothing,
                      amount::Int = 0, old_share::Float64 = 0.0, new_share::Float64 = 0.0,
                      new_rarity::Float64 = 0.0, hidden::Bool = false)
    return ResolvedSlot(kind, effect, piece, item, amount, old_share, new_share, new_rarity, hidden)
end

mutable struct RollContext
    globals
    user
    data_manager
    floor::Int
    tier::Symbol
    used_keys::Set{String}
end

#region Table

const PACKAGES = Package[
    # Unlucky
    Package("Ul1_PocketChange", :unlucky, [
        Slot(:resource; pool = :gold, magnitude = :tiny),
        Slot(:resource; pool = :heal, magnitude = :tiny),
        Slot(:resource; pool = :max_hp),
    ]),
    Package("Ul2_Scratch", :unlucky, [
        Slot(:owned_weight; delta_pp = 3),
        Slot(:resource; pool = :gold, magnitude = :tiny),
        Slot(:resource; pool = :heal, magnitude = :tiny),
    ]),
    Package("Ul3_Leftovers", :unlucky, [
        Slot(:resource; pool = :heal, magnitude = :tiny),
        Slot(:resource; pool = :gold, magnitude = :tiny),
        Slot(:resource; pool = :max_hp),
    ]),
    Package("Ul4_Consolation", :unlucky, [
        Slot(:new_piece; entry_share = 0.05),
        Slot(:resource; pool = :gold, magnitude = :tiny),
        Slot(:resource; pool = :heal, magnitude = :tiny),
    ]),
    Package("Ul5_Tax", :unlucky, [
        Slot(:owned_weight; delta_pp = -3),
        Slot(:resource; pool = :gold, magnitude = :tiny),
        Slot(:resource; pool = :heal, magnitude = :tiny),
    ]),

    # Common
    Package("C1_Rations", :common, [
        Slot(:resource; pool = :gold),
        Slot(:resource; pool = :heal),
        Slot(:potion; pool = :common),
    ]),
    Package("C2_PatchUp", :common, [
        Slot(:resource; pool = :heal),
        Slot(:resource; pool = :max_hp),
        Slot(:resource; pool = :gold),
    ]),
    Package("C3_Drill", :common, [
        Slot(:owned_weight; delta_pp = 5),
        Slot(:resource; pool = :gold),
        Slot(:resource; pool = :heal),
    ]),
    Package("C4_Recruit", :common, [
        Slot(:new_piece; entry_share = 0.08),
        Slot(:resource; pool = :gold),
        Slot(:resource; pool = :heal),
    ]),
    Package("C5_Sidearm", :common, [
        Slot(:potion; pool = :common),
        Slot(:owned_weight; delta_pp = 5),
        Slot(:resource; pool = :gold),
    ]),
    Package("C6_FirstAid", :common, [
        Slot(:resource; pool = :heal),
        Slot(:potion; pool = :common),
        Slot(:resource; pool = :max_hp),
    ]),
    Package("C7_Cull", :common, [
        Slot(:owned_weight; delta_pp = -5),
        Slot(:resource; pool = :heal),
        Slot(:resource; pool = :gold),
    ]),

    # Uncommon
    Package("U1_DraftAndDrill", :uncommon, [
        Slot(:owned_weight; delta_pp = 8),
        Slot(:new_piece; entry_share = 0.10),
        Slot(:resource; pool = :any),
    ]),
    Package("U2_Apothecary", :uncommon, [
        Slot(:potion; pool = :common),
        Slot(:owned_weight; delta_pp = 8),
        Slot(:resource; pool = :gold),
    ]),
    Package("U3_FreshBlood", :uncommon, [
        Slot(:new_piece; entry_share = 0.10),
        Slot(:potion; pool = :common),
        Slot(:resource; pool = :heal),
    ]),
    Package("U4_DoubleDrill", :uncommon, [
        Slot(:owned_weight; delta_pp = 8),
        Slot(:owned_weight; delta_pp = 5),
        Slot(:resource; pool = :gold),
    ]),
    Package("U5_SupplyDrop", :uncommon, [
        Slot(:potion; pool = :common),
        Slot(:resource; pool = :gold),
        Slot(:resource; pool = :max_hp),
    ]),
    Package("U6_FieldMedic", :uncommon, [
        Slot(:resource; pool = :heal),
        Slot(:resource; pool = :max_hp),
        Slot(:potion; pool = :common),
    ]),
    Package("U7_Shed", :uncommon, [
        Slot(:owned_weight; delta_pp = -8),
        Slot(:new_piece; entry_share = 0.12),
        Slot(:resource; pool = :gold),
    ]),

    # Rare
    Package("R1_Specialist", :rare, [
        Slot(:owned_weight; delta_pp = 12),
        Slot(:new_piece; entry_share = 0.12),
        Slot(:potion; pool = :any),
    ]),
    Package("R2_RelicCache", :rare, [
        Slot(:treasure),
        Slot(:resource; pool = :gold, magnitude = :large),
        Slot(:potion; pool = :any),
    ]),
    Package("R3_Fortify", :rare, [
        Slot(:resource; pool = :max_hp),
        Slot(:resource; pool = :heal, magnitude = :large),
        Slot(:owned_weight; delta_pp = 8),
    ]),
    Package("R4_NewBlood", :rare, [
        Slot(:new_piece; entry_share = 0.15),
        Slot(:potion; pool = :any),
        Slot(:resource; pool = :gold),
    ]),
    Package("R5_DoubleDose", :rare, [
        Slot(:potion; pool = :any),
        Slot(:potion; pool = :any),
        Slot(:resource; pool = :heal),
    ]),
    Package("R6_Heirloom", :rare, [
        Slot(:treasure),
        Slot(:owned_weight; delta_pp = 8),
        Slot(:resource; pool = :gold),
    ]),
    Package("R7_Prune", :rare, [
        Slot(:owned_weight; delta_pp = -8),
        Slot(:potion; pool = :any),
        Slot(:resource; pool = :gold, magnitude = :large),
    ]),

    # Epic
    Package("E1_EliteDraft", :epic, [
        Slot(:owned_weight; delta_pp = 12),
        Slot(:new_piece; entry_share = 0.15),
        Slot(:treasure),
    ]),
    Package("E2_MysterySpark", :epic, [
        Slot(:mystery_weight; delta_pp = 10),
        Slot(:potion; pool = :rare),
        Slot(:resource; pool = :max_hp),
    ]),
    Package("E3_Armory", :epic, [
        Slot(:new_piece; entry_share = 0.12),
        Slot(:new_piece; entry_share = 0.10),
        Slot(:resource; pool = :gold, magnitude = :large),
    ]),
    Package("E4_Vitality", :epic, [
        Slot(:resource; pool = :max_hp, magnitude = :large),
        Slot(:resource; pool = :heal),
        Slot(:owned_weight; delta_pp = 8),
    ]),
    Package("E5_RelicBrew", :epic, [
        Slot(:treasure),
        Slot(:potion; pool = :rare),
        Slot(:resource; pool = :gold),
    ]),
    Package("E6_MysteryTax", :epic, [
        Slot(:mystery_weight; delta_pp = -10),
        Slot(:potion; pool = :rare),
        Slot(:resource; pool = :gold, magnitude = :large),
    ]),

    # Enchanted
    Package("En1_FatesFavor", :enchanted, [
        Slot(:mystery_weight; delta_pp = 15),
        Slot(:new_piece; entry_share = 0.15),
        Slot(:potion; pool = :rare),
    ]),
    Package("En2_Jackpot", :enchanted, [
        Slot(:mystery_weight; delta_pp = 12),
        Slot(:resource; pool = :gold, magnitude = :huge),
        Slot(:treasure),
    ]),
    Package("En3_Transformation", :enchanted, [
        Slot(:new_piece; entry_share = 0.18),
        Slot(:owned_weight; delta_pp = 12),
        Slot(:resource; pool = :heal),
    ]),
    Package("En4_Pandora", :enchanted, [
        Slot(:mystery_weight; delta_pp = 10),
        Slot(:treasure),
        Slot(:potion; pool = :rare),
    ]),
    Package("En5_Gamble", :enchanted, [
        Slot(:mystery_weight; delta_pp = -12),
        Slot(:mystery_weight; delta_pp = 12),
        Slot(:treasure),
    ]),
]

#endregion

#region Tier helpers

function tier_index(tier::Symbol)::Int
    index = findfirst(==(tier), TIER_ORDER)
    return index === nothing ? 1 : index
end

function frame_for_tier(tier::Symbol)::String
    return JulGame.UserGlobals["Module"].get_asset_path(get(TIER_FRAMES, tier, TIER_FRAMES[:common]))
end

function frame_tint_for_tier(tier::Symbol)::NTuple{4, Int}
    return get(TIER_FRAME_TINTS, tier, (255, 255, 255, 255))
end

function min_tier_for_category(category::String)::Symbol
    return (category == "elite" || category == "boss") ? :rare : first(TIER_ORDER)
end

function tier_weights_for_category(category::String)
    if category == "boss"
        return BOSS_TIER_WEIGHTS
    elseif category == "elite"
        return ELITE_TIER_WEIGHTS
    end
    return TIER_WEIGHTS
end

function _weighted_pick(entries, rng::AbstractRNG)
    total = sum(w for (_, w) in entries)
    total <= 0.0 && return first(entries)[1]
    roll = rand(rng) * total
    acc = 0.0
    for (value, weight) in entries
        acc += weight
        roll <= acc && return value
    end
    return last(entries)[1]
end

#endregion

#region Pools

function _normalize_key(key)::String
    return uppercase(strip(string(key)))
end

function _available_potions(ctx::RollContext, pool::Symbol)
    potions = ctx.data_manager.potion_data
    potions === nothing && return []
    values_list = potions isa Dict ? collect(values(potions)) : collect(potions)
    values_list = filter(ctx.globals.item_available_in_game, values_list)
    if pool == :common || pool == :rare
        wanted = pool == :common ? COMMON_POTION_KEYS : RARE_POTION_KEYS
        wanted_set = Set(_normalize_key(k) for k in wanted)
        scoped = filter(p -> _normalize_key(p.key) in wanted_set, values_list)
        # Authored pools are a curation, not a hard constraint: if the sheet has
        # disabled everything in the tier, fall back to whatever is playable.
        isempty(scoped) || (values_list = scoped)
    end
    owned = Set(_normalize_key(p.key) for p in ctx.user.potions if p !== nothing)
    values_list = filter(p -> !(_normalize_key(p.key) in ctx.used_keys), values_list)
    unowned = filter(p -> !(_normalize_key(p.key) in owned), values_list)
    pool_list = isempty(unowned) ? values_list : unowned
    sort!(pool_list, by = p -> string(p.key))
    return pool_list
end

function _owned_gem_quality(ctx::RollContext)
    best = nothing
    for piece in ctx.user.pieces
        piece === nothing && continue
        ctx.globals.UserModule.is_gem_piece(piece) || continue
        score = ctx.globals.UserModule.piece_quality_score(piece)
        if best === nothing || score > best
            best = score
        end
    end
    return best
end

function _available_new_pieces(ctx::RollContext)
    pieces = ctx.data_manager.piece_data
    (pieces === nothing || isempty(pieces)) && return []
    candidates = [p[2] for p in collect(pieces) if ctx.globals.item_available_in_game(p[2])]
    owned = Set(_normalize_key(p.key) for p in ctx.user.pieces if p !== nothing)
    candidates = filter(p -> !(_normalize_key(p.key) in owned), candidates)
    candidates = filter(p -> !(_normalize_key(p.key) in ctx.used_keys), candidates)
    # One gem only: never a worse/equal new gem than the one held, and never
    # two new-gem cards in the same trio. An owned-gem weight change is fine.
    if NEW_GEM_SLOT_KEY in ctx.used_keys
        candidates = filter(p -> !ctx.globals.UserModule.is_gem_piece(p), candidates)
    else
        best_gem = _owned_gem_quality(ctx)
        if best_gem !== nothing
            candidates = filter(candidates) do piece
                !ctx.globals.UserModule.is_gem_piece(piece) ||
                    ctx.globals.UserModule.piece_quality_score(piece) > best_gem
            end
        end
    end
    sort!(candidates, by = p -> string(p.key))
    return candidates
end

function _weight_changeable_owned_pieces(ctx::RollContext, delta_pp::Float64)
    owned = [p for p in ctx.user.pieces if p !== nothing]
    isempty(owned) && return []
    growing = delta_pp >= 0.0
    candidates = filter(owned) do piece
        _normalize_key(piece.key) in ctx.used_keys && return false
        share = ctx.globals.UserModule.piece_board_share(piece, owned)
        return growing ? share < MAX_SHARE - 0.01 : share > MIN_SHARE + 0.01
    end
    sort!(candidates, by = p -> string(p.key))
    return candidates
end

function _available_treasures(ctx::RollContext)
    treasures = ctx.data_manager.treasure_data
    (treasures === nothing || isempty(treasures)) && return []
    candidates = [t[2] for t in collect(treasures) if ctx.globals.item_available_in_game(t[2])]
    character = get(ctx.globals.get_characters_data(), ctx.user.selectedCharacter, nothing)
    if character !== nothing
        candidates = filter(t -> t.key != character.treasure, candidates)
    end
    owned = Set(_normalize_key(t.key) for t in ctx.user.treasures if t !== nothing)
    candidates = filter(t -> !(_normalize_key(t.key) in owned), candidates)
    candidates = filter(t -> !(_normalize_key(t.key) in ctx.used_keys), candidates)
    sort!(candidates, by = t -> string(t.key))
    return candidates
end

function _pick_by_inverse_rarity(items, rng::AbstractRNG)
    isempty(items) && return nothing
    weights = [1.0 / max(Float64(item.rarity), 0.01) for item in items]
    return items[_weighted_pick(collect(zip(1:length(items), weights)), rng)]
end

#endregion

#region Resolution

function _tier_amount(table, tier::Symbol, magnitude::Symbol)::Int
    base = table[tier_index(tier)]
    scale = get(MAGNITUDE_SCALE, magnitude, 1.0)
    return max(1, round(Int, base * scale))
end

function gold_slot(ctx::RollContext, magnitude::Symbol = :normal)::ResolvedSlot
    amount = _tier_amount(TIER_GOLD, ctx.tier, magnitude) * max(1, ctx.floor)
    return ResolvedSlot(:gold; effect = :gold, amount = amount)
end

function _resource_key(pool::Symbol)::String
    pool == :max_hp && return "resource:max_hp"
    pool == :heal && return "resource:heal"
    return "resource:gold"
end

function _unused_resource_pools(ctx::RollContext)
    return [pool for pool in (:gold, :heal, :max_hp) if !(_resource_key(pool) in ctx.used_keys)]
end

function _pick_resource_pool(ctx::RollContext, rng::AbstractRNG, preferred::Symbol)::Symbol
    unused = _unused_resource_pools(ctx)
    isempty(unused) && return :gold
    preferred in unused && return preferred
    return unused[rand(rng, 1:length(unused))]
end

function _resolve_resource(slot::Slot, ctx::RollContext, rng::AbstractRNG)::ResolvedSlot
    preferred = slot.pool == :any ?
        _weighted_pick(((:gold, 1.0), (:heal, 1.0), (:max_hp, 1.0)), rng) :
        slot.pool
    pool = _pick_resource_pool(ctx, rng, preferred)
    if pool == :gold
        return gold_slot(ctx, slot.magnitude)
    elseif pool == :max_hp
        amount = _tier_amount(TIER_MAX_HP, ctx.tier, slot.magnitude)
        return ResolvedSlot(:resource; effect = :max_hp, amount = amount)
    end
    base = TIER_HEAL[tier_index(ctx.tier)]
    if base <= 0
        return ResolvedSlot(:resource; effect = :heal_full)
    end
    amount = _tier_amount(TIER_HEAL, ctx.tier, slot.magnitude)
    return ResolvedSlot(:resource; effect = :heal, amount = amount)
end

"""
Rarity that lands `piece` on `target_share` of the pool, holding every other
piece fixed. Inverse of the "Weight: x%" share formula.
"""
function _rarity_for_target_share(piece, owned, target_share::Float64)::Float64
    globals = JulGame.UserGlobals["Module"]
    total = 0.0
    for p in owned
        p === nothing && continue
        total += Float64(p.weight)
    end
    others = max(0.0, total - Float64(piece.weight))
    return globals.UserModule.rarity_for_share(target_share, others)
end

function _resolve_owned_weight(slot::Slot, ctx::RollContext, rng::AbstractRNG; hidden::Bool = false)
    owned = [p for p in ctx.user.pieces if p !== nothing]
    candidates = _weight_changeable_owned_pieces(ctx, slot.delta_pp)
    isempty(candidates) && return nothing
    piece = candidates[rand(rng, 1:length(candidates))]
    old_share = ctx.globals.UserModule.piece_board_share(piece, owned)
    new_share = clamp(old_share + slot.delta_pp / 100.0, MIN_SHARE, MAX_SHARE)
    moved = slot.delta_pp >= 0.0 ? new_share > old_share + 0.001 : new_share < old_share - 0.001
    moved || return nothing
    return ResolvedSlot(
        hidden ? :mystery_weight : :owned_weight;
        piece = piece,
        old_share = old_share,
        new_share = new_share,
        new_rarity = _rarity_for_target_share(piece, owned, new_share),
        hidden = hidden,
    )
end

function _resolve_new_piece(slot::Slot, ctx::RollContext, rng::AbstractRNG)
    candidates = _available_new_pieces(ctx)
    isempty(candidates) && return nothing
    piece = _pick_by_inverse_rarity(candidates, rng)
    piece === nothing && return nothing
    owned = [p for p in ctx.user.pieces if p !== nothing]
    total = 0.0
    for p in owned
        total += Float64(p.weight)
    end
    share = clamp(slot.entry_share, MIN_SHARE, MAX_SHARE)
    return ResolvedSlot(
        :new_piece;
        piece = piece,
        old_share = 0.0,
        new_share = share,
        # A new piece joins the pool, so it is measured against the post-add total.
        new_rarity = ctx.globals.UserModule.rarity_for_share(share, total),
    )
end

function _resolve_potion(slot::Slot, ctx::RollContext, rng::AbstractRNG)
    length(ctx.user.potions) >= ctx.user.max_potions && return nothing
    candidates = _available_potions(ctx, slot.pool)
    isempty(candidates) && return nothing
    potion = _pick_by_inverse_rarity(candidates, rng)
    potion === nothing && return nothing
    return ResolvedSlot(:potion; item = potion)
end

function _resolve_treasure(slot::Slot, ctx::RollContext, rng::AbstractRNG)
    candidates = _available_treasures(ctx)
    isempty(candidates) && return nothing
    treasure = _pick_by_inverse_rarity(candidates, rng)
    treasure === nothing && return nothing
    return ResolvedSlot(:treasure; item = treasure)
end

function resolve_slot(slot::Slot, ctx::RollContext, rng::AbstractRNG)::ResolvedSlot
    resolved = if slot.kind == :owned_weight
        _resolve_owned_weight(slot, ctx, rng)
    elseif slot.kind == :mystery_weight
        _resolve_owned_weight(slot, ctx, rng; hidden = true)
    elseif slot.kind == :new_piece
        _resolve_new_piece(slot, ctx, rng)
    elseif slot.kind == :potion
        _resolve_potion(slot, ctx, rng)
    elseif slot.kind == :treasure
        _resolve_treasure(slot, ctx, rng)
    else
        _resolve_resource(slot, ctx, rng)
    end

    # A slot that cannot resolve becomes an unused resource so the trio stays distinct.
    if resolved === nothing
        fallback_pool = _pick_resource_pool(ctx, rng, :gold)
        resolved = _resolve_resource(Slot(:resource; pool = fallback_pool, magnitude = slot.magnitude), ctx, rng)
    end

    key = slot_key(resolved)
    if key != "" && key in ctx.used_keys
        fallback_pool = _pick_resource_pool(ctx, rng, :gold)
        resolved = _resolve_resource(Slot(:resource; pool = fallback_pool, magnitude = slot.magnitude), ctx, rng)
        key = slot_key(resolved)
    end
    key != "" && push!(ctx.used_keys, key)
    if resolved.kind == :new_piece && resolved.piece !== nothing &&
       ctx.globals.UserModule.is_gem_piece(resolved.piece)
        push!(ctx.used_keys, NEW_GEM_SLOT_KEY)
    end
    return resolved
end

function slot_key(resolved::ResolvedSlot)::String
    if resolved.piece !== nothing
        return _normalize_key(resolved.piece.key)
    elseif resolved.item !== nothing
        return _normalize_key(resolved.item.key)
    elseif resolved.kind == :gold || resolved.effect == :gold
        return "resource:gold"
    elseif resolved.effect == :heal || resolved.effect == :heal_full
        return "resource:heal"
    elseif resolved.effect == :max_hp
        return "resource:max_hp"
    end
    return ""
end

"""
True when at least one authored slot can resolve to something other than gold.
Packages that would collapse entirely into gold are dropped before the roll.
"""
function has_meaningful_slot(package::Package, ctx::RollContext)::Bool
    for slot in package.slots
        if slot.kind == :resource
            # Heal and max HP are real rewards even when gold is the roll.
            slot.pool == :gold || return true
        elseif slot.kind == :owned_weight || slot.kind == :mystery_weight
            isempty(_weight_changeable_owned_pieces(ctx, slot.delta_pp)) || return true
        elseif slot.kind == :new_piece
            isempty(_available_new_pieces(ctx)) || return true
        elseif slot.kind == :potion
            if length(ctx.user.potions) < ctx.user.max_potions && !isempty(_available_potions(ctx, slot.pool))
                return true
            end
        elseif slot.kind == :treasure
            isempty(_available_treasures(ctx)) || return true
        end
    end
    return false
end

"""Elite packages must author a treasure option so the player always sees one offered."""
function package_offers_treasure(package::Package)::Bool
    return any(s -> s.kind == :treasure, package.slots)
end

function package_eligible_for_category(package::Package, category::String, ctx::RollContext)::Bool
    has_meaningful_slot(package, ctx) || return false
    if category == "elite"
        package_offers_treasure(package) || return false
        # If every treasure is already owned, keep the authored treasure packages
        # (slot falls back to a resource) rather than opening the full rare pool.
    end
    return true
end

#endregion

#region Rolling

function build_context(floor::Int, tier::Symbol = :common)::RollContext
    globals = JulGame.UserGlobals["Module"]
    return RollContext(
        globals,
        globals.get_user_data(),
        globals.get_data_manager(),
        max(1, floor),
        tier,
        Set{String}(),
    )
end

"""
Roll a package for this node and resolve its slots against the current run.
Returns `(package, Vector{ResolvedSlot})`. Deterministic for a given rng.
Elites always roll a package that includes a treasure option.
"""
function roll_package(rng::AbstractRNG, floor::Int, category::String)
    ctx = build_context(floor)
    tier = _weighted_pick(tier_weights_for_category(category), rng)

    candidates = Package[]
    tried = Symbol[]
    floor_tier = min_tier_for_category(category)
    min_index = tier_index(floor_tier)
    # Walk down the tiers if a tier has nothing worth offering this run.
    while isempty(candidates)
        ctx.tier = tier
        candidates = filter(p -> p.tier == tier && package_eligible_for_category(p, category, ctx), PACKAGES)
        isempty(candidates) || break
        push!(tried, tier)
        index = tier_index(tier)
        index <= min_index && break
        tier = TIER_ORDER[index - 1]
        tier in tried && break
    end

    if isempty(candidates)
        ctx.tier = floor_tier
        candidates = filter(p -> p.tier == floor_tier && package_eligible_for_category(p, category, ctx), PACKAGES)
        if isempty(candidates)
            candidates = filter(p -> tier_index(p.tier) >= min_index && package_eligible_for_category(p, category, ctx), PACKAGES)
        end
        # Last resort: if no treasure-bearing packages remain (e.g. data missing),
        # fall back to any meaningful package at the category floor.
        if isempty(candidates) && category == "elite"
            candidates = filter(p -> tier_index(p.tier) >= min_index && has_meaningful_slot(p, ctx), PACKAGES)
        end
    end
    isempty(candidates) && return (nothing, ResolvedSlot[])

    package = candidates[rand(rng, 1:length(candidates))]
    ctx.tier = package.tier
    empty!(ctx.used_keys)

    resolved = ResolvedSlot[resolve_slot(slot, ctx, rng) for slot in package.slots]
    return (package, resolved)
end

#endregion

#region Applying

"""
Grant a resolved slot. Returns false when nothing could be applied, so callers
can fall back rather than showing a reward that silently did nothing.
"""
function apply_slot!(user, resolved::ResolvedSlot)::Bool
    globals = JulGame.UserGlobals["Module"]

    if resolved.kind == :owned_weight || resolved.kind == :mystery_weight
        resolved.piece === nothing && return false
        for i in eachindex(user.pieces)
            piece = user.pieces[i]
            piece === nothing && continue
            if _normalize_key(piece.key) == _normalize_key(resolved.piece.key)
                user.pieces[i] = globals.UserModule.with_rarity(piece, resolved.new_rarity)
                return true
            end
        end
        return false

    elseif resolved.kind == :new_piece
        resolved.piece === nothing && return false
        piece = globals.UserModule.with_rarity(resolved.piece, resolved.new_rarity)
        return globals.UserModule.add_piece_with_gem_limit!(user, piece)

    elseif resolved.kind == :potion
        resolved.item === nothing && return false
        length(user.potions) >= user.max_potions && return false
        push!(user.potions, resolved.item)
        return true

    elseif resolved.kind == :treasure
        resolved.item === nothing && return false
        if user.treasures === nothing
            user.treasures = []
        end
        push!(user.treasures, resolved.item)
        return true

    elseif resolved.kind == :gold || resolved.effect == :gold
        user.gold += resolved.amount
        return true

    elseif resolved.effect == :heal_full
        user.health = user.maxHealth
        return true

    elseif resolved.effect == :heal
        user.health = min(user.maxHealth, user.health + resolved.amount)
        return true

    elseif resolved.effect == :max_hp
        user.maxHealth += resolved.amount
        return true
    end

    return false
end

#endregion

end # module
