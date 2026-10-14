"""
Shared heart-fill reaction. A health drop flashes the lost slice white, then
the fill eases down. A heal flashes the gained slice white, then the fill eases up.
"""
module HeartFillFXModule
    const FLASH_HOLD = 0.12
    const DRAIN_TIME = 0.38
    const HEAL_TIME = 0.28
    # ui-healthheart is a white shape modulated by this tint. While the lost slice
    # is white, modulation is turned off and this tint is baked into the rest.
    const BAKE_TINT = (255, 70, 127)
    const IDLE_COLOR = (255, 70, 127, 255)
    const FLASH_COLOR = (255, 255, 255, 255)

    mutable struct FillState
        shown::Float64
        target::Float64
        from::Float64
        phase::Symbol
        t::Float64
    end

    const STATES = Dict{String, FillState}()

    function _ease(u::Float64)::Float64
        u = clamp(u, 0.0, 1.0)
        return 1.0 - (1.0 - u) ^ 2
    end

    """
    Advance one heart. Returns `(shown_ratio, highlight_below)`.
    `highlight_below >= 0` keeps the wedge between that ratio and `shown_ratio` white.
    Below `shown_ratio` that wedge is health about to be lost. Above it, health about to be gained.
    """
    function present!(id::AbstractString, ratio::Float64, dt::Float64)
        ratio = clamp(Float64(ratio), 0.0, 1.0)
        dt = max(0.0, Float64(dt))
        key = String(id)
        st = get(STATES, key, nothing)
        if st === nothing
            STATES[key] = FillState(ratio, ratio, ratio, :idle, 0.0)
            return (ratio, -1.0)
        end

        if st.phase == :idle
            if abs(ratio - st.shown) > 1e-4
                st.from = st.shown
                st.target = ratio
                st.t = 0.0
                st.phase = :flash
            else
                st.shown = ratio
                st.target = ratio
                return (st.shown, -1.0)
            end
        elseif abs(ratio - st.target) > 1e-4
            st.from = st.shown
            st.target = ratio
            st.t = 0.0
            st.phase = :flash
        end

        st.t += dt
        if st.phase == :flash
            st.shown = st.from
            if st.t < FLASH_HOLD
                return (st.shown, st.target)
            end
            st.phase = st.target < st.from ? :drain : :heal
            st.t = 0.0
        end
        if st.phase == :drain || st.phase == :heal
            duration = st.phase == :drain ? DRAIN_TIME : HEAL_TIME
            u = st.t / duration
            st.shown = st.from + (st.target - st.from) * _ease(u)
            if u >= 1.0
                st.shown = st.target
                st.phase = :idle
                return (st.shown, -1.0)
            end
            return (st.shown, st.target)
        end
        return (st.shown, -1.0)
    end

    export present!
end
