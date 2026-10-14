include("../localization/event_strings.jl")
using .EventStringsModule
include.(filter(contains(r".jl$"), readdir(joinpath(@__DIR__, "scripts"); join=true)))