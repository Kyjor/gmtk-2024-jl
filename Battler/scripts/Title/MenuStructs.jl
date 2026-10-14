

# Structure to hold audio settings
mutable struct AudioSettings
    masterVolume::Ref{Int}
    musicVolume::Ref{Int}
    sfxVolume::Ref{Int}
    menuSoundVolume::Ref{Int}
    
    function AudioSettings()
        this = new()
        this.masterVolume = Ref(100)  # Default values (0-100)
        this.musicVolume = Ref(100)
        this.sfxVolume = Ref(100)
        this.menuSoundVolume = Ref(100)
        return this
    end
end

# Define menu item types
@enum MenuItemType begin
    # Main menu items
    Action 
    Setting_Number
    Setting_Toggle
    Setting_List
end

# Structure to represent a menu item
mutable struct MenuItem
    type::MenuItemType
    defaultText::String
    textKey::String
    textBox::Union{TextBoxModule.TextBox, Nothing}
    value 

    function MenuItem(type::MenuItemType, textKey::String, defaultText::String;  fontSize::Int=40, action::Function=() -> nothing, value::Any=nothing, listValues=[], ignoreUpdate::Bool=false)
        this = new()
        this.type = type
        this.defaultText = defaultText
        this.textKey = textKey
        this.value = value
        if type == Setting_Toggle && value !== nothing
            action = () -> this.value[] = !this.value[]
        elseif type == Setting_List && value !== nothing && length(listValues) > 0
            # advance to next value in the list, if it's the last, wrap around to the first
            action = () -> this.value[] = listValues[clamp((indexin([this.value[]], listValues)[1] + 1)%length(listValues), 1, length(listValues))]
        elseif type == Setting_Number && value !== nothing
            action = () -> this.value[] = (this.value[] + 10)%110
        end

        this.textBox = TextBoxModule.TextBox(
            get_text(this.textKey, this.defaultText) * (value !== nothing ? ": $(value[])" : "");
            id = "$(string(type))_$(this.textKey)",
            fontSize = fontSize,
            anchor = :center,
            isActive = false,
            clickEvents = [action, () -> update_menu_item(this, ignoreUpdate)]  # Explicitly create a Vector{Function}
        )

        return this
    end

    function update_menu_item(this::MenuItem, ignoreUpdate::Bool=false)
        if ignoreUpdate
            return
        end
        this.textBox.text = get_text(this.textKey, this.defaultText) * (this.value !== nothing ? ": $(this.value[])" : "");
    end
end