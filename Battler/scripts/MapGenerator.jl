module GridMapGenerator

using Random

export Point
struct Point
    x::Int
    y::Int
end

mutable struct MapEdge
    src_x::Int
    src_y::Int
    dst_x::Int
    dst_y::Int
end

mutable struct MapRoomNode
    x::Int
    y::Int
    class::Union{Nothing, Symbol}
    edges::Vector{MapEdge}
    parents::Vector{Point}
end



function MapRoomNode(x, y)
    MapRoomNode(x, y, nothing, MapEdge[], Point[])
end

const Map = Vector{Vector{MapRoomNode}}

function create_nodes(height::Int, width::Int)::Map
    [ [ MapRoomNode(x, y) for x in 0:width-1 ] for y in 0:height-1 ]
end

function _create_paths!(nodes::Map, edge::MapEdge)
    y, x = edge.dst_y, edge.dst_x
    if y + 1 >= length(nodes)
        return
    end
    row_width = length(nodes[1])
    row_end_node = row_width - 1

    min, max = if x == 0
        (0, 1)
    elseif x == row_end_node
        (-1, 0)
    else
        (-1, 1)
    end

    new_edge_x = x + rand(min:max)
    new_edge_y = y + 1
    target_node_candidate = nodes[new_edge_y+1][new_edge_x+1]
    target_coord_candidate = Point(new_edge_x, new_edge_y)
    min_ancestor_gap = 3
    max_ancestor_gap = 5
    current_node_coord = Point(x, y)

    for parent in target_node_candidate.parents
        if parent != current_node_coord
            ancestor = get_common_ancestor(nodes, parent, current_node_coord, max_ancestor_gap)
            if ancestor !== nothing
                ancestor_gap = new_edge_y - ancestor.y
                if ancestor_gap < min_ancestor_gap
                    if target_coord_candidate.x > x
                        new_edge_x = x + rand(-1:0)
                        if new_edge_x < 0
                            new_edge_x = x
                        end
                    elseif target_coord_candidate.x == x
                        new_edge_x = x + rand(-1:1)
                        if new_edge_x > row_end_node
                            new_edge_x = x - 1
                        elseif new_edge_x < 0
                            new_edge_x = x + 1
                        end
                    else
                        new_edge_x = x + rand(0:1)
                        if new_edge_x > row_end_node
                            new_edge_x = x
                        end
                    end
                    target_coord_candidate = Point(new_edge_x, new_edge_y)
                    continue
                end
            end
        end
    end

    # Eliminate edge crosses
    if x != 0
        left_node = nodes[y+1][x]
        if !isempty(left_node.edges)
            right_edge_of_left_node = last(left_node.edges)
            if right_edge_of_left_node.dst_x > new_edge_x
                new_edge_x = right_edge_of_left_node.dst_x
            end
        end
    end
    if x < row_end_node
        right_node = nodes[y+1][x+2]
        if !isempty(right_node.edges)
            left_edge_of_right_node = first(right_node.edges)
            if left_edge_of_right_node.dst_x < new_edge_x
                new_edge_x = left_edge_of_right_node.dst_x
            end
        end
    end

    # Add edge and parent
    push!(nodes[y+1][x+1].edges, MapEdge(x, y, new_edge_x, new_edge_y))
    push!(nodes[new_edge_y+1][new_edge_x+1].parents, Point(x, y))
    _create_paths!(nodes, MapEdge(x, y, new_edge_x, new_edge_y))
end

function create_paths!(nodes::Map, path_density::Int)
    row_size = length(nodes[1]) - 1
    first_starting_node = -1
    for i in 1:path_density
        starting_node = rand(0:row_size)
        if i == 1
            first_starting_node = starting_node
        end
        while starting_node == first_starting_node && i == 2
            starting_node = rand(0:row_size)
        end
        tmp_edge = MapEdge(starting_node, -1, starting_node, 0)
        _create_paths!(nodes, tmp_edge)
    end
end

function filter_redundant_edges!(map::Map)
    existing_edges = Set{Point}()
    delete_list = Tuple{Int, MapEdge}[]
    
    for (i, node) in enumerate(map[1])
        for edge in node.edges
            for prev in existing_edges
                if prev.x == edge.dst_x && prev.y == edge.dst_y
                    push!(delete_list, (i, edge))
                end
            end
            push!(existing_edges, Point(edge.dst_x, edge.dst_y))
        end
    end
    
    for (i, edge) in delete_list
        filter!(e -> e != edge, map[1][i].edges)
    end
end

const ROOM_TYPES = [:RestRoom, :ShopRoom, :MonsterRoomElite, :EventRoom, :MonsterRoom, :TreasureRoom, :BossRoom]

function generate_room_type(room_chances::Dict{Symbol, Float64}, available_room_count::Int;
                            min_counts::Dict{Symbol, Int} = Dict{Symbol, Int}())
    acc = Symbol[]
    rooms_type_q = [:ShopRoom, :RestRoom, :MonsterRoomElite, :EventRoom]
    
    for t in rooms_type_q
        chance = get(room_chances, t, 0.0)
        min_count = get(min_counts, t, 0)
        rooms = max(min_count, round(Int, chance * available_room_count))
        for _ in 1:rooms
            push!(acc, t)
        end
    end
    
    # Fill remaining with MonsterRoom
    while length(acc) < available_room_count
        push!(acc, :MonsterRoom)
    end
    acc
end

function rule_assignable_to_row(n::MapRoomNode, room::Symbol)
    applicable_rooms = Set([:RestRoom, :MonsterRoomElite])
    if n.y <= 5 && room in applicable_rooms
        return false
    end
    if n.y >= 13 && room == :RestRoom
        return false
    end
    true
end

function rule_sibling_matches(sibs::Vector{MapRoomNode}, room::Symbol)
    applicable_rooms = Set([:RestRoom, :TreasureRoom, :ShopRoom, :MonsterRoomElite, :MonsterRoom, :EventRoom, :BossRoom])
    any(sib -> sib.class == room, sibs) && room in applicable_rooms
end

function get_siblings(map::Map, node::MapRoomNode)
    sibs = MapRoomNode[]
    for parent in node.parents
        for edge in map[parent.y+1][parent.x+1].edges
            sib = map[edge.dst_y+1][edge.dst_x+1]
            if sib !== node
                push!(sibs, sib)
            end
        end
    end
    sibs
end

function rule_parent_matches(map::Map, parents::Vector{Point}, room::Symbol)
    applicable_rooms = Set([:RestRoom, :TreasureRoom, :ShopRoom, :MonsterRoomElite, :BossRoom])
    any(parent -> map[parent.y+1][parent.x+1].class == room, parents) && room in applicable_rooms
end

function get_next_room_type(map::Map, n::MapRoomNode, room_list::Vector{Symbol})
    parents = n.parents
    siblings = get_siblings(map, n)
    for room in room_list
        if rule_assignable_to_row(n, room)
            if !rule_parent_matches(map, parents, room) && !rule_sibling_matches(siblings, room)
                return room
            end
            if n.y == 0
                return room
            end
        end
    end
    nothing
end

function count_connected_nodes(map::Map)
    count = 0
    for row in map, node in row
        # Count nodes that are part of the path system (have edges OR have parents) and don't have a class yet
        if (!isempty(node.edges) || !isempty(node.parents)) && isnothing(node.class)
            count += 1
        end
    end
    count
end

function last_minute_node_checker!(map::Map)
    for row in map, node in row
        # Check all connected nodes (with edges OR parents) that don't have a class
        if (!isempty(node.edges) || !isempty(node.parents)) && isnothing(node.class)
            @debug "Room [$(node.y),$(node.x)] was empty. Now populated with monsters."
            node.class = :MonsterRoom
        end
    end
end

function distribute_rooms_across_map!(map::Map, room_list::Vector{Symbol})
    node_count = count_connected_nodes(map)
    resize!(room_list, max(length(room_list), node_count))
    shuffle!(room_list)
    
    # Assign rooms
    for row in map, node in row
        # Process nodes that have edges (non-final nodes) and don't have a class yet
        if !isempty(node.edges) && isnothing(node.class)
            room_to_be_set = get_next_room_type(map, node, room_list)
            if room_to_be_set !== nothing
                pos = findfirst(==(room_to_be_set), room_list)
                if pos !== nothing
                    splice!(room_list, pos)
                    node.class = room_to_be_set
                end
            end
        end
    end
    
    last_minute_node_checker!(map)
end

function get_room_symbol(t::Union{Nothing, Symbol})
    if t === nothing
        return "*"
    end
    if t == :RestRoom
        return "R"
    elseif t == :ShopRoom
        return "S"
    elseif t == :MonsterRoom
        return "M"
    elseif t == :EventRoom
        return "?"
    elseif t == :MonsterRoomElite
        return "E"
    elseif t == :TreasureRoom
        return "T"
    elseif t == :BossRoom
        return "B"
    end
    "*"
end

function generate_dungeon(height::Int, width::Int, path_density::Int)::Map
    map = create_nodes(height, width)
    create_paths!(map, path_density)
    filter_redundant_edges!(map)
    return map
end

function generate_maps(seed::Int64, map_height::Int, map_width::Int, path_density::Int, is_ascension_zero::Bool; num_maps::Int = 3)
    maps = Map[]
    
    for _ in 1:num_maps
        map = generate_dungeon(map_height, map_width, path_density)
        
        # Count connected nodes
        count = sum(!isempty(n.edges) && (n.y != map_height-2 || !isempty(n.parents)) for row in map for n in row)
        
        # Set special rooms
        for node in map[1]
            node.class = :MonsterRoom
        end
        for node in map[9]
            node.class = :TreasureRoom
        end
        # Find all current final nodes (nodes with parents but no edges - endpoints)
        final_nodes = MapRoomNode[]
        for row in map, node in row
            if !isempty(node.parents) && isempty(node.edges)
                push!(final_nodes, node)
            end
        end
        
        @debug "Found $(length(final_nodes)) final nodes before boss room creation."
        
        # Clear any existing boss rooms to ensure only one
        for row in map, node in row
            if node.class == :BossRoom
                @debug "Clearing existing boss room at ($(node.x), $(node.y))"
                node.class = nothing
            end
        end
        
        # First, assign rest rooms to the current final row (before adding boss room)
        for node in map[end]
            # Only assign RestRoom to nodes that are connected but don't have a class
            if (!isempty(node.edges) || !isempty(node.parents)) && node.class === nothing
                node.class = :RestRoom
                @debug "Assigned RestRoom to node at ($(node.x), $(node.y))"
            end
        end
        
        # Create a single boss room that all final nodes will connect to
        if !isempty(final_nodes)
            # Add a completely new column (row) to the map for the boss room
            # This preserves existing rest rooms and other final nodes
            boss_y = length(map)  # New row at the very end
            boss_x = 1  # Place boss room in the middle column
            
            @debug "Creating boss room at position ($(boss_x), $(boss_y)). Current map has $(length(map)) rows."
            
            # Append a new row to the map
            new_row = [MapRoomNode(x, boss_y) for x in 0:(length(map[1])-1)]
            push!(map, new_row)
            
            # Create the boss room in the new row
            boss_node = map[boss_y + 1][boss_x + 1]
            boss_node.class = :BossRoom
            
            @debug "Boss node created. Connecting $(length(final_nodes)) final nodes to boss room."
            
            # Connect all final nodes to the boss room
            for (i, final_node) in enumerate(final_nodes)
                @debug "Connecting final node $(i) at ($(final_node.x), $(final_node.y)) to boss room"
                # Add edge from final node to boss room
                push!(final_node.edges, MapEdge(final_node.x, final_node.y, boss_x, boss_y))
                # Add parent relationship to boss room
                push!(boss_node.parents, Point(final_node.x, final_node.y))
            end
            
            @debug "Boss room created at ($(boss_x), $(boss_y)) with $(length(final_nodes)) connections. Map now has $(length(map)) rows."
            
            # Verify boss room is the only one and is truly final
            boss_count = 0
            for row in map, node in row
                if node.class == :BossRoom
                    boss_count += 1
                    @debug "Found boss room at ($(node.x), $(node.y)) with $(length(node.edges)) edges and $(length(node.parents)) parents"
                end
            end
            @debug "Total boss rooms found: $(boss_count)"
            
            # Final validation
            if boss_count != 1
                error("Boss room validation failed! Expected 1 boss room, found $(boss_count)")
            end
            
            # Verify the boss room is in the last row
            boss_node_final = map[end][boss_x + 1]
            if boss_node_final.class != :BossRoom
                error("Boss room is not in the final row!")
            end
            
            # Verify the boss room has no outgoing edges (is truly final)
            if !isempty(boss_node_final.edges)
                error("Boss room has outgoing edges! It should be the final node.")
            end
            
            @debug "Boss room validation passed: Single boss room in final row with no outgoing edges."
            
        else
            @debug "No final nodes found for boss room creation!"
        end
        
        # Room chances
        room_chances = Dict(
            :ShopRoom => 0.1,
            :RestRoom => 0.12,
            :EventRoom => 0.22,
            :MonsterRoomElite => 0.08 * (is_ascension_zero ? 1.0 : 1.6)
        )
        
        room_list = generate_room_type(room_chances, count; min_counts = Dict(:ShopRoom => 2))
        distribute_rooms_across_map!(map, room_list)
        push!(maps, map)
    end
    
    maps
end

function get_common_ancestor(map::Map, node1::Point, node2::Point, max_depth::Int)::Union{Nothing, Point}
    # Assertions matching Rust implementation
    @assert node1.y == node2.y "Nodes must be on the same level"
    @assert node1.x != node2.x "Nodes must be different"
    
    # Determine left and right nodes (keeping the bug for compatibility)
    l_node, r_node = if node1.x < node2.y
        node1, node2
    else
        node2, node1
    end
    
    current_y = node1.y
    
    while current_y >= 0 && current_y >= node1.y - max_depth
        # Get parents for both nodes
        l_parents = map[l_node.y+1][l_node.x+1].parents
        r_parents = map[r_node.y+1][r_node.x+1].parents
        
        # Check if either node has no parents
        if isempty(l_parents) || isempty(r_parents)
            return nothing
        end
        
        # Get the rightmost parent for left node and leftmost parent for right node
        l_node = l_parents[argmax([p.x for p in l_parents])]
        r_node = r_parents[argmin([p.x for p in r_parents])]
        
        # Check if we found a common ancestor
        if l_node == r_node
            return l_node
        end
        
        current_y -= 1
    end
    
    return nothing
end

end # module
