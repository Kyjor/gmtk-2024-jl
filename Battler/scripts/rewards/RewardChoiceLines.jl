# Rough-edged tree lines joining the "Choose wisely" prompt to its options.
# Branch count is a parameter, so a fourth option needs no new drawing code.
module RewardChoiceLinesModule
using JulGame

const SEGMENT_LENGTH = 8.0
const THICKNESS = 4
const JITTER = 1.7
const DEFAULT_COLOR = (236, 231, 216, 255)

# A chalk line should sit still rather than crawl, so the wobble is derived from
# the segment index instead of rand().
function _jitter(seed::Int, index::Int)::Float64
    h = hash((seed, index))
    return (Float64(h % 2000) / 1000.0) - 1.0
end

function _draw_run(id::String, x1::Float64, y1::Float64, x2::Float64, y2::Float64,
                   color::NTuple{4, Int}, alpha::Float64, layer::Int, seed::Int, progress::Float64)
    progress <= 0.0 && return
    dx = x2 - x1
    dy = y2 - y1
    span = sqrt(dx * dx + dy * dy)
    span < 1.0 && return

    a = round(Int, color[4] * clamp(alpha, 0.0, 1.0))
    a <= 0 && return
    segment_color = (color[1], color[2], color[3], a)

    horizontal = abs(dx) >= abs(dy)
    steps = max(1, ceil(Int, span / SEGMENT_LENGTH))
    drawn = clamp(progress, 0.0, 1.0) * steps

    for i in 0:(steps - 1)
        i >= drawn && break
        # Partial trailing segment keeps the draw-on smooth instead of chunky.
        fraction = min(1.0, drawn - i)
        t0 = i / steps
        t1 = (i + fraction) / steps
        ax = x1 + dx * t0
        ay = y1 + dy * t0
        bx = x1 + dx * t1
        by = y1 + dy * t1
        wobble = _jitter(seed, i) * JITTER

        if horizontal
            rect_x = round(Int, min(ax, bx))
            rect_y = round(Int, min(ay, by) + wobble)
            rect_w = max(1, round(Int, abs(bx - ax)) + 1)
            rect_h = THICKNESS
        else
            rect_x = round(Int, min(ax, bx) + wobble)
            rect_y = round(Int, min(ay, by))
            rect_w = THICKNESS
            rect_h = max(1, round(Int, abs(by - ay)) + 1)
        end

        JulGame.ImmediateUIModule.immediate_rect(
            "$(id)_$(i)";
            size = Math.Vector2(rect_w, rect_h),
            anchor = :topLeft,
            anchorOffset = Math.Vector2(rect_x, rect_y),
            color = segment_color,
            layer = layer,
        )
    end
end

"""
Draw the spine plus one branch per option.

`origin` is where the spine starts, under the prompt. `targets` are the points on
each option slot that branches connect to. `branch_progress` drives both the
entry draw-on and the retract on commit; `alphas` dims the branches whose slots
are not hovered.
"""
function draw_choice_tree(
    id::String,
    origin,
    targets;
    spine_progress::Float64 = 1.0,
    branch_progress = nothing,
    alphas = nothing,
    color::NTuple{4, Int} = DEFAULT_COLOR,
    layer::Int = 11,
    seed::Int = 4712,
)
    isempty(targets) && return

    spine_x = Float64(origin.x)
    spine_top = Float64(origin.y)
    spine_bottom = spine_top
    for (i, target) in enumerate(targets)
        progress = branch_progress === nothing ? 1.0 : Float64(branch_progress[i])
        progress <= 0.0 && continue
        spine_bottom = max(spine_bottom, Float64(target.y))
    end

    _draw_run("$(id)_spine", spine_x, spine_top, spine_x, spine_bottom,
              color, 1.0, layer, seed, spine_progress)

    for (i, target) in enumerate(targets)
        progress = branch_progress === nothing ? 1.0 : Float64(branch_progress[i])
        alpha = alphas === nothing ? 1.0 : Float64(alphas[i])
        _draw_run("$(id)_branch_$(i)", spine_x, Float64(target.y), Float64(target.x), Float64(target.y),
                  color, alpha, layer, seed + i * 97, progress)
    end
end

function draw_separator(
    id::String,
    x1::Float64,
    x2::Float64,
    y::Float64;
    color::NTuple{4, Int} = DEFAULT_COLOR,
    alpha::Float64 = 1.0,
    layer::Int = 12,
    seed::Int = 8801,
)
    _draw_run("$(id)_shadow", x1 + 3.0, y + 4.0, x2 + 3.0, y + 4.0,
              (0, 0, 0, 255), alpha * 0.45, layer, seed + 1, 1.0)
    _draw_run(id, x1, y, x2, y, color, alpha, layer, seed, 1.0)
end

export draw_choice_tree, draw_separator

end # module
