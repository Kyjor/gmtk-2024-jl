abstract type Combatant end

mutable struct FightingEntity
    #stats
    health::Int64
    maxHealth::Int64
    shield::Int64
    maxShield::Int64
    attack::Int64
    defense::Int64
    speed::Int64
    luck::Int64

    #inventory
    inventory::Vector
    gold::Int64
    pieces::Vector
    potions::Vector
    max_potions::Int64
    max_pieces::Int64
    max_treasures::Int64
    treasures::Vector
    #effects
    weaken::Int64
    burn::Int64
    freeze::Int64
    poison::Int64
    vulnerable::Int64
    shock::Int64
    dodge_chance::Int64
    reflect_chance::Int64
    base_attack::Int64  # For storing original attack value when modified by effects

    function FightingEntity()
        this = new()

        this.health = 100
        this.maxHealth = 100

        this.shield = 0
        this.maxShield = 0

        this.attack = 10
        this.defense = 10

        this.speed = 10
        this.luck = 10

        this.inventory = []
        this.gold = 0
        this.pieces = []
        this.potions = []
        this.treasures = []
        this.max_potions = 4
        this.max_pieces = 999
        this.max_treasures = 999

        this.weaken = 0
        this.burn = 0
        this.freeze = 0
        this.poison = 0
        this.vulnerable = 0
        this.shock = 0
        this.dodge_chance = 0
        this.reflect_chance = 0
        this.base_attack = 10  # Same as initial attack

        return this
    end
end

relationships = Dict{Combatant, FightingEntity}()

function Base.getproperty(script::Combatant, property::Symbol)
    # Check if the relationship exists
    add_relationship_if_not_exists(script)

    if hasfield(typeof(relationships[script]), property)
        return getfield(relationships[script], property)
    end

    return getfield(script, property)
end

function Base.setproperty!(script::Combatant, property::Symbol, value)
    add_relationship_if_not_exists(script)

    # Track health changes for analytics (only for User type)
    if property == :health
        # Check if this is a User by checking if it has the selectedCharacter field
        is_user = false
        try
            if isdefined(script, :selectedCharacter)
                is_user = true
            end
        catch
            # Not a User, continue normally
        end

        if is_user
            # Get old health value before setting new one
            old_health = 0
            if hasfield(typeof(relationships[script]), property)
                old_health = getfield(relationships[script], property)
            else
                try
                    old_health = getfield(script, property)
                catch
                    # Field doesn't exist yet, old_health stays 0
                end
            end

            health_change = value - old_health

            # Update analytics if available (only track if there's an actual change)
            if health_change != 0
                try
                    globals = JulGame.UserGlobals["Module"]
                    if globals !== nothing
                        analytics_data = globals.get_analytics_data()
                        if analytics_data !== nothing && analytics_data.is_analytics_enabled
                            # Track health lost/gained
                            if health_change < 0
                                analytics_data.health_lost += abs(health_change)
                            elseif health_change > 0
                                analytics_data.health_gained += health_change
                            end

                            # Track lowest health (update if new health is lower, or initialize if it's the first decrease)
                            if value < analytics_data.lowest_health || (analytics_data.lowest_health == 0 && value < old_health)
                                analytics_data.lowest_health = value
                            end
                        end
                    end
                catch e
                    # Silently fail if analytics not available - don't break gameplay
                    @debug "Could not update health analytics: $e"
                end
            end
        end
    end

    # check if the FightingEntity has the property
    if hasfield(typeof(relationships[script]), property)
        setfield!(relationships[script], property, value)
    else
        setfield!(script, property, value)
    end
end

function add_relationship_if_not_exists(script::Combatant)
    if !haskey(relationships, script)
        relationships[script] = FightingEntity()
        return
    end
end

function delete_relationship(script::Combatant)
    if haskey(relationships, script)
        delete!(relationships, script)
    end
end

function add_piece(script, piece)
    if length(script.pieces) >= script.max_pieces
        return
    end

    push!(script.pieces, piece)
end

function add_treasure(script, treasure)
    if length(script.treasures) >= script.max_treasures
        return
    end

    # check if the treasure is already in the dict
    if haskey(script.treasures, treasure.name)
        return
    end

    push!(script.treasures, treasure)
end

function add_potion(script, potion)
    if length(script.potions) >= script.max_potions
        return
    end

    push!(script.potions, potion)
end

function add_gold(script, gold::Int64)
    script.gold += gold
end

function add_inventory(script, item)
    push!(script.inventory, item)
end

function take_damage(script, damage::Int64)
    # Each vulnerable stack adds 1 damage, including hits of 1.
    if script.vulnerable > 0
        damage += script.vulnerable
    end

    if script.shield > 0
        remaining = take_shield_damage(script, damage)
        if remaining == 0 && damage > 0
            play_fully_blocked_sfx()
        end
        damage = remaining
    end

    script.health -= damage
end

function play_fully_blocked_sfx()
    try
        globals = JulGame.UserGlobals["Module"]
        globals.AudioManagerModule.play_audio_oneshot(
            globals.get_audio_manager(),
            globals.get_asset_path("sfx", "damagefullyblocked"),
            false, 1.0, 0, 1,
        )
    catch e
        @debug "fully blocked sfx: $e"
    end
end

function take_shield_damage(script, damage::Int64)
    script.shield -= damage

    if script.shield < 0
        damage = abs(script.shield)
        script.shield = 0
    else
        damage = 0
    end

    return damage
end


# TODO: Add a way to add custom fields to scripts
