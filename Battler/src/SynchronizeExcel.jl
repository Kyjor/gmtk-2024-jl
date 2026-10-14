const _ADHOC = !isempty(PROGRAM_FILE) && abspath(PROGRAM_FILE) == @__FILE__

if _ADHOC
    import Pkg
    Pkg.activate(normpath(joinpath(@__DIR__, "..")))
end

include("generate_constants.jl")

using HTTP
using XLSX

const LIVE_DATA_SHEETS = [
    "Treasures",
    "Enemies",
    "Pieces",
    "Potions",
    "RandomEvents",
    "Characters",
    "EnemyComps",
    "Encounters",
    "Statuses",
    "Settings",
]

const _GDM_PKG = Base.PkgId(Base.UUID("7e4809e4-a3a8-4b3b-a5e8-a128d6c0d43e"), "GameDataManager")

function _is_game_data_manager_dir(path::AbstractString)
    isdir(path) && isfile(joinpath(path, "config.json"))
end

"""
Locate assets/game-data-manager at runtime.

`@__DIR__` is baked into PackageCompiler sysimages (CI path), so compiled
builds must resolve from pwd()/exe location instead.
"""
function resolve_game_data_manager_dir()
    roots = String[pwd(), dirname(pwd())]
    if !isempty(PROGRAM_FILE)
        exe_dir = dirname(abspath(PROGRAM_FILE))
        push!(roots, exe_dir, dirname(exe_dir))
    end
    if (@isdefined JulGame) && isdefined(JulGame, :BasePath) && !isempty(JulGame.BasePath)
        push!(roots, JulGame.BasePath)
    end
    # Dev checkout only — skip when the compile-time path is gone (relocated exe).
    compile_root = normpath(joinpath(@__DIR__, ".."))
    isdir(compile_root) && push!(roots, compile_root)

    candidates = String[]
    for root in unique(normpath.(roots))
        push!(candidates, joinpath(root, "assets", "game-data-manager"))
        push!(candidates, root) # already inside game-data-manager
    end
    candidates = unique(normpath.(candidates))

    for c in candidates
        _is_game_data_manager_dir(c) && return c
    end
    error("game-data-manager directory not found; tried: $(join(candidates, ", "))")
end

"""
Download the balance spreadsheet, rewrite JSON via GameDataManager, and
(optionally) regenerate constants/structs when JULGAME_REGEN_TYPES=true.

GameDataManager is required only after cd into its project dir so `__init__`
sees config.json. JSON is pinned to 0.21 for GameDataManager's use_mmap API.
"""
function sync_spreadsheet_to_json!()
    gdm_dir = resolve_game_data_manager_dir()
    xlsx_dir = joinpath(gdm_dir, "xlsx")
    mkpath(xlsx_dir)

    sheet_url = "https://docs.google.com/spreadsheets/d/1b-7Iq35JTVkJ2TTr-fdCs5gtcoDLApFK/export?format=xlsx"
    headers = Dict(
        "Accept" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "User-Agent" => "Mozilla/5.0",
    )
    response = HTTP.get(sheet_url; headers=headers)
    if response.status != 200
        error("Failed to download Google Sheets data. HTTP status: $(response.status)")
    end

    xlsx_path = joinpath(xlsx_dir, "Data.xlsx")
    temp_path = joinpath(xlsx_dir, "Data_temp.xlsx")
    write(xlsx_path, response.body)

    try
        xf = XLSX.readxlsx(xlsx_path)
        data = Dict{String, Any}()
        for sheet_name in XLSX.sheetnames(xf)
            try
                data[sheet_name] = XLSX.gettable(xf[sheet_name])
            catch e
                @warn "JULGAME_LIVE_DATA: skipping non-table sheet during reformat" sheet=sheet_name error=e
            end
        end
        close(xf)
        if !isempty(data)
            XLSX.openxlsx(temp_path, mode="w") do xf
                for (sheet_name, table) in data
                    XLSX.addsheet!(xf, sheet_name)
                    XLSX.writetable!(xf[sheet_name], table)
                end
            end
            mv(temp_path, xlsx_path; force=true)
        else
            @warn "JULGAME_LIVE_DATA: no sheets reformatted; keeping downloaded XLSX"
        end
    catch e
        @error "Failed to reformat XLSX file: $(e) — continuing with downloaded file"
    end

    previous_cwd = pwd()
    try
        cd(gdm_dir)
        # Load after cd so GameDataManager.__init__ can see config.json
        Base.require(_GDM_PKG)
        GDM = Base.loaded_modules[_GDM_PKG]
        Base.invokelatest(GDM.init_project)
        Base.invokelatest(GDM.xl, "data")
    finally
        cd(previous_cwd)
    end

    package_compiled = (@isdefined JulGame) && isdefined(JulGame, :IS_PACKAGE_COMPILED) && JulGame.IS_PACKAGE_COMPILED
    if !package_compiled && get(ENV, "JULGAME_REGEN_TYPES", "false") == "true"
        current_sheet = ""
        try
            for sheet in LIVE_DATA_SHEETS
                current_sheet = sheet
                @debug "Generating constants for $(sheet)"
                generate_constants_file(sheet)
                @debug "Generating structs for $(sheet)"
                generate_structs_file(sheet)
            end
        catch e
            @error "Error generating structs/constants for $(current_sheet): $(e)"
            Base.show_backtrace(stdout, catch_backtrace())
            rethrow()
        end
    end
    return nothing
end

if _ADHOC
    println("Syncing spreadsheet to JSON…")
    sync_spreadsheet_to_json!()
    println("Done.")
end
