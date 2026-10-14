module RunScalingModule

using JulGame

# key: enemy key, value: number of encounters this run
const SEEN_ENEMIES = Dict{String, Int}()
const SHOP_VISITS = Dict{String, Int}()

function reset!()
    empty!(SEEN_ENEMIES)
    empty!(SHOP_VISITS)
end

const EnemyScaling = Dict{String, Vector{Tuple{Float64, String, Float64}}}(
    
"ENEMY_SLIME" => [
        (3.0, "Poison", 2.0),
        (5.0, "Heal", 3.0),
    ],
)

const DefaultEnemyScaling = [
    (1.5, "Poison", 1.5),
    (2.0, "Heal", 2.0),
]


function register_enemy_seen(enemy_key::String)
    isempty(enemy_key) && return
    enemies_dict = JulGame.UserGlobals["Module"].EnemiesModule.ALL_ENEMIES
    SEEN_ENEMIES[enemy_key] = get(SEEN_ENEMIES, enemy_key, 0) + 1
    seen = SEEN_ENEMIES[enemy_key]
    if seen >= 2 && seen <= 3
        scaling = get(EnemyScaling, enemy_key, DefaultEnemyScaling)[seen-1]
        update_shared_structure(enemies_dict, enemy_key, :average_health, round(Int, enemies_dict[enemy_key].average_health * scaling[1]))
        update_shared_structure(enemies_dict, enemy_key, :pattern, enemies_dict[enemy_key].pattern * ",$(scaling[2])")
        update_shared_structure(enemies_dict, enemy_key, :average_attack, round(Int, enemies_dict[enemy_key].average_attack * scaling[3]))
    end
end

function update_shared_structure(dict::Dict, key::String, value_symbol::Symbol, value::Any)
    try
        current_dict = dict[key]
        field_names = fieldnames(typeof(current_dict))
        field_values = [name == value_symbol ? value : getfield(current_dict, name) for name in field_names]
        dict[key] = typeof(current_dict)(field_values...)
    catch e
        @error "Error updating shared structure: $(e)"
        Base.show_backtrace(stderr, catch_backtrace())
    end
end

function register_encounter_enemies!(enemy_keys)
    seen_this = Set{String}()
    for raw in enemy_keys
        key = string(raw)
        (isempty(key) || key in seen_this) && continue
        push!(seen_this, key)
        register_enemy_seen(key)
    end
end

function register_shop_visit()
    SHOP_VISITS["count"] = get(SHOP_VISITS, "count", 0) + 1
end

function shop_visits()::Int
    get(SHOP_VISITS, "count", 0)
end

function times_seen(enemy_key::String)::Int
    get(SEEN_ENEMIES, enemy_key, 1)
end

"""Relative half-width around the scaled average (±20%)."""
const ATTACK_VARIANCE = 0.20
const COMBAT_VARIANCE = ATTACK_VARIANCE
const PRICE_VARIANCE = 0.20
# Attack and heal grow slower than defense. 1.0 is the full combat curve.
const ATTACK_HEAL_GROWTH = 0.4
const DEFENSE_GROWTH = 0.50

function intent_frequency_factor(pattern::AbstractString, keywords)::Float64
    parts = filter(!isempty, strip.(split(String(pattern), ',')))
    isempty(parts) && return 1.0
    keys = Set(lowercase(string(k)) for k in keywords)
    n = count(p -> lowercase(p) in keys, parts)
    n == 0 && return 1.0
    return length(parts) / Float64(n)
end

"""
How much rarer Attack/Bash is in the pattern vs an every-turn attacker.
`Attack,Defend,Summon` → 3.0; `Attack` → 1.0; no attack slots → 1.0.
"""
function attack_frequency_factor(pattern::AbstractString)::Float64
    return intent_frequency_factor(pattern, ("attack", "bash"))
end

function defend_frequency_factor(pattern::AbstractString)::Float64
    return intent_frequency_factor(pattern, ("defend", "allyshield"))
end

function heal_frequency_factor(pattern::AbstractString)::Float64
    return intent_frequency_factor(pattern, ("heal", "teamheal", "healking"))
end

function lookup_enemy_pattern(enemy_key::String)::String
    isempty(enemy_key) && return ""
    try
        globals = JulGame.UserGlobals["Module"]
        data = globals.get_enemy_data()
        enemy = get(data, enemy_key, nothing)
        enemy === nothing && return ""
        return string(enemy.pattern)
    catch
        return ""
    end
end

"""
Shared combat curve for attack / shield / heal.
Scale is 1.0 at floor 1 / first sighting / room 0 / turn 0.
Sparse intents ramp the turn term faster via `attack_frequency_factor`.
`growth` scales everything above 1.0 (attack and heal use `ATTACK_HEAL_GROWTH`).
Returns the deterministic average (no variance).
"""
function get_scaled_combat_value(
    base_value::Int,
    floor_number::Int;
    times_seen::Int = 1,
    floor_node_number::Int = 0,
    battle_turn_number::Int = 0,
    attack_frequency_factor::Float64 = 1.0,
    growth::Float64 = 1.0,
)::Int
    base_value <= 0 && return 0
    floor_t = max(0, floor_number - 1)
    seen_t = max(0, times_seen - 1)
    node_t = max(0, floor_node_number)
    turn_t = max(0, battle_turn_number)
    freq = max(1.0, attack_frequency_factor)

    run = 0.12 * floor_t + 0.06 * seen_t + 0.02 * node_t
    turn = (0.025 * turn_t + 0.006 * turn_t * turn_t) * freq
    return max(1, round(Int, base_value * (1.0 + (run + turn) * growth)))
end

const get_scaled_attack_value = get_scaled_combat_value

"""
Roll once around `average` by ±20%. When average ≥ 5, half-width is at least 1.
Clamp to ≥ 1. Call at intent set so the shown value matches the hit.
"""
function apply_combat_variance(average::Int)::Int
    average <= 0 && return 0
    half = average * COMBAT_VARIANCE
    if average >= 5
        half = max(half, 1.0)
    end
    lo = max(1, round(Int, average - half))
    hi = max(lo, round(Int, average + half))
    return rand(lo:hi)
end

const apply_attack_variance = apply_combat_variance

function current_scaling_context(enemy_key::String)
    seen = times_seen(enemy_key)
    floor_number = 1
    floor_node_number = 0
    battle_turn_number = 0
    try
        globals = JulGame.UserGlobals["Module"]
        dm = globals.get_data_manager()
        psm = dm.persistent_state_manager
        floor_number = max(1, Int(psm.currentFloor))
        floor_node_number = max(0, Int(psm.currentRoom))
        bm = dm.current_battle_manager
        if bm !== nothing && isdefined(bm, :battleTurnNumber)
            battle_turn_number = max(0, Int(bm.battleTurnNumber))
        end
    catch
    end
    return (seen, floor_number, floor_node_number, battle_turn_number)
end

function _scale_combat_stat(
    base_value::Int,
    enemy_key::String,
    pattern::AbstractString,
    freq_fn;
    growth::Float64 = 1.0,
)::Int
    seen, floor_number, node, turn = current_scaling_context(enemy_key)
    pat = String(pattern)
    isempty(pat) && (pat = lookup_enemy_pattern(enemy_key))
    freq = freq_fn(pat)
    average = get_scaled_combat_value(
        base_value,
        floor_number;
        times_seen = seen,
        floor_node_number = node,
        battle_turn_number = turn,
        attack_frequency_factor = freq,
        growth = growth,
    )
    return apply_combat_variance(average)
end

function scale_attack(
    base_attack_value::Int,
    enemy_key::String = "";
    pattern::AbstractString = "",
)::Int
    return _scale_combat_stat(base_attack_value, enemy_key, pattern, attack_frequency_factor; growth = ATTACK_HEAL_GROWTH)
end

function scale_defense(
    base_defense_value::Int,
    enemy_key::String = "";
    pattern::AbstractString = "",
)::Int
    return _scale_combat_stat(base_defense_value, enemy_key, pattern, defend_frequency_factor; growth = DEFENSE_GROWTH)
end

"""`base_heal_amount` is the absolute heal (e.g. average_heal * health), not the raw fraction."""
function scale_heal(
    base_heal_amount::Int,
    enemy_key::String = "";
    pattern::AbstractString = "",
)::Int
    return _scale_combat_stat(base_heal_amount, enemy_key, pattern, heal_frequency_factor; growth = ATTACK_HEAL_GROWTH)
end

#region Shop prices

function current_shop_scaling_context()
    floor_number = 1
    floor_node_number = 0
    try
        globals = JulGame.UserGlobals["Module"]
        psm = globals.get_data_manager().persistent_state_manager
        floor_number = max(1, Int(psm.currentFloor))
        floor_node_number = max(0, Int(psm.currentRoom))
    catch
    end
    return (floor_number, floor_node_number, shop_visits())
end

"""
Steady shop curve from `average_price`.
Scale is 1.0 on floor 1 / room 0 / first shop visit.
Gentler than combat so gold stays readable mid-run.
"""
function get_scaled_price_value(
    base_price::Int,
    floor_number::Int;
    floor_node_number::Int = 0,
    shop_visits::Int = 1,
)::Int
    base_price <= 0 && return 0
    floor_t = max(0, floor_number - 1)
    node_t = max(0, floor_node_number)
    visit_t = max(0, shop_visits - 1)

    run = 1.0 + 0.08 * floor_t + 0.02 * node_t + 0.03 * visit_t
    return max(1, round(Int, base_price * run))
end

"""Same ±20% band as attacks; min ±1 when average ≥ 5."""
function apply_price_variance(average::Int)::Int
    average <= 0 && return 0
    half = average * PRICE_VARIANCE
    if average >= 5
        half = max(half, 1.0)
    end
    lo = max(1, round(Int, average - half))
    hi = max(lo, round(Int, average + half))
    return rand(lo:hi)
end

function scale_price(base_price::Int)::Int
    floor_number, node, visits = current_shop_scaling_context()
    average = get_scaled_price_value(
        base_price,
        floor_number;
        floor_node_number = node,
        shop_visits = visits,
    )
    return apply_price_variance(average)
end

"""
Pick which stock category gets the shop's one 50% sale.
Weights: piece 50 / potion 35 / treasure 15, renormalized to what's in stock.
"""
function roll_shop_sale_kind(
    has_piece::Bool,
    has_potion::Bool,
    has_treasure::Bool,
)::Union{Symbol, Nothing}
    options = Tuple{Symbol, Float64}[]
    has_piece && push!(options, (:piece, 50.0))
    has_potion && push!(options, (:potion, 35.0))
    has_treasure && push!(options, (:treasure, 15.0))
    isempty(options) && return nothing

    total = sum(w for (_, w) in options)
    roll = rand() * total
    acc = 0.0
    for (kind, weight) in options
        acc += weight
        roll <= acc && return kind
    end
    return first(options)[1]
end

#endregion

end
