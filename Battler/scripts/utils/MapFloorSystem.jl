module MapFloorSystemModule
using JulGame

export MapFabSpec,
       MapFloorTheme,
       FLOOR_THEMES,
       IS_DEMO,
       floor_theme,
       has_next_floor,
       advance_to_next_floor!,
       map_tile_sprite,
       map_path_sprite,
       resolve_shop_scene

struct MapFabSpec
    name::String
    assetCount::Int
    spawnCount::Int
    collisionRadius::Float64
    # :scatter / :enclosed / :interstitial / :sidewalk / :outer / :road (/ :edge alias of :outer)
    placement::Symbol
    # Min center distance to another fab of the same name (0 = hull-only).
    minSameTypeDistance::Float64
end

# Default spacing between duplicates of the same prop.
const DEFAULT_MIN_SAME_TYPE_DISTANCE = Dict{String, Float64}(
    "grass" => 0.0,
    "flowers" => 0.35,
    "bush" => 1.75,
    "shrub" => 1.75,
    "stump" => 2.5,
    "grave" => 2.75,
    "skull" => 5.0,
    "groundhand" => 5.0,
    "hatandwand" => 5.0,
    "knife" => 5.0,
    "tree" => 3.5,
    "crow" => 3.5,
    "fence" => 10.0,
    "fog" => 0.0,
    "streetlight" => 4.5,
    "bench" => 3.0,
    "firehydrant" => 3.5,
    "trashcan" => 3.0,
    "trafficlight" => 5.0,
    "pothole" => 2.5,
    "cone" => 2.0,
    "balloon" => 2.5,
    "suitcase" => 3.5,
    "rat" => 2.5,
    "trashbag" => 3.0,
    "paperstack" => 1.5,
    "paper" => 0.75,
    "papercrumpled" => 0.75,
    "can" => 1.0,
    "cup" => 1.0,
    "mailbox" => 3.5,
    "letter" => 1.0,
    "recyclingbin" => 3.0,
    "signdeadend" => 4.0,
    "signstop" => 4.0,
    "baseball" => 1.5,
    "baseballbat" => 2.0,
    "basketball" => 1.5,
    "batandball" => 2.0,
    "bicycle" => 3.0,
    "soccerball" => 1.5,
    "squirrel" => 2.0,
)

function MapFabSpec(
    name::String,
    assetCount::Int,
    spawnCount::Int,
    collisionRadius::Float64,
    placement::Symbol = :scatter;
    minSameTypeDistance::Float64 = get(DEFAULT_MIN_SAME_TYPE_DISTANCE, name, 2.0),
)
    return MapFabSpec(name, assetCount, spawnCount, collisionRadius, placement, minSameTypeDistance)
end

const GRASS_FILL_MULTIPLIER = 0.75
const FLOWER_FILL_MULTIPLIER = 0.75

struct MapFloorTheme
    number::Int
    name::String
    # Stable art folder slug (graveyard/city/town) — independent of floor order.
    assetPrefix::String
    encounterFloor::Int
    mapHeight::Int
    mapWidth::Int
    pathDensity::Int
    mapTilePrefix::String
    startingTileSprite::String
    spawnPointSprite::String
    pathSprites::Dict{Symbol, String}
    sceneArt::Dict{String, String}
    fabs::Vector{MapFabSpec}
    fabBounds::NTuple{4, Float64}
    fogHorizontalBounds::NTuple{2, Float64}
    # 0 = world-locked FG; 0.5 / 0.75 = parallax scroll vs camera, with seamless wrap.
    fgParallaxFactor::Float64
    # Camera zoom for the map scene (1.0 = default; <1 zooms out).
    mapZoom::Float64
    # Sprite multiply tint applied to fog fabs (RGBA 0–255).
    fogColor::NTuple{4, Int}
    # Scales grass spawnCount (1.0 = theme baseline; 0.5 = half density).
    grassFillMultiplier::Float64
    # Scales flowers spawnCount (1.0 = theme baseline; 0.5 = half density).
    flowerFillMultiplier::Float64
end

function graveyard_theme(
    number::Int,
    name::String;
    assetPrefix::String = "graveyard",
    encounterFloor::Int = number,
    mapHeight::Int = 15,
    mapWidth::Int = 4,
    pathDensity::Int = 3,
    mapTilePrefix::String = "map-tile",
    startingTileSprite::String = "map-tile-green",
    spawnPointSprite::String = "mapfab-graveyardspawnpoint",
    pathSprites::Dict{Symbol, String} = Dict(
        :available => "map-pathavailable",
        :inactive => "map-pathinactive",
        :highlighted => "map-pathhighlighted",
    ),
    sceneArt::Dict{String, String} = Dict(
        "BG" => "bg-title-grid",
        "BG1" => "bg-title-grid",
        "BG2" => "bg-title-grid",
        "mapfab-bottomfgtrees-0000" => "mapfab-graveyardbottomfgtrees",
        "TopBG" => "map-topbg-graveyard",
    ),
    # Landmarks first; keep Interstitial well stocked (graves/bushes/skulls).
    fabs::Vector{MapFabSpec} = [
        # Enclosed (4): large → few flowers → grass fill (order matters).
        MapFabSpec("bush", 2, 6, 0.8, :enclosed),
        MapFabSpec("grave", 8, 8, 0.8, :enclosed),
        MapFabSpec("flowers", 6, 20, 0.15, :enclosed),
        MapFabSpec("grass", 14, 50, 0.08, :enclosed),
        # Interstitial (2): décor first, grass fill last.
        MapFabSpec("bush", 2, 6, 0.8, :interstitial),
        MapFabSpec("grave", 8, 8, 0.8, :interstitial),
        MapFabSpec("groundhand", 1, 3, 0.4, :interstitial),
        MapFabSpec("hatandwand", 1, 3, 0.4, :interstitial),
        MapFabSpec("knife", 1, 3, 0.4, :interstitial),
        MapFabSpec("skull", 2, 15, 0.4, :interstitial),
        # Crows before trees so OuterCrust isn't already packed.
        MapFabSpec("crow", 1, 8, 0.35, :outer),
        MapFabSpec("tree", 2, 10, 0.8, :outer),
        MapFabSpec("fog", 6, 100, 0.6, :scatter),
        MapFabSpec("fence", 1, 2, 0.6, :outer),
        MapFabSpec("grass", 14, 15, 0.08, :interstitial),
    ],
    fabBounds::NTuple{4, Float64} = (-20.0, 50.0, -20.0, 20.0),
    fogHorizontalBounds::NTuple{2, Float64} = (-2.0, 52.0),
    fgParallaxFactor::Float64 = 0.5,
    mapZoom::Float64 = 1.1,
    fogColor::NTuple{4, Int} = (255, 255, 255, 255),
    grassFillMultiplier::Float64 = GRASS_FILL_MULTIPLIER,
    flowerFillMultiplier::Float64 = FLOWER_FILL_MULTIPLIER,
)
    return MapFloorTheme(
        number,
        name,
        assetPrefix,
        encounterFloor,
        mapHeight,
        mapWidth,
        pathDensity,
        mapTilePrefix,
        startingTileSprite,
        spawnPointSprite,
        pathSprites,
        sceneArt,
        fabs,
        fabBounds,
        fogHorizontalBounds,
        fgParallaxFactor,
        mapZoom,
        fogColor,
        grassFillMultiplier,
        flowerFillMultiplier,
    )
end

function city_theme(
    number::Int,
    name::String;
    assetPrefix::String = "city",
    encounterFloor::Int = number,
    mapHeight::Int = 15,
    mapWidth::Int = 4,
    pathDensity::Int = 3,
    mapTilePrefix::String = "map-tile",
    startingTileSprite::String = "map-tile-green",
    spawnPointSprite::String = "mapfab-graveyardspawnpoint",
    pathSprites::Dict{Symbol, String} = Dict(
        :available => "map-pathavailable",
        :inactive => "map-pathinactive",
        :highlighted => "map-pathhighlighted",
    ),
    sceneArt::Dict{String, String} = Dict(
        "BG" => "bg-title-grid",
        "BG1" => "bg-title-grid",
        "BG2" => "bg-title-grid",
        "mapfab-bottomfgtrees-0000" => "mapfab-cityforegroundscrolling",
        "TopBG" => "map-topbg-city",
    ),
    # Sidewalk furniture + interstitial set; grass/flowers fill from city patch.
    fabs::Vector{MapFabSpec} = [
        MapFabSpec("streetlight", 1, 6, 1.4, :sidewalk),
        MapFabSpec("bench", 1, 4, 1.3, :sidewalk),
        MapFabSpec("firehydrant", 1, 3, 1.0, :sidewalk),
        MapFabSpec("trashcan", 1, 3, 1.1, :sidewalk),
        MapFabSpec("trafficlight", 1, 2, 1.0, :sidewalk),
        MapFabSpec("bush", 2, 10, 1.0, :interstitial),
        MapFabSpec("balloon", 2, 5, 0.6, :interstitial),
        MapFabSpec("suitcase", 1, 4, 0.9, :interstitial),
        MapFabSpec("trashbag", 2, 5, 0.8, :interstitial),
        MapFabSpec("rat", 1, 4, 0.5, :interstitial),
        MapFabSpec("paperstack", 2, 2, 0.55, :enclosed),
        MapFabSpec("paper", 4, 4, 0.45, :enclosed),
        MapFabSpec("papercrumpled", 4, 4, 0.45, :enclosed),
        MapFabSpec("can", 1, 3, 0.4, :enclosed),
        MapFabSpec("cup", 1, 3, 0.4, :enclosed),
        MapFabSpec("flowers", 6, 16, 0.15, :enclosed),
        MapFabSpec("grass", 13, 40, 0.08, :enclosed),
        MapFabSpec("pothole", 1, 3, 0.8, :road),
        MapFabSpec("cone", 2, 4, 0.7, :pathside),
        MapFabSpec("fog", 6, 28, 0.6, :scatter),
        MapFabSpec("grass", 13, 12, 0.08, :interstitial),
    ],
    fabBounds::NTuple{4, Float64} = (-20.0, 50.0, -20.0, 20.0),
    fogHorizontalBounds::NTuple{2, Float64} = (-2.0, 52.0),
    fgParallaxFactor::Float64 = 0.65,
    mapZoom::Float64 = 1.1,
    # Match the cyan outline language of city décor.
    fogColor::NTuple{4, Int} = (110, 195, 255, 220),
    grassFillMultiplier::Float64 = GRASS_FILL_MULTIPLIER,
    flowerFillMultiplier::Float64 = FLOWER_FILL_MULTIPLIER,
)
    return MapFloorTheme(
        number,
        name,
        assetPrefix,
        encounterFloor,
        mapHeight,
        mapWidth,
        pathDensity,
        mapTilePrefix,
        startingTileSprite,
        spawnPointSprite,
        pathSprites,
        sceneArt,
        fabs,
        fabBounds,
        fogHorizontalBounds,
        fgParallaxFactor,
        mapZoom,
        fogColor,
        grassFillMultiplier,
        flowerFillMultiplier,
    )
end

function town_theme(
    number::Int,
    name::String;
    assetPrefix::String = "town",
    encounterFloor::Int = number,
    mapHeight::Int = 15,
    mapWidth::Int = 4,
    pathDensity::Int = 3,
    mapTilePrefix::String = "map-tile",
    startingTileSprite::String = "map-tile-green",
    spawnPointSprite::String = "mapfab-graveyardspawnpoint",
    pathSprites::Dict{Symbol, String} = Dict(
        :available => "map-pathavailable",
        :inactive => "map-pathinactive",
        :highlighted => "map-pathhighlighted",
    ),
    sceneArt::Dict{String, String} = Dict(
        "BG" => "bg-title-grid",
        "BG1" => "bg-title-grid",
        "BG2" => "bg-title-grid",
        "mapfab-bottomfgtrees-0000" => "mapfab-townforegroundscrolling",
        "TopBG" => "map-topbg-town",
    ),
    fabs::Vector{MapFabSpec} = [
        MapFabSpec("streetlight", 1, 6, 1.4, :sidewalk),
        MapFabSpec("firehydrant", 1, 3, 1.0, :sidewalk),
        MapFabSpec("trashcan", 1, 3, 1.1, :sidewalk),
        MapFabSpec("mailbox", 1, 2, 1.0, :sidewalk),
        MapFabSpec("recyclingbin", 1, 2, 1.0, :sidewalk),
        MapFabSpec("signstop", 1, 2, 0.9, :sidewalk),
        MapFabSpec("signdeadend", 1, 1, 0.9, :sidewalk),
        MapFabSpec("fence", 2, 2, 0.8, :outer),
        MapFabSpec("tree", 2, 6, 0.9, :outer),
        MapFabSpec("bush", 2, 8, 1.0, :interstitial),
        MapFabSpec("shrub", 2, 6, 0.9, :interstitial),
        MapFabSpec("stump", 2, 3, 0.8, :interstitial),
        MapFabSpec("trashbag", 2, 5, 0.8, :interstitial),
        MapFabSpec("squirrel", 1, 3, 0.5, :interstitial),
        MapFabSpec("bicycle", 1, 2, 1.0, :interstitial),
        MapFabSpec("baseballbat", 1, 2, 0.6, :interstitial),
        MapFabSpec("batandball", 1, 2, 0.6, :interstitial),
        MapFabSpec("hatandwand", 1, 2, 0.5, :interstitial),
        MapFabSpec("knife", 1, 2, 0.5, :interstitial),
        MapFabSpec("letter", 3, 3, 0.4, :enclosed),
        MapFabSpec("baseball", 1, 3, 0.4, :enclosed),
        MapFabSpec("basketball", 1, 2, 0.45, :enclosed),
        MapFabSpec("soccerball", 1, 2, 0.45, :enclosed),
        MapFabSpec("flowers", 6, 16, 0.15, :enclosed),
        MapFabSpec("grass", 14, 40, 0.08, :enclosed),
        MapFabSpec("pothole", 1, 3, 0.8, :road),
        MapFabSpec("fog", 6, 28, 0.6, :scatter),
        MapFabSpec("grass", 14, 12, 0.08, :interstitial),
    ],
    fabBounds::NTuple{4, Float64} = (-20.0, 50.0, -20.0, 20.0),
    fogHorizontalBounds::NTuple{2, Float64} = (-2.0, 52.0),
    fgParallaxFactor::Float64 = 0.65,
    mapZoom::Float64 = 1.1,
    fogColor::NTuple{4, Int} = (110, 195, 255, 220),
    grassFillMultiplier::Float64 = GRASS_FILL_MULTIPLIER,
    flowerFillMultiplier::Float64 = FLOWER_FILL_MULTIPLIER,
)
    return MapFloorTheme(
        number,
        name,
        assetPrefix,
        encounterFloor,
        mapHeight,
        mapWidth,
        pathDensity,
        mapTilePrefix,
        startingTileSprite,
        spawnPointSprite,
        pathSprites,
        sceneArt,
        fabs,
        fabBounds,
        fogHorizontalBounds,
        fgParallaxFactor,
        mapZoom,
        fogColor,
        grassFillMultiplier,
        flowerFillMultiplier,
    )
end

const FLOOR_THEMES = [
    graveyard_theme(1, "Graveyard"),
    # Keep floor-1 encounter tables until later-floor combat content is ready.
    city_theme(2, "The City"; encounterFloor = 1),
    town_theme(3, "Town"; encounterFloor = 1),
]

function floor_theme(floor::Int)::MapFloorTheme
    index = findfirst(theme -> theme.number == floor, FLOOR_THEMES)
    index === nothing && throw(ArgumentError("No map floor is configured for floor $floor"))
    return FLOOR_THEMES[index]
end

# Baked at sysimage build time (CI sets NECRO_DEMO for the demo variant).
const IS_DEMO = get(ENV, "NECRO_DEMO", "false") == "true"
const DEMO_FLOOR_COUNT = 1
const LAST_FLOOR = IS_DEMO ? DEMO_FLOOR_COUNT : maximum(theme -> theme.number, FLOOR_THEMES)

has_next_floor(floor::Int)::Bool = next_floor_number(floor) !== nothing

function next_floor_number(floor::Int)
    later_floors = [theme.number for theme in FLOOR_THEMES if floor < theme.number <= LAST_FLOOR]
    return isempty(later_floors) ? nothing : minimum(later_floors)
end

function advance_to_next_floor!(persistentState)::Bool
    next_floor = next_floor_number(persistentState.currentFloor)
    next_floor === nothing && return false

    persistentState.currentFloor = next_floor
    persistentState.currentLevel = 0
    persistentState.currentRoom = 0
    persistentState.isFloorComplete = false
    persistentState.completedNodes = Int[]
    persistentState.currentEnemies = []
    persistentState.currentEvent = (type = "", name = "")
    persistentState.mapPoints = nothing
    persistentState.mapConnections = Dict{String, Any}()
    persistentState.availableNodes = Int[]
    persistentState.startingPoints = Int[]
    return true
end

function map_tile_sprite(theme::MapFloorTheme, category; completed::Bool = false)::String
    suffix = completed ? "-complete" : ""
    return JulGame.UserGlobals["Module"].get_asset_path("$(theme.mapTilePrefix)-$(lowercase(String(category)))$(suffix)")
end

function map_path_sprite(theme::MapFloorTheme, state::Symbol)::String
    haskey(theme.pathSprites, state) || throw(ArgumentError("No map path sprite configured for state $state"))
    return JulGame.UserGlobals["Module"].get_asset_path(theme.pathSprites[state])
end

function resolve_shop_scene(seed, node_index)::String
    h = hash((Int(seed), Int(node_index), 0x48414d53))  # "HAMS"
    return isodd(h) && !IS_DEMO ? "hamster-shop.json" : "upgraded-shop.json"
end

end
