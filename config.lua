Config = {}

-- Helicopter models the camera works in
Config.HeliModels = {
    joaat("polmav"),
    joaat("as350"),
}

-- Text shown in the top corners of the screen while in the camera
Config.HUD = {
    -- Used when the model/livery isn't listed below
    DefaultDepartmentName = "LOS SANTOS POLICE DEPARTMENT",

    -- Department name per model and livery index (0-based)
    DepartmentNames = {
        [joaat("as350")] = {
            [0] = "LOS ANGELES FIRE DEPARTMENT",
            [1] = "CALIFORNIA HIGHWAY PATROL",
            [2] = "LOS ANGELES POLICE DEPARTMENT",
            [3] = "LOS ANGELES SHERIFF'S DEPARTMENT",
        },
    },
}

-- Local client events triggered with false when the camera opens and true when it closes,
-- so other resources can hide their HUD. Leave empty if you don't need it.
Config.DisableEventsWhileHelicam = {
    "hud:toggle",
}

-- Default keys. Players who have already joined keep their own binding
-- (Settings > Key Bindings > FiveM).
Config.Keybinds = {
    ["toggle_helicam"] = {
        defaultKey = "B",
        description = "Toggle Helicam",
    },
    ["toggle_vision"] = {
        defaultMapper = "MOUSE_BUTTON",
        defaultKey = "MOUSE_RIGHT",
        description = "Toggle Vision (Helicam)",
    },
    ["toggle_display"] = {
        defaultKey = "Q",
        description = "Toggle Vehicle Info Display",
    },
    ["toggle_spotlight"] = {
        defaultKey = "U",
        description = "Toggle Spotlight",
    },
    ["toggle_lock_on"] = {
        defaultKey = "SPACE",
        description = "Toggle Camera Lock On",
    },
    ["toggle_rappel"] = {
        defaultKey = "X",
        description = "Rappel from Helicopter",
    },
    ["spotlight_light_up"] = {
        defaultKey = "UP",
        description = "Increase Spotlight Brightness",
    },
    ["spotlight_light_down"] = {
        defaultKey = "DOWN",
        description = "Decrease Spotlight Brightness",
    },
    ["spotlight_radius_up"] = {
        defaultKey = "RIGHT",
        description = "Increase Spotlight Radius",
    },
    ["spotlight_radius_down"] = {
        defaultKey = "LEFT",
        description = "Decrease Spotlight Radius",
    },
}