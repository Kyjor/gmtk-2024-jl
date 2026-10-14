module RunRecorderModule
    using Dates
    using Random
    using ..Globals
    using ...MapFloorSystemModule: IS_DEMO

    # Records one run for analytics: final loadout, a coarse timeline, per-battle summaries and
    # per-item stats. Owns all of its state; game code only makes one-line calls into it.
    # Inventory changes (treasures, pieces, potions, gold) are detected by diffing, so every
    # acquisition source is captured without hooking each push site.

    const MAX_TIMELINE_EVENTS = 3000

    mutable struct RunRecord
        run_uuid::String
        started_at::String
        game_version::String
        seed::Int
        character::String
        context::String
        timeline::Vector{Dict{String, Any}}
        dropped_events::Int
        battles::Vector{Dict{String, Any}}
        current_battle::Union{Nothing, Dict{String, Any}}
        items::Dict{String, Dict{String, Any}}
        totals::Dict{String, Int}
        known_treasures::Vector{String}
        known_pieces::Dict{String, Vector{Float64}}
        known_potions::Dict{String, Int}
        known_gold::Int
    end

    _empty_items() = Dict{String, Dict{String, Any}}(
        "treasures" => Dict{String, Any}(),
        "potions" => Dict{String, Any}(),
        "abilities" => Dict{String, Any}(),
        "pieces" => Dict{String, Any}(),
    )

    _new_record() = RunRecord("", "", "", 0, "", "start", Dict{String, Any}[], 0, Dict{String, Any}[], nothing,
        _empty_items(), Dict{String, Int}(), String[], Dict{String, Vector{Float64}}(), Dict{String, Int}(), 0)

    const STATE = Ref(_new_record())

    is_active()::Bool = !isempty(STATE[].run_uuid)

    # ---------------------------------------------------------------- helpers

    function _uuid4()::String
        b = rand(RandomDevice(), UInt8, 16)
        b[7] = (b[7] & 0x0f) | 0x40
        b[9] = (b[9] & 0x3f) | 0x80
        h = bytes2hex(b)
        return "$(h[1:8])-$(h[9:12])-$(h[13:16])-$(h[17:20])-$(h[21:32])"
    end

    _iso_now() = Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"

    function _prop(obj, name::Symbol, default)
        obj === nothing && return default
        try
            if obj isa AbstractDict
                return get(obj, string(name), get(obj, name, default))
            end
            hasproperty(obj, name) || return default
            v = getproperty(obj, name)
            return v === nothing ? default : v
        catch
            return default
        end
    end

    function _psm()
        try
            return Globals.get_data_manager().persistent_state_manager
        catch
            return nothing
        end
    end

    function _user()
        try
            return Globals.get_data_manager().user_data
        catch
            return nothing
        end
    end

    _int(x, default::Int = 0) = x isa Number ? round(Int, x) : something(tryparse(Int, string(x)), default)

    function _weight(piece)::Float64
        raw = try
            getfield(piece, :weight)
        catch
            _prop(piece, :weight, 10)
        end
        raw isa Number && return Float64(raw)
        return something(tryparse(Float64, strip(string(raw))), 10.0)
    end

    _keys_of(items) = items === nothing ? String[] : [string(_prop(i, :key, "")) for i in items if i !== nothing && !isempty(string(_prop(i, :key, "")))]

    function _count_keys(keys::Vector{String})
        d = Dict{String, Int}()
        for k in keys
            d[k] = get(d, k, 0) + 1
        end
        return d
    end

    function _piece_weights(user)
        d = Dict{String, Vector{Float64}}()
        pieces = _prop(user, :pieces, nothing)
        pieces === nothing && return d
        for p in pieces
            p === nothing && continue
            k = string(_prop(p, :key, ""))
            isempty(k) && continue
            push!(get!(d, k, Float64[]), _weight(p))
        end
        foreach(sort!, values(d))
        return d
    end

    function _item_stats(kind::String, key::String)::Dict{String, Any}
        bucket = STATE[].items[kind]
        return get!(bucket, key) do
            Dict{String, Any}()
        end
    end

    function _bump!(d::AbstractDict, field::String, n::Real = 1)
        d[field] = get(d, field, 0) + n
    end

    add_total!(name::String, n::Real = 1) = (STATE[].totals[name] = get(STATE[].totals, name, 0) + round(Int, n); nothing)

    function _where()
        psm = _psm()
        return (
            t = round(Float64(_prop(psm, :runElapsedTime, 0.0)); digits = 1),
            floor = _int(_prop(psm, :currentFloor, 0)),
            node = _int(_prop(psm, :currentLevel, 0)),
            room = _int(_prop(psm, :currentRoom, 0)),
        )
    end

    function _encounter_label(ev)
        type = string(_prop(ev, :type, ""))
        category = string(_prop(ev, :category, ""))
        name = string(_prop(ev, :name, ""))
        return (type = type, category = category, name = name)
    end

    function _context_for(ev)::String
        e = _encounter_label(ev)
        e.type == "Battle" && return e.category == "boss" ? "boss_battle" : "battle"
        e.type == "Treasure" && return "treasure_node"
        if e.type == "Event"
            e.category in ("shop", "rest") && return e.category
            return isempty(e.name) ? "event" : "event:$(e.name)"
        end
        return isempty(e.type) ? "other" : lowercase(e.type)
    end

    # ---------------------------------------------------------------- lifecycle

    """New run (character confirmed). The starting kit is baselined as source "start" without timeline noise."""
    function start_run!(character::AbstractString = "")
        try
            psm = _psm()
            user = _user()
            r = _new_record()
            r.run_uuid = _uuid4()
            r.started_at = _iso_now()
            r.game_version = try string(Globals.get_version(), IS_DEMO ? "-demo" : "") catch; "" end
            r.seed = _int(_prop(psm, :seed, 0))
            r.character = isempty(character) ? string(_prop(user, :selectedCharacter, "")) : String(character)
            r.context = "start"
            STATE[] = r
            _sync!(; emit = false)
            record!("run_start";
                character = r.character,
                treasures = copy(r.known_treasures),
                pieces = sort(collect(keys(r.known_pieces))),
                potions = sort(collect(keys(r.known_potions))),
                hp = _int(_prop(user, :health, 0)),
                max_hp = _int(_prop(user, :maxHealth, 0)),
                gold = r.known_gold)
        catch e
            @debug "RunRecorder.start_run!: $e"
        end
        return nothing
    end

    """Clear everything (called when run state is reset)."""
    reset!() = (STATE[] = _new_record(); nothing)

    function _ensure_started!()
        is_active() || start_run!()
    end

    # ---------------------------------------------------------------- timeline

    function record!(type::AbstractString; kw...)
        try
            _ensure_started!()
            r = STATE[]
            _sync!()
            if length(r.timeline) >= MAX_TIMELINE_EVENTS
                r.dropped_events += 1
                return nothing
            end
            w = _where()
            ev = Dict{String, Any}("type" => String(type), "t" => w.t, "floor" => w.floor, "node" => w.node)
            for (k, v) in kw
                ev[string(k)] = v
            end
            push!(r.timeline, ev)
        catch e
            @debug "RunRecorder.record!($type): $e"
        end
        return nothing
    end

    """Diff live inventory against the last known state and log acquisitions under the current context."""
    function _sync!(; emit::Bool = true)
        r = STATE[]
        user = _user()
        user === nothing && return
        w = _where()

        treasures = _keys_of(_prop(user, :treasures, nothing))
        for k in treasures
            k in r.known_treasures && continue
            push!(r.known_treasures, k)
            stats = _item_stats("treasures", k)
            get!(stats, "source", r.context)
            get!(stats, "floor", w.floor)
            get!(stats, "node", w.node)
            get!(stats, "t", w.t)
            get!(stats, "triggers", 0)
            emit && _push_raw!("treasure_gained", w; key = k, source = r.context)
        end
        for k in copy(r.known_treasures)
            k in treasures && continue
            filter!(!=(k), r.known_treasures)
            emit && _push_raw!("treasure_lost", w; key = k, source = r.context)
        end

        pieces = _piece_weights(user)
        for k in union(keys(pieces), keys(r.known_pieces))
            now_w = get(pieces, k, Float64[])
            old_w = get(r.known_pieces, k, Float64[])
            now_w == old_w && continue
            if emit
                if length(now_w) > length(old_w)
                    _push_raw!("piece_added", w; key = k, n = length(now_w) - length(old_w), source = r.context)
                elseif length(now_w) < length(old_w)
                    _push_raw!("piece_removed", w; key = k, n = length(old_w) - length(now_w), source = r.context)
                else
                    _push_raw!("piece_upgraded", w; key = k, from = old_w, to = now_w, source = r.context)
                end
            end
        end
        r.known_pieces = pieces

        potions = _count_keys(_keys_of(_prop(user, :potions, nothing)))
        for (k, n) in potions
            gained = n - get(r.known_potions, k, 0)
            gained > 0 || continue
            _bump!(_item_stats("potions", k), "gained", gained)
            emit && _push_raw!("potion_gained", w; key = k, n = gained, source = r.context)
        end
        r.known_potions = potions

        gold = _int(_prop(user, :gold, 0))
        delta = gold - r.known_gold
        if emit && delta > 0
            add_total!("gold_earned", delta)
        elseif emit && delta < 0
            add_total!("gold_lost", -delta)
        end
        r.known_gold = gold
        return nothing
    end

    function _push_raw!(type::String, w; kw...)
        r = STATE[]
        if length(r.timeline) >= MAX_TIMELINE_EVENTS
            r.dropped_events += 1
            return
        end
        ev = Dict{String, Any}("type" => type, "t" => w.t, "floor" => w.floor, "node" => w.node)
        for (k, v) in kw
            ev[string(k)] = v
        end
        push!(r.timeline, ev)
    end

    """Attribute later acquisitions to `ctx` (e.g. "shop", "reward")."""
    function set_context!(ctx::AbstractString)
        try
            _ensure_started!()
            _sync!()
            STATE[].context = String(ctx)
        catch e
            @debug "RunRecorder.set_context!: $e"
        end
        return nothing
    end

    """Map node chosen: logs the node and switches the acquisition context to it."""
    function node_selected!(encounter)
        try
            _ensure_started!()
            _sync!()
            e = _encounter_label(encounter)
            enemies = [string(_prop(en, :key, "")) for en in _prop(encounter, :enemies, [])]
            record!("node_selected"; node_type = e.type, category = e.category, name = e.name,
                enemies = filter(!isempty, enemies))
            STATE[].context = _context_for(encounter)
        catch ex
            @debug "RunRecorder.node_selected!: $ex"
        end
        return nothing
    end

    # ---------------------------------------------------------------- battles

    function battle_start!(enemy_keys)
        try
            _ensure_started!()
            r = STATE[]
            if r.current_battle !== nothing
                r.current_battle["result"] = "restarted"
                push!(r.battles, r.current_battle)
                r.current_battle = nothing
            end
            _sync!()
            psm = _psm()
            user = _user()
            w = _where()
            e = _encounter_label(_prop(psm, :currentEvent, nothing))
            keys = [string(k) for k in enemy_keys]
            r.current_battle = Dict{String, Any}(
                "index" => length(r.battles) + 1,
                "floor" => w.floor, "node" => w.node, "room" => w.room, "t_start" => w.t,
                "category" => e.category, "name" => e.name, "enemies" => keys,
                "hp_start" => _int(_prop(user, :health, 0)),
                "max_hp_start" => _int(_prop(user, :maxHealth, 0)),
                "shield_start" => _int(_prop(user, :shield, 0)),
                "gold_start" => _int(_prop(user, :gold, 0)),
                "turns" => 0, "damage_dealt" => 0, "damage_taken" => 0, "max_hit" => 0, "max_combo" => 0,
                "swaps" => 0, "queue_placements" => 0, "rerolls" => 0, "kills" => 0, "death_prevented" => 0,
                "matches" => Dict{String, Any}(), "abilities" => Dict{String, Any}(), "potions" => Dict{String, Any}(),
                "result" => "in_progress",
            )
            record!("battle_start"; enemies = keys, category = e.category, hp = r.current_battle["hp_start"])
        catch ex
            @debug "RunRecorder.battle_start!: $ex"
        end
        return nothing
    end

    """`result` is "won", "died" or "abandoned"."""
    function battle_end!(result::AbstractString)
        try
            r = STATE[]
            b = r.current_battle
            b === nothing && return nothing
            user = _user()
            w = _where()
            b["result"] = String(result)
            b["hp_end"] = _int(_prop(user, :health, 0))
            b["max_hp_end"] = _int(_prop(user, :maxHealth, 0))
            b["duration"] = round(w.t - Float64(b["t_start"]); digits = 1)
            push!(r.battles, b)
            r.current_battle = nothing
            record!("battle_end"; result = String(result), turns = b["turns"], damage_dealt = b["damage_dealt"],
                damage_taken = b["damage_taken"], hp = b["hp_end"], enemies = b["enemies"])
            result == "won" && (r.context = b["category"] == "boss" ? "boss_reward" : "battle_reward")
        catch ex
            @debug "RunRecorder.battle_end!: $ex"
        end
        return nothing
    end

    _battle() = STATE[].current_battle

    """Mirror of `AnalyticsModule.track_action` so existing counters feed the current battle."""
    function on_action!(action::Symbol, value::Int = 1)
        try
            b = _battle()
            if action == :damage_dealt
                b === nothing && return nothing
                _bump!(b, "damage_dealt", value)
                b["max_hit"] = max(b["max_hit"], value)
            elseif action == :damage_received
                b === nothing && return nothing
                _bump!(b, "damage_taken", value)
            elseif action == :combo_length
                b === nothing && return nothing
                b["max_combo"] = max(b["max_combo"], value)
            elseif action == :turn_taken
                b === nothing || _bump!(b, "turns", value)
            elseif action == :switch_used
                b === nothing || _bump!(b, "swaps", value)
                add_total!("swaps", value)
            elseif action == :drag_used
                b === nothing || _bump!(b, "queue_placements", value)
                add_total!("queue_placements", value)
            elseif action == :reroll_used
                b === nothing || _bump!(b, "rerolls", value)
                add_total!("queue_rerolls", value)
            elseif action == :enemy_killed
                b === nothing || _bump!(b, "kills", value)
            elseif action == :gold_spent
                add_total!("gold_spent", value)
            elseif action == :event_won
                add_total!("events_accepted", value)
            elseif action == :event_ignored
                add_total!("events_declined", value)
            end
        catch e
            @debug "RunRecorder.on_action!($action): $e"
        end
        return nothing
    end

    """One connected match resolved (including ones captured by the Sealed Envelope)."""
    function note_match!(piece::AbstractString, count::Integer)
        try
            _ensure_started!()
            key = String(piece)
            stats = _item_stats("pieces", key)
            _bump!(stats, "matched")
            _bump!(stats, "count_total", count)
            b = _battle()
            if b !== nothing
                m = get!(b["matches"], key) do
                    Dict{String, Any}("times" => 0, "count" => 0)
                end
                _bump!(m, "times")
                _bump!(m, "count", count)
            end
        catch e
            @debug "RunRecorder.note_match!: $e"
        end
        return nothing
    end

    function note_ability!(treasure_key::AbstractString)
        try
            _ensure_started!()
            key = String(treasure_key)
            _bump!(_item_stats("abilities", key), "used")
            haskey(STATE[].items["treasures"], key) && _bump!(STATE[].items["treasures"][key], "triggers")
            b = _battle()
            b === nothing || _bump!(b["abilities"], key)
            record!("ability_used"; key = key)
        catch e
            @debug "RunRecorder.note_ability!: $e"
        end
        return nothing
    end

    """`how` is "used", "sold" or "discarded"."""
    function note_potion!(potion_key::AbstractString, how::AbstractString = "used")
        try
            _ensure_started!()
            key = String(potion_key)
            _bump!(_item_stats("potions", key), String(how))
            b = _battle()
            (how == "used" && b !== nothing) && _bump!(b["potions"], key)
            record!("potion_$(how)"; key = key, in_battle = b !== nothing)
        catch e
            @debug "RunRecorder.note_potion!: $e"
        end
        return nothing
    end

    function note_death_prevented!(source::AbstractString)
        try
            b = _battle()
            b === nothing || _bump!(b, "death_prevented")
            record!("death_prevented"; source = String(source))
        catch e
            @debug "RunRecorder.note_death_prevented!: $e"
        end
        return nothing
    end

    # ---------------------------------------------------------------- snapshot / payload

    function snapshot_loadout()
        user = _user()
        psm = _psm()
        r = STATE[]
        stat(name) = _int(_prop(user, name, 0))
        treasures = Dict{String, Any}[]
        for k in _keys_of(_prop(user, :treasures, nothing))
            s = get(r.items["treasures"], k, Dict{String, Any}())
            push!(treasures, Dict{String, Any}(
                "key" => k,
                "source" => get(s, "source", "unknown"),
                "floor" => get(s, "floor", nothing),
                "node" => get(s, "node", nothing),
                "triggers" => get(s, "triggers", 0),
            ))
        end
        pieces = Dict{String, Any}[]
        for p in something(_prop(user, :pieces, nothing), [])
            p === nothing && continue
            push!(pieces, Dict{String, Any}("key" => string(_prop(p, :key, "")), "weight" => _weight(p)))
        end
        return Dict{String, Any}(
            "character" => string(_prop(user, :selectedCharacter, r.character)),
            "stats" => Dict{String, Any}(
                "health" => stat(:health), "max_health" => stat(:maxHealth),
                "shield" => stat(:shield), "max_shield" => stat(:maxShield),
                "attack" => stat(:attack), "base_attack" => stat(:base_attack), "defense" => stat(:defense),
                "speed" => stat(:speed), "luck" => stat(:luck), "gold" => stat(:gold),
                "dodge_chance" => stat(:dodge_chance), "reflect_chance" => stat(:reflect_chance),
            ),
            "treasures" => treasures,
            "pieces" => pieces,
            "potions" => _keys_of(_prop(user, :potions, nothing)),
            "floor" => _int(_prop(psm, :currentFloor, 0)),
            "node" => _int(_prop(psm, :currentLevel, 0)),
            "room" => _int(_prop(psm, :currentRoom, 0)),
            "elapsed" => round(Float64(_prop(psm, :runElapsedTime, 0.0)); digits = 1),
        )
    end

    """
    Columns for the Runs row. `outcome` is "won", "died" or "abandoned".
    Pass `loadout` to use a saved snapshot instead of live state (abandoned runs).
    """
    function build_payload(outcome::AbstractString; loadout = nothing)
        live = loadout === nothing
        live && _ensure_started!()
        r = STATE[]
        live && _sync!()
        if r.current_battle !== nothing
            if live
                battle_end!(outcome)
            else
                r.current_battle["result"] = String(outcome)
                push!(r.battles, r.current_battle)
                r.current_battle = nothing
            end
        end
        snap = live ? snapshot_loadout() : loadout
        live && record!("run_end"; outcome = String(outcome))

        last_battle = isempty(r.battles) ? nothing : r.battles[end]
        died = outcome == "died"
        return Dict{String, Any}(
            "run_uuid" => r.run_uuid,
            "game_version" => r.game_version,
            "outcome" => String(outcome),
            "seed" => r.seed,
            "character_key" => string(get(snap, "character", r.character)),
            "final_floor" => _int(get(snap, "floor", 0)),
            "death_floor" => died ? _int(get(snap, "floor", 0)) : nothing,
            "death_enemies" => (died && last_battle !== nothing) ? join(last_battle["enemies"], ",") : nothing,
            "loadout" => snap,
            "timeline" => r.timeline,
            "battles" => r.battles,
            "item_stats" => Dict{String, Any}(
                "treasures" => r.items["treasures"],
                "potions" => r.items["potions"],
                "abilities" => r.items["abilities"],
                "pieces" => r.items["pieces"],
                "totals" => r.totals,
                "dropped_events" => r.dropped_events,
                "started_at" => r.started_at,
            ),
        )
    end

    # ---------------------------------------------------------------- save / load

    function to_save()
        is_active() || return nothing
        r = STATE[]
        return Dict{String, Any}(
            "run_uuid" => r.run_uuid, "started_at" => r.started_at, "game_version" => r.game_version,
            "seed" => r.seed, "character" => r.character, "context" => r.context,
            "timeline" => r.timeline, "dropped_events" => r.dropped_events,
            "battles" => r.battles, "current_battle" => r.current_battle,
            "items" => r.items, "totals" => r.totals,
            "known_treasures" => r.known_treasures, "known_pieces" => r.known_pieces,
            "known_potions" => r.known_potions, "known_gold" => r.known_gold,
            "loadout" => snapshot_loadout(),
        )
    end

    _plain(x::AbstractDict) = Dict{String, Any}(string(k) => _plain(v) for (k, v) in pairs(x))
    _plain(x::AbstractVector) = Any[_plain(v) for v in x]
    _plain(x) = x

    """Restore from a save payload section. Missing/legacy data leaves a fresh (lazily started) record."""
    function from_save!(raw)
        reset!()
        raw === nothing && return false
        try
            d = _plain(raw)
            r = _new_record()
            r.run_uuid = string(get(d, "run_uuid", ""))
            r.started_at = string(get(d, "started_at", ""))
            r.game_version = string(get(d, "game_version", ""))
            r.seed = _int(get(d, "seed", 0))
            r.character = string(get(d, "character", ""))
            r.context = string(get(d, "context", "resumed"))
            r.timeline = Dict{String, Any}[e for e in get(d, "timeline", Any[]) if e isa AbstractDict]
            r.dropped_events = _int(get(d, "dropped_events", 0))
            r.battles = Dict{String, Any}[b for b in get(d, "battles", Any[]) if b isa AbstractDict]
            cb = get(d, "current_battle", nothing)
            r.current_battle = cb isa AbstractDict ? cb : nothing
            items = get(d, "items", Dict{String, Any}())
            for kind in keys(r.items)
                v = get(items, kind, nothing)
                v isa AbstractDict && (r.items[kind] = v)
            end
            r.totals = Dict{String, Int}(k => _int(v) for (k, v) in get(d, "totals", Dict{String, Any}()))
            r.known_treasures = String[string(k) for k in get(d, "known_treasures", Any[])]
            r.known_pieces = Dict{String, Vector{Float64}}(
                k => Float64[Float64(x) for x in v] for (k, v) in get(d, "known_pieces", Dict{String, Any}()))
            r.known_potions = Dict{String, Int}(k => _int(v) for (k, v) in get(d, "known_potions", Dict{String, Any}()))
            r.known_gold = _int(get(d, "known_gold", 0))
            STATE[] = r
            return is_active()
        catch e
            @warn "RunRecorder: could not restore from save" exception = e
            reset!()
            return false
        end
    end

    """Payload for a run that was abandoned (saved, then replaced by a new run). `raw` is the saved section."""
    function abandoned_payload(raw)
        from_save!(raw) || return nothing
        d = _plain(raw)
        loadout = get(d, "loadout", nothing)
        loadout isa AbstractDict || return nothing
        payload = build_payload("abandoned"; loadout = loadout)
        reset!()
        return payload
    end

    export start_run!, reset!, record!, set_context!, node_selected!, battle_start!, battle_end!,
        on_action!, note_match!, note_ability!, note_potion!, note_death_prevented!, add_total!,
        snapshot_loadout, build_payload, to_save, from_save!, abandoned_payload, is_active
end
