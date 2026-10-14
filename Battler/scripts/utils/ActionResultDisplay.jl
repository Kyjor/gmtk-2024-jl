module ActionResultDisplayModule
    using JulGame
    include("DisplayText.jl")
    using .DisplayTextModule
    include("Easings.jl")

    const CHIP_POP = 0.18
    const CHIP_HOLD = 1.17
    const CHIP_FADE = 0.45
    const CHIP_LIFE = CHIP_POP + CHIP_HOLD + CHIP_FADE
    const CHIP_CRIT_LIFE = 2.10
    const BASE_Y = -140.0
    const ROW_H = 68.0
    const RISE_HOLD = 52.0
    const RISE_FADE = 28.0
    const SPAWN_STAGGER = 0.07
    const MAX_VISIBLE = 3
    const EVICT_FADE = 0.18
    const STACK_FOLLOW = 14.0
    const ICON_SIZE = 128
    const COUNT_FS = 40
    const VALUE_FS = 60
    const VALUE_FS_CRIT = 72
    const STATUS_FS = 48
    const GAP_COUNT = 12.0
    const GAP_ICON = 16.0
    const LAYER = 30
    const RENDER_LIFETIME_MS = 100
    const PLAYER_ENTITY_ID = "95b3f5d9-a580-4a15-b745-9ecf1fc76620"
    const HEART_GAP = 8.0
    const HEART_HALF_FALLBACK = 48.0
    const COLOR_COUNT = (215, 210, 195, 255)
    const COLOR_DAMAGE = (255, 120, 120, 255)
    const COLOR_CRIT = (255, 80, 80, 255)
    const COLOR_HEAL = (120, 255, 140, 255)
    const COLOR_SHIELD = (120, 200, 255, 255)
    const COLOR_GOLD = (255, 210, 80, 255)

    const ICON_NATIVE = Dict{String, Tuple{Int, Int}}()

    function _png_size(full::String)::Tuple{Int, Int}
        open(full, "r") do io
            read(io, 16)
            b = read(io, 8)
            length(b) < 8 && return (0, 0)
            w = (Int(b[1]) << 24) | (Int(b[2]) << 16) | (Int(b[3]) << 8) | Int(b[4])
            h = (Int(b[5]) << 24) | (Int(b[6]) << 16) | (Int(b[7]) << 8) | Int(b[8])
            return (w, h)
        end
    end

    function _native_icon_size(path::String)::Tuple{Int, Int}
        haskey(ICON_NATIVE, path) && return ICON_NATIVE[path]
        wh = (0, 0)
        try
            wh = _png_size(joinpath(JulGame.BasePath, "assets", "images", path))
        catch
        end
        ICON_NATIVE[path] = wh
        return wh
    end

    """Height matches the square chip icons. Width follows the file's aspect."""
    function _icon_draw_size(path::String, target_h::Int)::Tuple{Float64, Float64}
        h = Float64(target_h)
        nw, nh = _native_icon_size(path)
        (nw <= 0 || nh <= 0) && return (h, h)
        return (max(1.0, h * nw / nh), h)
    end

    mutable struct SourceContext
        piece_key::String
        match_count::Int
        active::Bool
    end

    mutable struct ResultChip
        id::Int
        entity::Any
        kind::Symbol
        value_text::String
        color::NTuple{4, Int}
        piece_key::String
        icon::String
        badge::String
        match_count::Int
        crit::Bool
        slot::Int
        base_y::Float64
        y::Float64
        delay::Float64
        elapsed::Float64
        life::Float64
        evicting::Bool
        evict_elapsed::Float64
        parent_lost::Bool
        frozen_x::Float64
        frozen_y::Float64
        heart::Any       # combatant's health heart; chips hang below it and drift down
        dir::Float64     # -1 drifts/stacks up from the entity, +1 down from the heart
    end

    const SOURCE = SourceContext("", 0, false)
    const CHIPS = ResultChip[]
    const NEXT_ID = Ref(1)

    function set_source!(piece_key, match_count)
        SOURCE.piece_key = String(piece_key)
        SOURCE.match_count = Int(match_count)
        SOURCE.active = true
    end

    function clear_source!()
        SOURCE.active = false
        SOURCE.piece_key = ""
        SOURCE.match_count = 0
    end

    function reset!()
        empty!(CHIPS)
        clear_source!()
    end

    function _resolve_entity(target)
        target === nothing && return nothing
        try
            if hasproperty(target, :sprite) && target.sprite !== nothing
                return target
            end
        catch
        end
        try
            if hasproperty(target, :parent) && target.parent !== nothing
                return target.parent
            end
        catch
        end
        return target
    end

    function _entity_key(entity)
        try
            return objectid(entity)
        catch
            return 0
        end
    end

    function _entity_sprite(entity)
        try
            return entity.sprite
        catch
            return nothing
        end
    end

    function _heart_of(entity)
        try
            for s in entity.scripts
                hasproperty(s, :healthHeart) && s.healthHeart !== nothing && return s.healthHeart
            end
        catch
        end
        try
            if string(entity.id) == PLAYER_ENTITY_ID
                return JulGame.UserGlobals["Module"].get_user_data().healthHeart
            end
        catch
        end
        return nothing
    end

    function _heart_half_h(sprite)::Float64
        try
            sz = sprite.lastRenderedScreenSize
            sz !== nothing && return Float64(sz.y) / 2.0
        catch
        end
        return HEART_HALF_FALLBACK
    end

    function _icon_path(piece_key::String)::String
        isempty(piece_key) && return ""
        parts = split(lowercase(piece_key), "_")
        length(parts) < 2 && return ""
        try
            return JulGame.UserGlobals["Module"].get_asset_path(String(parts[1]), String(parts[2]))
        catch
            return ""
        end
    end

    function _text_w(s::String, fontSize::Int)::Float64
        return length(s) * fontSize * 0.56
    end

    function _value_text(kind::Symbol, value, crit::Bool)::String
        if kind == :status
            return String(value)
        end
        n = value isa Integer ? Int(value) : try
            Int(round(Float64(value)))
        catch
            0
        end
        kind == :damage && return crit ? "-$(n)!" : "-$(n)"
        n < 0 && return "-$(abs(n))"
        return "+$(n)"
    end

    function _value_color(kind::Symbol, crit::Bool, color)
        color !== nothing && return color
        kind == :heal && return COLOR_HEAL
        kind == :shield && return COLOR_SHIELD
        kind == :gold && return COLOR_GOLD
        kind == :damage && return crit ? COLOR_CRIT : COLOR_DAMAGE
        return COLOR_COUNT
    end

    function _chip_icon(chip::ResultChip)::String
        !isempty(chip.icon) && return chip.icon
        return _icon_path(chip.piece_key)
    end

    function _chips_for(entity)
        key = _entity_key(entity)
        return (c for c in CHIPS if _entity_key(c.entity) == key)
    end

    function push(target; kind::Symbol = :damage, value = 0, piece_key = nothing, match_count = nothing, crit::Bool = false, color = nothing, icon = nothing, badge = nothing, base_y = nothing)
        entity = _resolve_entity(target)
        entity === nothing && return

        pk = piece_key === nothing ? (SOURCE.active ? SOURCE.piece_key : "") : String(piece_key)
        ic = icon === nothing ? "" : String(icon)
        bd = badge === nothing ? "" : String(badge)
        mc = match_count === nothing ? (SOURCE.active ? SOURCE.match_count : 0) : Int(match_count)
        if mc <= 1
            mc = 0
        end

        waiting = count(c -> _entity_key(c.entity) == _entity_key(entity) && (c.delay > 0.0 || c.elapsed <= 0.0) && !c.evicting, CHIPS)
        for c in _chips_for(entity)
            c.slot += 1
        end

        live = count(c -> _entity_key(c.entity) == _entity_key(entity) && !c.evicting, CHIPS)
        if live >= MAX_VISIBLE
            oldest = nothing
            oldest_slot = -1
            for c in _chips_for(entity)
                (!c.evicting && c.slot > oldest_slot) || continue
                oldest = c
                oldest_slot = c.slot
            end
            if oldest !== nothing
                oldest.evicting = true
                oldest.evict_elapsed = 0.0
            end
        end

        life = crit ? CHIP_CRIT_LIFE : CHIP_LIFE
        heart = base_y === nothing ? _heart_of(entity) : nothing
        origin_y = base_y !== nothing ? Float64(base_y) : heart !== nothing ? HEART_GAP + ICON_SIZE / 2.0 : BASE_Y
        chip = ResultChip(
            NEXT_ID[],
            entity,
            kind,
            _value_text(kind, value, crit),
            _value_color(kind, crit, color),
            pk,
            ic,
            bd,
            mc,
            crit,
            0,
            origin_y,
            origin_y,
            waiting * SPAWN_STAGGER,
            0.0,
            life,
            false,
            0.0,
            false,
            0.0,
            0.0,
            heart,
            heart === nothing ? -1.0 : 1.0,
        )
        NEXT_ID[] += 1
        push!(CHIPS, chip)
    end

    function _hold_duration(chip::ResultChip)::Float64
        extra = chip.life - CHIP_LIFE
        return CHIP_HOLD + max(0.0, extra)
    end

    function _motion(chip::ResultChip)
        if chip.evicting
            t = clamp(chip.evict_elapsed / EVICT_FADE, 0.0, 1.0)
            fade = ease_in_quad(t)
            hold_end_rise = -RISE_HOLD
            return (1.0 - 0.06 * t, Int(round(255 * (1.0 - fade))), hold_end_rise)
        end

        e = chip.elapsed
        pop_end = CHIP_POP
        hold_end = pop_end + _hold_duration(chip)
        if e <= pop_end
            t = pop_end <= 0.0 ? 1.0 : e / pop_end
            scale = 0.60 + 0.40 * ease_out_back(t)
            alpha = Int(round(255 * clamp(e / 0.08, 0.0, 1.0)))
            return (scale, alpha, 0.0)
        elseif e <= hold_end
            t = (e - pop_end) / max(_hold_duration(chip), 0.001)
            return (1.0, 255, -RISE_HOLD * ease_out_quart(t))
        else
            t = (e - hold_end) / max(CHIP_FADE, 0.001)
            t = clamp(t, 0.0, 1.0)
            return (1.0 - 0.06 * t, Int(round(255 * (1.0 - ease_in_quad(t)))), -RISE_HOLD - RISE_FADE * t)
        end
    end

    function _tick_chip!(chip::ResultChip, dt::Float64)::Bool
            if chip.delay > 0.0
            chip.delay -= dt
            if chip.delay > 0.0
                slot_y = chip.base_y + chip.dir * chip.slot * ROW_H
                chip.y += (slot_y - chip.y) * (1.0 - exp(-STACK_FOLLOW * dt))
                return true
            end
            chip.delay = 0.0
        end

        if chip.evicting
            chip.evict_elapsed += dt
        else
            chip.elapsed += dt
        end

        slot_y = chip.base_y + chip.dir * chip.slot * ROW_H
        chip.y += (slot_y - chip.y) * (1.0 - exp(-STACK_FOLLOW * dt))

        chip.evicting && chip.evict_elapsed >= EVICT_FADE && return false
        !chip.evicting && chip.elapsed >= chip.life && return false
        return true
    end

    _anchor(chip::ResultChip) = chip.heart === nothing ? chip.entity : chip.heart

    function _snapshot_parent!(chip::ResultChip)
        chip.parent_lost && return
        try
            pos = _anchor(chip).transform.position
            chip.frozen_x = Float64(pos.x) * 64.0
            chip.frozen_y = Float64(pos.y) * 64.0
            chip.parent_lost = true
        catch
            chip.parent_lost = true
        end
    end

    function _draw_chip!(chip::ResultChip)
        chip.delay > 0.0 && return
        scale, alpha, rise = _motion(chip)
        alpha <= 0 && return

        sprite = _entity_sprite(_anchor(chip))
        if sprite === nothing
            _snapshot_parent!(chip)
        end

        show_count = chip.match_count > 1
        count_text = show_count ? "x$(chip.match_count)" : ""
        icon_path = _chip_icon(chip)
        badge_path = chip.badge
        value_fs = chip.kind == :status ? STATUS_FS : (chip.crit ? VALUE_FS_CRIT : VALUE_FS)
        fs_count = max(1, round(Int, COUNT_FS * scale))
        fs_value = max(1, round(Int, value_fs * scale))
        icon_h = max(1, round(Int, ICON_SIZE * scale))

        count_w = show_count ? _text_w(count_text, fs_count) : 0.0
        icon_w, icon_draw_h = icon_path == "" ? (0.0, 0.0) : _icon_draw_size(icon_path, icon_h)
        badge_w, badge_draw_h = badge_path == "" ? (0.0, 0.0) : _icon_draw_size(badge_path, icon_h)
        value_w = _text_w(chip.value_text, fs_value)
        total = value_w
        show_count && (total += count_w + GAP_COUNT)
        if icon_path != ""
            total += icon_w + GAP_ICON
        elseif show_count && badge_path == ""
            total += GAP_ICON
        end
        badge_path != "" && (total += badge_w + GAP_ICON)
        x = -total / 2.0
        # `rise` is negative (upward); heart chips mirror it to drift down below the heart.
        y = chip.y - chip.dir * rise
        if chip.heart !== nothing && sprite !== nothing
            y += _heart_half_h(sprite)
        end
        a = clamp(alpha, 0, 255)
        count_color = (COLOR_COUNT[1], COLOR_COUNT[2], COLOR_COUNT[3], a)
        value_color = (chip.color[1], chip.color[2], chip.color[3], a)
        icon_color = (255, 255, 255, a)

        parent = sprite
        use_frozen = parent === nothing && chip.parent_lost
        origin_x = use_frozen ? chip.frozen_x : 0.0
        origin_y = use_frozen ? chip.frozen_y : 0.0

        function place_text(id, text, px, fontSize, color)
            if use_frozen
                DisplayTextModule.display_text(
                    id, text;
                    fontSize = fontSize,
                    anchor = :none,
                    position = Math.Vector2(origin_x + px, origin_y + y),
                    color = color,
                    layer = LAYER,
                    lifetime = RENDER_LIFETIME_MS,
                )
            else
                DisplayTextModule.display_text(
                    id, text;
                    fontSize = fontSize,
                    anchor = :center,
                    anchorOffset = Math.Vector2(px + _text_w(text, fontSize) / 2.0, y),
                    parent = parent,
                    color = color,
                    layer = LAYER,
                    lifetime = RENDER_LIFETIME_MS,
                )
            end
        end

        function place_icon(id, path, px, draw_w, draw_h)
            draw_size = Math.Vector2(draw_w, draw_h)
            img = if use_frozen
                JulGame.ImmediateUIModule.immediate_image(
                    id, path;
                    anchor = :none,
                    position = Math.Vector2(origin_x + px, origin_y + y - draw_h / 2.0),
                    size = draw_size,
                    color = icon_color,
                    layer = LAYER,
                    lifetime = RENDER_LIFETIME_MS,
                )
            else
                JulGame.ImmediateUIModule.immediate_image(
                    id, path;
                    parent = parent,
                    anchor = :center,
                    anchorOffset = Math.Vector2(px + draw_w / 2.0, y),
                    size = draw_size,
                    color = icon_color,
                    layer = LAYER,
                    lifetime = RENDER_LIFETIME_MS,
                )
            end
            # Render uses originalSize, which load_image freezes on the first square.
            if img !== nothing
                img.size = draw_size
                img.originalSize = draw_size
            end
        end

        cursor = x
        if show_count
            place_text("ard_$(chip.id)_n", count_text, cursor, fs_count, count_color)
            cursor += count_w + GAP_COUNT
        end
        if icon_path != ""
            place_icon("ard_$(chip.id)_i", icon_path, cursor, icon_w, icon_draw_h)
            cursor += icon_w + GAP_ICON
        elseif show_count && badge_path == ""
            cursor += GAP_ICON
        end
        if badge_path != ""
            place_icon("ard_$(chip.id)_b", badge_path, cursor, badge_w, badge_draw_h)
            cursor += badge_w + GAP_ICON
        end
        place_text("ard_$(chip.id)_v", chip.value_text, cursor, fs_value, value_color)
    end

    function update(deltaTime)
        dt = Float64(deltaTime)
        if dt > 0.0
            keep = ResultChip[]
            for chip in CHIPS
                _tick_chip!(chip, dt) && push!(keep, chip)
            end
            empty!(CHIPS)
            append!(CHIPS, keep)
        end
        for chip in CHIPS
            try
                _draw_chip!(chip)
            catch
            end
        end
        try_flush_move_damage!()
    end

    # Per-enemy total for the current player move. Shown once, after the move's
    # damage has landed, and only when more than one source contributed.
    mutable struct MoveDamageAcc
        total::Int
        sources::Set{String}
        entity::Any
    end

    const MOVE_DMG = Dict{UInt, MoveDamageAcc}()
    const MOVE_DMG_LAST = Ref(0.0)
    const MOVE_DMG_SETTLE = 0.45

    function note_move_damage!(entity, amount, source::String)
        n = try
            Int(amount)
        catch
            0
        end
        n <= 0 && return
        entity === nothing && return
        src = isempty(source) ? "hit" : source
        if src != "combo_star" && _enemy_turn_active()
            return
        end
        key = _entity_key(entity)
        acc = get!(MOVE_DMG, key) do
            MoveDamageAcc(0, Set{String}(), entity)
        end
        acc.total += n
        push!(acc.sources, src)
        acc.entity = entity
        MOVE_DMG_LAST[] = time()
    end

    function _enemy_turn_active()::Bool
        try
            bm = JulGame.UserGlobals["Module"].get_data_manager().current_battle_manager
            bm === nothing && return false
            return bm.currentState == bm.battleStates[:enemyTurn]
        catch
            return false
        end
    end

    function _move_damage_still_resolving()::Bool
        try
            bm = JulGame.UserGlobals["Module"].get_data_manager().current_battle_manager
            if bm !== nothing
                st = bm.currentState
                bs = bm.battleStates
                if st == bs[:switchingItems] || st == bs[:searchingForMatches] ||
                   st == bs[:replaceItems] || st == bs[:animatingIntents] || st == bs[:playerAction]
                    return true
                end
                if !isempty(bm.activeAnimations)
                    return true
                end
            end
        catch
        end
        try
            stars = parentmodule(parentmodule(@__MODULE__)).ComboStarsModule.STATE.stars
            return any(s -> s.phase == :flying || s.phase == :leaving, stars)
        catch
            return false
        end
    end

    function try_flush_move_damage!()
        isempty(MOVE_DMG) && return
        _move_damage_still_resolving() && return
        time() - MOVE_DMG_LAST[] < MOVE_DMG_SETTLE && return
        pending = collect(values(MOVE_DMG))
        empty!(MOVE_DMG)
        for acc in pending
            length(acc.sources) > 1 || continue
            acc.total <= 0 && continue
            push(acc.entity; kind = :status, value = "Total -$(acc.total)", color = COLOR_DAMAGE)
        end
    end

    export set_source!, clear_source!, push, update, reset!, note_move_damage!
end
