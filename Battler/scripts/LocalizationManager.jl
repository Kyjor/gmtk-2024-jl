module LocalizationManagerModule
    using JulGame

    mutable struct LocalizationManager <: Script
        parent
        trackedElements::Dict{String, String}  # Maps UI element id -> localization key
        lastLanguage::String

        function LocalizationManager()
            this = new()
            this.trackedElements = Dict{String, String}()
            this.lastLanguage = ""
            return this
        end
    end

    """
    Check if a string looks like a localization key.
    Keys typically start with prefixes like UI_, Battle_, Shop_, Event_, etc.
    """
    function is_localization_key(key::String)
        prefixes = ["UI_", "Battle_", "Shop_", "Event_", "Map_", "Inventory_"]
        return any(startswith(key, prefix) for prefix in prefixes)
    end

    """
    Update a single UI element's text if it has a localization key.
    Returns true if the element was updated, false otherwise.
    """
    function update_ui_element_text(element, globals)
        return false
        if !(element isa JulGame.TextBoxModule.TextBox)
            @debug "Not a textbox, skipping $(element.name):$(element.id)"
            return false
        end
        @debug "Updating ui elements text"
        # Check if name or id is a localization key
        localization_key = nothing
        element_id = nothing

        if is_localization_key(element.name)
            @debug "element name $(element.name) is a localization key"
            localization_key = element.name
            element_id = element.id
        elseif is_localization_key(element.id)
            @debug "element id $(element.id) is a localization key"
            localization_key = element.id
            element_id = element.id
        end

        if localization_key !== nothing && element_id !== nothing
            # Get localized text (use current text as fallback)
            @debug "getting localized string for: $(element.name) text: $(element.text)"
            localized_text = globals.get_localized_string(localization_key, element.text)
            @debug "localized_text: $(localized_text)"
            # Update the text
            element.text = localized_text

            # Track this element for future language changes
            return true
        end

        return false
    end

    """
    Scan all UIElements in the current scene and update their text if they have localization keys.
    """
    function update_all_ui_texts(this::LocalizationManager, globals)
        scene = MAIN.scene
        # Clear tracking (will rebuild)
        empty!(this.trackedElements)

        updated_count = 0

        # Iterate through all UIElements in the scene
        for element in scene.uiElements
            if update_ui_element_text(element, globals)
                # Track this element
                if hasproperty(element, :id) && element.id !== nothing
                    key = is_localization_key(element.name) ? element.name :
                          (is_localization_key(element.id) ? element.id : "")
                    if key != ""
                        this.trackedElements[element.id] = key
                        updated_count += 1
                    end
                end
            end
        end

        @debug "LocalizationManager: Updated $updated_count text elements"

        # Store current language
        this.lastLanguage = globals.get_current_language()
    end

    """
    Update all tracked UI elements when language changes.
    """
    function refresh_localized_texts(this::LocalizationManager, globals, firstTime::Bool = false)
        current_language = globals.get_current_language()
        # Only refresh if language actually changed
        @debug "Checking current language"
        @debug "current_language: $current_language"
        @debug "this.lastLanguage: $(this.lastLanguage)"
        if current_language == this.lastLanguage && !firstTime
            @debug "skipping refresh"
            return
        end
        @debug "refreshing"
        @debug "LocalizationManager: Language changed from $(this.lastLanguage) to $(current_language), refreshing texts"

        # Re-scan and update all elements
        update_all_ui_texts(this, globals)

        this.lastLanguage = current_language
    end

    function JulGame.initialize(this::LocalizationManager)
        globals = JulGame.UserGlobals["Module"]

        # Wait a frame for scene to fully load
        # We'll do the initial scan in update()
        this.lastLanguage = globals.get_current_language()
        @debug "LocalizationManager: Last language set to $(this.lastLanguage)"
        refresh_localized_texts(this, globals, true)
        # Subscribe to language change events via Observer
        try
            globals.ObserverModule.add_observer((event, data) -> begin
                if event == :language_changed
                    @debug "LocalizationManager: Received language change notification"
                    refresh_localized_texts(this, globals)
                end
            end)
            @debug "LocalizationManager: Subscribed to language change events"
        catch e
            @warn "LocalizationManager: Failed to subscribe to language change events: $e"
        end

        @debug "LocalizationManager initialized"
    end

    function JulGame.update(this::LocalizationManager, deltaTime)
        globals = JulGame.UserGlobals["Module"]

        # Check if language changed
        current_language = globals.get_current_language()
        if current_language != this.lastLanguage
            @debug "current_language: $current_language"
            @debug "lastLanguage: $(this.lastLanguage)"
            refresh_localized_texts(this, globals)
        end
    end

    """
    Manually update a specific UI element by ID or name.
    Useful for dynamically created elements or elements accessed by code.
    """
    function update_element_by_key(this::LocalizationManager, element_id_or_name::String, globals)
        # Try to get element by ID first
        element = JulGame.SceneModule.get_ui_element_by_id(element_id_or_name)

        # If not found, try by name
        if element === nothing
            element = JulGame.SceneModule.get_ui_element_by_name(element_id_or_name)
        end

        if element !== nothing
            updated = update_ui_element_text(element, globals)
            if updated && hasproperty(element, :id) && element.id !== nothing
                # Extract the key from name or id
                key = is_localization_key(element.name) ? element.name :
                      (is_localization_key(element.id) ? element.id : element_id_or_name)
                this.trackedElements[element.id] = key
            end
            return updated
        end

        return false
    end

    export LocalizationManager, update_element_by_key, update_ui_element_text, is_localization_key
end
