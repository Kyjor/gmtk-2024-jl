module MapFabClustersModule
    using Random

    export FabFormation, formations_for, stamp_fab_clusters!

    """Relative offsets from an anchor (world units)."""
    struct FabFormation
        id::Symbol
        offsets::Vector{NTuple{2, Float64}}
    end

    # Multiple designs per type; at most one formation stamped per type per map.
    const FAB_FORMATIONS = Dict{String, Vector{FabFormation}}(
        "grass" => [
            FabFormation(:meadow, NTuple{2, Float64}[
                (0.0, 0.0), (0.45, 0.25), (-0.35, 0.4), (0.55, -0.3),
                (-0.5, -0.2), (0.15, 0.6), (-0.2, -0.55), (0.7, 0.15),
            ]),
            FabFormation(:tuft, NTuple{2, Float64}[
                (0.0, 0.0), (0.35, 0.15), (-0.3, 0.2), (0.1, -0.35),
                (0.5, -0.1), (-0.45, -0.25),
            ]),
        ],
        "flowers" => [
            FabFormation(:bouquet, NTuple{2, Float64}[
                (0.0, 0.0), (0.5, 0.2), (-0.45, 0.25), (0.15, -0.45), (0.55, -0.3),
            ]),
            FabFormation(:ring, NTuple{2, Float64}[
                (0.55, 0.0), (-0.28, 0.48), (-0.28, -0.48), (0.2, 0.4),
            ]),
        ],
        "bush" => [
            FabFormation(:grove, NTuple{2, Float64}[
                (0.0, 0.0), (2.1, 0.35), (1.0, 1.9),
            ]),
            FabFormation(:line, NTuple{2, Float64}[
                (0.0, 0.0), (2.0, 0.15), (4.0, -0.1),
            ]),
        ],
        "grave" => [
            FabFormation(:row, NTuple{2, Float64}[
                (0.0, 0.0), (3.2, 0.05), (6.4, -0.05),
            ]),
            FabFormation(:family, NTuple{2, Float64}[
                (0.0, 0.0), (3.0, 0.5), (6.0, 0.0), (3.0, -0.55),
            ]),
        ],
        "skull" => [
            FabFormation(:pile, NTuple{2, Float64}[
                (0.0, 0.0), (5.2, 0.4), (2.5, 4.7),
            ]),
            FabFormation(:line, NTuple{2, Float64}[
                (0.0, 0.0), (5.3, 0.15), (10.6, -0.1),
            ]),
        ],
        "groundhand" => [
            FabFormation(:reach, NTuple{2, Float64}[
                (0.0, 0.0), (5.4, 0.3), (2.6, 4.9),
            ]),
        ],
        "hatandwand" => [
            FabFormation(:ritual, NTuple{2, Float64}[
                (0.0, 0.0), (5.5, 0.0), (2.75, 4.8),
            ]),
        ],
        "knife" => [
            FabFormation(:scatter, NTuple{2, Float64}[
                (0.0, 0.0), (5.3, 0.4), (2.4, 4.6),
            ]),
        ],
        "tree" => [
            FabFormation(:grove, NTuple{2, Float64}[
                (0.0, 0.0), (4.2, 1.1), (1.8, 4.2),
            ]),
            FabFormation(:line, NTuple{2, Float64}[
                (0.0, 0.0), (4.0, 0.2), (8.1, -0.15),
            ]),
        ],
        "crow" => [
            # Solo first — almost always stamp at least one perch bird.
            FabFormation(:solo, NTuple{2, Float64}[
                (0.0, 0.0),
            ]),
            FabFormation(:perch, NTuple{2, Float64}[
                (0.0, 0.0), (3.3, 0.25), (6.6, -0.1),
            ]),
        ],
        "fence" => [
            FabFormation(:run, NTuple{2, Float64}[
                (0.0, 0.0), (2.4, 0.0), (4.8, 0.0),
            ]),
        ],
        "streetlight" => [
            FabFormation(:curb, NTuple{2, Float64}[
                (0.0, 0.0), (5.0, 0.05), (10.0, -0.05),
            ]),
        ],
        "bench" => [
            FabFormation(:plaza, NTuple{2, Float64}[
                (0.0, 0.0), (3.5, 0.1), (1.7, 2.9),
            ]),
        ],
        "firehydrant" => [
            FabFormation(:block, NTuple{2, Float64}[
                (0.0, 0.0), (4.0, 0.2), (2.0, 3.5),
            ]),
        ],
        "trashcan" => [
            FabFormation(:pair_row, NTuple{2, Float64}[
                (0.0, 0.0), (3.3, 0.15), (6.6, -0.05),
            ]),
        ],
        "trafficlight" => [
            FabFormation(:corner, NTuple{2, Float64}[
                (0.0, 0.0), (5.5, 0.2), (2.5, 5.0),
            ]),
        ],
        "pothole" => [
            FabFormation(:road_scar, NTuple{2, Float64}[
                (0.0, 0.0), (2.8, 0.3), (1.3, 2.4),
            ]),
        ],
        "cone" => [
            FabFormation(:workzone, NTuple{2, Float64}[
                (0.0, 0.0), (2.3, 0.1), (1.1, 2.0), (3.4, 1.8),
            ]),
        ],
        "balloon" => [
            FabFormation(:bunch, NTuple{2, Float64}[
                (0.0, 0.0), (2.7, 0.3), (1.2, 2.5),
            ]),
        ],
        "suitcase" => [
            FabFormation(:luggage, NTuple{2, Float64}[
                (0.0, 0.0), (3.8, 0.4), (1.8, 3.4),
            ]),
        ],
        "trashbag" => [
            FabFormation(:heap, NTuple{2, Float64}[
                (0.0, 0.0), (3.3, 0.35), (1.5, 2.9),
            ]),
        ],
        "rat" => [
            FabFormation(:nest, NTuple{2, Float64}[
                (0.0, 0.0), (2.8, 0.35), (1.3, 2.5),
            ]),
        ],
        "paperstack" => [
            FabFormation(:pile, NTuple{2, Float64}[
                (0.0, 0.0), (1.7, 0.25), (0.7, 1.5),
            ]),
        ],
        "paper" => [
            FabFormation(:litter, NTuple{2, Float64}[
                (0.0, 0.0), (0.95, 0.35), (-0.8, 0.45), (0.25, -0.85),
            ]),
        ],
        "papercrumpled" => [
            FabFormation(:wad, NTuple{2, Float64}[
                (0.0, 0.0), (0.9, 0.3), (-0.7, 0.4), (0.2, -0.75),
            ]),
        ],
        "can" => [
            FabFormation(:spill, NTuple{2, Float64}[
                (0.0, 0.0), (1.2, 0.25), (0.45, 1.15),
            ]),
        ],
        "cup" => [
            FabFormation(:spill, NTuple{2, Float64}[
                (0.0, 0.0), (1.15, 0.2), (0.4, 1.1),
            ]),
        ],
    )

    function formations_for(name::String)::Vector{FabFormation}
        return get(FAB_FORMATIONS, name, FabFormation[])
    end

    """
    Stamp at most one formation per fab type present in the theme.
    Call before individual scatter/fill so spacing rules see the cluster.
    `place_member!(name, assetCount, vis_x, vis_y)` must create + register the entity.
    `sample_anchor(fab, formation)` returns a candidate world anchor or nothing.
    `member_ok(fab, x, y)` validates a single member position.
    """
    function stamp_fab_clusters!(
        rng::AbstractRNG,
        fabs::Vector,
        sample_anchor::Function,
        member_ok::Function,
        place_member!::Function;
        max_anchor_attempts::Int = 70,
    )
        stamped = Set{String}()
        # First theme entry per name drives zone / asset profile.
        for fab in fabs
            name = fab.name
            name == "fog" && continue
            name in stamped && continue
            forms = formations_for(name)
            isempty(forms) && continue

            # Try listed order first (e.g. crow solo before perch), then the rest.
            # Shuffle only the retry order so we still cover every formation.
            order = collect(eachindex(forms))
            if length(order) > 1
                rest = order[2:end]
                shuffle!(rng, rest)
                order = vcat(order[1], rest)
            end
            for idx in order
                if _try_stamp_formation!(
                    rng, fab, forms[idx], sample_anchor, member_ok, place_member!;
                    max_anchor_attempts,
                )
                    push!(stamped, name)
                    break
                end
            end
        end
        return stamped
    end

    function _try_stamp_formation!(
        rng::AbstractRNG,
        fab,
        form::FabFormation,
        sample_anchor::Function,
        member_ok::Function,
        place_member!::Function;
        max_anchor_attempts::Int,
    )::Bool
        min_same = Float64(fab.minSameTypeDistance)
        soft_jitter = name_uses_soft_jitter(fab.name)

        for _ in 1:max_anchor_attempts
            anchor = sample_anchor(fab, form)
            anchor === nothing && continue
            ax, ay = anchor

            angle = rand(rng) * 2π
            c = cos(angle)
            s = sin(angle)

            points = NTuple{2, Float64}[]
            ok = true
            for (ox, oy) in form.offsets
                rx = ox * c - oy * s
                ry = ox * s + oy * c
                if soft_jitter
                    rx += (rand(rng) - 0.5) * 0.18
                    ry += (rand(rng) - 0.5) * 0.18
                end
                px = ax + rx
                py = ay + ry
                if !member_ok(fab, px, py)
                    ok = false
                    break
                end
                # Pairwise same-type spacing inside the pending cluster
                if min_same > 0.0
                    min_sq = min_same * min_same
                    for (qx, qy) in points
                        dx = px - qx
                        dy = py - qy
                        if dx * dx + dy * dy < min_sq
                            ok = false
                            break
                        end
                    end
                    ok || break
                end
                push!(points, (px, py))
            end
            ok || continue

            for (px, py) in points
                place_member!(fab, px, py)
            end
            return true
        end
        return false
    end

    function name_uses_soft_jitter(name::String)::Bool
        return name in ("grass", "flowers", "paper", "papercrumpled", "can", "cup", "cone", "rat")
    end
end
