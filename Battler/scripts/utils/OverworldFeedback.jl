module OverworldFeedbackModule
    using JulGame
    include("ActionResultDisplay.jl")
    using .ActionResultDisplayModule

    const COLOR_GOLD = (255, 210, 80, 255)
    const COLOR_ATTACK = (255, 170, 90, 255)
    const COLOR_DEFENSE = (120, 200, 255, 255)
    const COLOR_LUCK = (230, 140, 255, 255)
    const COLOR_MAXHP = (120, 255, 200, 255)
    const COLOR_POTION = (200, 160, 255, 255)
    const COLOR_ITEM = (220, 210, 180, 255)

    const PLAYER_REF = Ref{Any}(nothing)
    const HIT_FLASH = (255, 80, 80, 255)
    const HEAL_FLASH = (150, 255, 170, 255)
    const HIT_DURATION = 0.3
    const HIT_SHAKE = 0.18

    mutable struct HitReact
        entity::Any
        original_color::NTuple{4, Int}
        original_position::Any
        flash_color::NTuple{4, Int}
        shake::Float64
        elapsed::Float64
    end

    const HIT = Ref{Union{Nothing, HitReact}}(nothing)

    function set_player!(entity)
        PLAYER_REF[] = entity
    end

    function player_entity()
        target = PLAYER_REF[]
        target !== nothing && return target
        try
            return JulGame.SceneModule.get_entity_by_name("Player")
        catch
            return nothing
        end
    end

    function _chip_base_y(entity)
        try
            sprite = entity.sprite
            sz = nothing
            try
                sz = sprite.lastRenderedScreenSize
            catch
            end
            h = 0.0
            if sz !== nothing
                h = Float64(sz.y)
            end
            if h <= 1.0
                h = Float64(sprite.size.y)
            end
            # Sit above the avatar, next to the event HP heart (centerTop -82).
            return -(h * 0.5) - 110.0
        catch
            return -350.0
        end
    end

    function _asset(asset_type::String, asset_name::String, fallback::String = "")::String
        try
            path = JulGame.UserGlobals["Module"].get_asset_path(asset_type, asset_name)
            return isempty(path) ? fallback : path
        catch
            return fallback
        end
    end

    function _key_name(key)::String
        key === nothing && return ""
        parts = split(lowercase(String(key)), "_")
        return length(parts) >= 2 ? String(parts[2]) : String(parts[1])
    end

    function _sfx(name::String; volume::Float64 = 1.0)
        try
            g = JulGame.UserGlobals["Module"]
            g.AudioManagerModule.play_audio_oneshot(
                g.get_audio_manager(),
                g.get_asset_path("sfx", name),
                false,
                volume,
                0,
                1,
            )
        catch
        end
    end

    function _push(; kwargs...)
        target = player_entity()
        target === nothing && return
        ActionResultDisplayModule.push(target; base_y = _chip_base_y(target), kwargs...)
    end

    function gold!(amount; sfx::Bool = true)
        n = Int(amount)
        n == 0 && return
        _push(; kind = :gold, value = n, icon = _asset("ui", "money", JulGame.UserGlobals["Module"].get_asset_path("ui", "money")), color = COLOR_GOLD)
        sfx || return
        if n < 0
            _sfx("coin")
        else
            name = n <= 10 ? "getmoneyalittle" : n <= 20 ? "getmoneyagoodbit" : n <= 30 ? "getmoneyalot" : "getmoneyamillion"
            _sfx(name)
        end
    end

    function heal!(amount; sfx::Bool = true, icon = nothing)
        n = Int(amount)
        n <= 0 && return
        _push(; kind = :heal, value = n, icon = something(icon, _asset("piece", "potion", JulGame.UserGlobals["Module"].get_asset_path("piece", "potion"))))
        _hit_react!(HEAL_FLASH, 0.0)
        sfx && _sfx(n >= 15 ? "healbig" : "healsmall")
    end

    function _sprite_color(sprite)::NTuple{4, Int}
        c = sprite.color
        return (Int(c[1]), Int(c[2]), Int(c[3]), Int(c[4]))
    end

    function _finish_hit!()
        hit = HIT[]
        hit === nothing && return
        try
            hit.entity.sprite.color = hit.original_color
        catch
        end
        try
            hit.entity.transform.position = hit.original_position
        catch
        end
        HIT[] = nothing
    end

    function _hit_react!(flash::NTuple{4, Int}, shake::Float64)
        try
            entity = player_entity()
            entity === nothing && return
            _finish_hit!()
            sprite = entity.sprite
            (sprite === nothing || sprite == C_NULL) && return
            pos = entity.transform.position
            HIT[] = HitReact(
                entity,
                _sprite_color(sprite),
                JulGame.Math.Vector3f(pos.x, pos.y, pos.z),
                flash,
                shake,
                0.0,
            )
        catch
        end
    end

    function _update_hit!(deltaTime)
        hit = HIT[]
        hit === nothing && return
        hit.elapsed += Float64(deltaTime)
        progress = min(hit.elapsed / HIT_DURATION, 1.0)
        t = sin(progress * π)
        try
            o = hit.original_color
            f = hit.flash_color
            hit.entity.sprite.color = (
                Int(round(o[1] * (1 - t) + f[1] * t)),
                Int(round(o[2] * (1 - t) + f[2] * t)),
                Int(round(o[3] * (1 - t) + f[3] * t)),
                o[4],
            )
        catch
        end
        intensity = hit.shake * (1.0 - progress)
        try
            p = hit.original_position
            hit.entity.transform.position = JulGame.Math.Vector3f(
                p.x + (rand() - 0.5) * 2.0 * intensity,
                p.y + (rand() - 0.5) * 2.0 * intensity,
                p.z,
            )
        catch
        end
        progress >= 1.0 && _finish_hit!()
    end

    function damage!(amount; sfx::Bool = true)
        n = Int(amount)
        n <= 0 && return
        _push(; kind = :damage, value = n, icon = _asset("piece", "skull", JulGame.UserGlobals["Module"].get_asset_path("piece", "skull")))
        _hit_react!(HIT_FLASH, HIT_SHAKE)
        sfx && _sfx("damagenormal$(rand(1:6))")
    end

    function potion!(amount = 1; key = nothing, sfx::Bool = true)
        n = Int(amount)
        n <= 0 && return
        icon = key === nothing ? _asset("piece", "potion", JulGame.UserGlobals["Module"].get_asset_path("piece", "potion")) : _asset("potion", _key_name(key), JulGame.UserGlobals["Module"].get_asset_path("piece", "potion"))
        _push(; kind = :heal, value = n, icon = icon, color = COLOR_POTION)
        sfx && _sfx("potionhover1")
    end

    function attack!(amount; sfx::Bool = true)
        n = Int(amount)
        n == 0 && return
        _push(; kind = n < 0 ? :damage : :heal, value = abs(n), icon = _asset("piece", "sword", JulGame.UserGlobals["Module"].get_asset_path("piece", "sword")), color = COLOR_ATTACK)
        sfx && _sfx("piecesword")
    end

    function defense!(amount; sfx::Bool = true)
        n = Int(amount)
        n == 0 && return
        _push(; kind = :shield, value = abs(n), icon = _asset("piece", "shield", JulGame.UserGlobals["Module"].get_asset_path("piece", "shield")), color = COLOR_DEFENSE)
        sfx && _sfx("pieceshield")
    end

    function max_hp!(amount; sfx::Bool = true)
        n = Int(amount)
        n == 0 && return
        icon = n < 0 ? _asset("status", "arrowdebuff", JulGame.UserGlobals["Module"].get_asset_path("status", "arrowdebuff")) : _asset("status", "arrowbuff", JulGame.UserGlobals["Module"].get_asset_path("status", "arrowbuff"))
        _push(; kind = n < 0 ? :damage : :heal, value = abs(n), icon = icon, color = COLOR_MAXHP)
        sfx && (n < 0 ? _sfx("damagenormal1") : _sfx("healsmall"))
    end

    function luck!(amount; sfx::Bool = true)
        n = Int(amount)
        n == 0 && return
        _push(; kind = :heal, value = n, icon = _asset("piece", "lucky", JulGame.UserGlobals["Module"].get_asset_path("piece", "lucky")), color = COLOR_LUCK)
        sfx && _sfx("pieceluck")
    end

    function treasure!(item; sfx::Bool = true)
        item === nothing && return
        key = try
            item.key
        catch
            nothing
        end
        icon = key === nothing ? "" : _asset("treasure", _key_name(key), "")
        _push(; kind = :status, value = "+", icon = icon, color = COLOR_ITEM)
        sfx && _sfx("getmoneyagoodbit")
    end

    function piece!(item; sfx::Bool = true)
        item === nothing && return
        key = try
            item.key
        catch
            nothing
        end
        icon = key === nothing ? "" : _asset("piece", _key_name(key), JulGame.UserGlobals["Module"].get_asset_path("piece", "sword"))
        _push(; kind = :status, value = "+", icon = icon, color = COLOR_ITEM)
        sfx && _sfx("piecesword")
    end

    # Same pulse and enter-wobble as a selected board piece.
    const SALE_HOVER = WeakKeyDict{Any, Tuple{Any, Float64}}()
    const SALE_PULSE_AMOUNT = 0.07
    const SALE_PULSE_SPEED = 5.5
    const SALE_WOBBLE_AMOUNT = 0.03
    const SALE_WOBBLE_DURATION = 0.25

    function _sale_scale!(entity, s::Float64)
        entity === nothing && return
        try
            entity.sprite.renderScale = JulGame.Math.Vector2f(s, s)
        catch
        end
    end

    function update_sale_hover!(owner, entity, deltaTime)
        prev_entity, pulse = get(SALE_HOVER, owner, (nothing, 0.0))
        if prev_entity !== entity
            if prev_entity !== nothing
                try
                    parentmodule(OverworldFeedbackModule).BattleManagerModule.BattleJuiceModule.cancel_shake!(prev_entity)
                catch
                end
                _sale_scale!(prev_entity, 1.0)
            end
            pulse = 0.0
            if entity !== nothing
                try
                    parentmodule(OverworldFeedbackModule).BattleManagerModule.BattleJuiceModule.shake!(
                        entity;
                        intensity = SALE_WOBBLE_AMOUNT,
                        duration = SALE_WOBBLE_DURATION,
                        wobble = true,
                    )
                catch
                end
            end
        end
        if entity !== nothing
            pulse += Float64(deltaTime)
            _sale_scale!(entity, 1.0 + SALE_PULSE_AMOUNT * sin(pulse * SALE_PULSE_SPEED))
        end
        SALE_HOVER[owner] = (entity, pulse)
    end

    function update(deltaTime)
        _update_hit!(deltaTime)
        ActionResultDisplayModule.update(deltaTime)
    end

    function reset!()
        for (_, pair) in SALE_HOVER
            _sale_scale!(pair[1], 1.0)
        end
        empty!(SALE_HOVER)
        _finish_hit!()
        PLAYER_REF[] = nothing
        ActionResultDisplayModule.reset!()
    end

    export gold!, heal!, damage!, potion!, attack!, defense!, max_hp!, luck!, treasure!, piece!, update, reset!, set_player!, update_sale_hover!
end
