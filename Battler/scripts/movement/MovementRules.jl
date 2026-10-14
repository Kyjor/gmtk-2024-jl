module MovementRulesModule
    using JulGame

    export CardinalReach, DiagonalReach
    export reachable_cells, swappable_cells

    struct CardinalReach
        max_steps::Int
    end

    struct DiagonalReach
        max_steps::Int
    end

    const CARDINAL_DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))
    const DIAGONAL_DIRS = ((1, 1), (1, -1), (-1, 1), (-1, -1))

    """
    All in-bounds cells reachable from `origin` given treasure flags.
    Does not filter occupancy or nails.
    """
    function reachable_cells(
        origin::Tuple{Int,Int},
        gridW::Int,
        gridH::Int,
        has_black_pawn::Bool,
        has_white_bishop::Bool,
    )::Vector{Math.Vector2f}
        cells = Vector{Math.Vector2f}()
        seen = Set{Tuple{Int,Int}}()
        cardinal_max = has_black_pawn ? 2 : 1
        append_rays!(cells, seen, origin, gridW, gridH, CARDINAL_DIRS, cardinal_max)
        if has_white_bishop
            append_rays!(cells, seen, origin, gridW, gridH, DIAGONAL_DIRS, max(gridW, gridH) - 1)
        end
        return cells
    end

    """
    Reachable cells that currently hold a piece (swap targets).
    Caller filters nails.
    """
    function swappable_cells(
        origin::Tuple{Int,Int},
        gridPieces::Array{Union{Nothing, JulGame.EntityModule.Entity}, 2},
        gridW::Int,
        gridH::Int,
        has_black_pawn::Bool,
        has_white_bishop::Bool,
    )::Vector{Math.Vector2f}
        ox, oy = origin
        if ox < 1 || ox > gridW || oy < 1 || oy > gridH
            return Math.Vector2f[]
        end
        if gridPieces[ox, oy] === nothing
            return Math.Vector2f[]
        end

        result = Vector{Math.Vector2f}()
        for cell in reachable_cells(origin, gridW, gridH, has_black_pawn, has_white_bishop)
            x = Int(cell.x)
            y = Int(cell.y)
            if gridPieces[x, y] !== nothing
                push!(result, cell)
            end
        end
        return result
    end

    function append_rays!(
        cells::Vector{Math.Vector2f},
        seen::Set{Tuple{Int,Int}},
        origin::Tuple{Int,Int},
        gridW::Int,
        gridH::Int,
        dirs::NTuple{N, NTuple{2, Int}},
        max_steps::Int,
    ) where {N}
        ox, oy = origin
        for (dx, dy) in dirs
            for step in 1:max_steps
                nx = ox + dx * step
                ny = oy + dy * step
                if nx < 1 || nx > gridW || ny < 1 || ny > gridH
                    break
                end
                key = (nx, ny)
                if !(key in seen)
                    push!(seen, key)
                    push!(cells, Math.Vector2f(Float64(nx), Float64(ny)))
                end
            end
        end
        return nothing
    end
end
