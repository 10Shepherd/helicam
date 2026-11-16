-- FiveM Heli Cam by mraes, version 1.3 (2017-06-12)
-- Modified by rjross2013 (2017-06-23)
-- Further modified by Loque (2017-08-15) with credits to the following for tips gleaned from their scripts: Guadmaz's Simple Police Searchlight, devilkkw's Speed Camera, nynjardin's Simple Outlaw Alert and IllidanS4's FiveM Entity Iterators.
-- Converted to ox_lib keybinds by .exe Studios (filo) (2026-02-19)

---=========================
--- Config				====
---=========================
local fov_max = 80.0
local fov_min = 5.0 -- max zoom level (smaller fov is more zoom)
local zoomspeed = 3.0 -- camera zoom speed
local speed_lr = 4.0 -- speed by which the camera pans left-right
local speed_ud = 4.0 -- speed by which the camera pans up-down
local maxtargetdistance = 700 -- max distance at which target lock is maintained
local brightness = 1.0 -- default spotlight brightness
local spotradius = 4.0 -- default manual spotlight radius
local speed_measure = "Km/h" -- default unit to measure vehicle speed. Use either "Km/h" or "MPH".

local heliModels = Config.HeliModels

local helicamKeybinds = {}

---=========================
--- State				====
---=========================
local currentHeli = nil
local helicamThreadRunning = false -- stops a second heli thread from starting
local target_vehicle = nil
local target_plate = nil
local target_flagged = false -- true if this script marked the target as a mission entity itself
local vehicle_display = 0 -- 0 = full info, 1 = model/plate only, 2 = off
local helicam = false
local fov = (fov_max + fov_min) * 0.5
local vision_state = 0 -- 0 = normal, 1 = nightvision, 2 = thermal

-- Shared with the keybind callbacks
local helicamState = { cam = nil, locked_on_vehicle = nil }

-- Spotlight state bag on the helicopter, set by server.lua (fields are listed there)
local function currentSpot()
    if not currentHeli or not DoesEntityExist(currentHeli) then return nil end
    return Entity(currentHeli).state.helicamSpotlight
end

local function requestSpotlight(mode, paused)
    local netID, plate
    if mode == "tracking" then
        if not target_vehicle or not DoesEntityExist(target_vehicle) then return end
        netID = VehToNet(target_vehicle)
        plate = GetVehicleNumberPlateText(target_vehicle)
    end
    TriggerServerEvent("helicam:setSpotlight", mode, brightness, spotradius, netID, plate, paused == true)
end

local AIM_SEND_INTERVAL = 100 -- ms between manual spotlight aim updates sent to the server
local lastAimSent = 0

local function adjustSpotlight(brightnessDelta, radiusDelta)
    local newBrightness = math.max(1.0, math.min(10.0, brightness + brightnessDelta))
    local newRadius = math.max(4.0, math.min(10.0, spotradius + radiusDelta))
    if newBrightness == brightness and newRadius == spotradius then return end

    brightness, spotradius = newBrightness, newRadius
    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    TriggerServerEvent("helicam:spotlightSettings", brightness, spotradius)
end

AddEventHandler("onClientResourceStart", function(resource)
    if resource ~= cache.resource then return end
    DecorRegister("Target", 3)
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource ~= cache.resource then return end
    if helicamState.cam then
        RenderScriptCams(false, false, 0, 1, 0)
        DestroyCam(helicamState.cam, false)
        for _, eventName in ipairs(Config.DisableEventsWhileHelicam) do
            TriggerEvent(eventName, true)
        end
    end
    ClearTimecycleModifier()
    SetNightvision(false)
    SetSeethrough(false)
end)

---=========================
--- Helper Functions	====
---=========================

local function RotAnglesToVec(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function ChangeVision()
    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    if vision_state == 0 then
        SetNightvision(true)
        vision_state = 1
    elseif vision_state == 1 then
        SetNightvision(false)
        SetSeethrough(true)
        vision_state = 2
    else
        SetSeethrough(false)
        vision_state = 0
    end
end

local function ChangeDisplay()
    if vehicle_display == 0 then
        vehicle_display = 1
    elseif vehicle_display == 1 then
        vehicle_display = 2
    else
        vehicle_display = 0
    end
end

local function HideHUDThisFrame()
    HideHelpTextThisFrame()
    HideHudAndRadarThisFrame()
    HideHudComponentThisFrame(19) -- weapon wheel
    HideHudComponentThisFrame(1)  -- Wanted Stars
    HideHudComponentThisFrame(2)  -- Weapon icon
    HideHudComponentThisFrame(3)  -- Cash
    HideHudComponentThisFrame(4)  -- MP CASH
    HideHudComponentThisFrame(13) -- Cash Change
    HideHudComponentThisFrame(11) -- Floating Help Text
    HideHudComponentThisFrame(12) -- more floating help text
    HideHudComponentThisFrame(15) -- Subtitle Text
    HideHudComponentThisFrame(18) -- Game Stream
end

local function CheckInputRotation(cam, zoomvalue)
    local rightAxisX = GetDisabledControlNormal(0, 220)
    local rightAxisY = GetDisabledControlNormal(0, 221)
    local rotation = GetCamRot(cam, 2)
    if rightAxisX ~= 0.0 or rightAxisY ~= 0.0 then
        local new_z = rotation.z + rightAxisX * -1.0 * speed_ud * (zoomvalue + 0.1)
        local new_x = math.max(math.min(20.0, rotation.x + rightAxisY * -1.0 * speed_lr * (zoomvalue + 0.1)), -89.5)
        SetCamRot(cam, new_x, 0.0, new_z, 2)
    end
end

local function HandleZoom(cam)
    if IsControlJustPressed(0, 241) then -- Scroll up
        fov = math.max(fov - zoomspeed, fov_min)
    end
    if IsControlJustPressed(0, 242) then -- Scroll down
        fov = math.min(fov + zoomspeed, fov_max)
    end
    local current_fov = GetCamFov(cam)
    if math.abs(fov - current_fov) < 0.1 then
        fov = current_fov
    end
    SetCamFov(cam, current_fov + (fov - current_fov) * 0.05)
end

local function GetVehicleInView(cam)
    local coords = GetCamCoord(cam)
    local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
    local rayhandle = CastRayPointToPoint(coords, coords + (forward_vector * 200.0), 10, cache.vehicle, 0)
    local _, _, _, _, entityHit = GetRaycastResult(rayhandle)
    if entityHit > 0 and IsEntityAVehicle(entityHit) then
        return entityHit
    end
end

local function RenderVehicleInfo(vehicle)
    if not DoesEntityExist(vehicle) then return end
    local model = GetEntityModel(vehicle)
    local vehname = GetLabelText(GetDisplayNameFromVehicleModel(model))
    local licenseplate = GetVehicleNumberPlateText(vehicle)
    local vehspeed = GetEntitySpeed(vehicle) * (speed_measure == "MPH" and 2.236936 or 3.6)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextScale(0.0, vehicle_display == 0 and 0.49 or 0.55)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    if vehicle_display == 0 then
        AddTextComponentString(("Speed: %d %s\nModel: %s\nPlate: %s"):format(math.ceil(vehspeed), speed_measure, vehname, licenseplate))
    else
        AddTextComponentString(("Model: %s\nPlate: %s"):format(vehname, licenseplate))
    end
    DrawText(0.45, 0.9)
end

local function GetLocationLabel(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if street ~= "" then
        return ("%s - %s"):format(street, zone)
    end
    return zone
end

local function GetDepartmentName(heli)
    local liveries = Config.HUD.DepartmentNames[GetEntityModel(heli)]
    if liveries then
        local name = liveries[GetVehicleLivery(heli)]
        if name then return name end
    end
    return Config.HUD.DefaultDepartmentName
end

local cardinalPoints = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function GetCardinalDirection(heading)
    local index = math.floor((heading % 360.0) / 45.0 + 0.5) % 8 + 1
    return cardinalPoints[index]
end

-- Direction, road, cross street and postal of the locked vehicle. "---" where unknown.
local travelInfoCache = { vehicle = nil, expires = 0, info = nil }
local function GetVehicleTravelInfo(vehicle)
    local now = GetGameTimer()
    if travelInfoCache.vehicle == vehicle and now < travelInfoCache.expires then
        return travelInfoCache.info
    end

    local coords = GetEntityCoords(vehicle)
    local streetHash, crossHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local cross = GetStreetNameFromHashKey(crossHash)

    local ok, postal = false, nil
    if GetResourceState("nearest-postal") == "started" then
        ok, postal = pcall(function()
            return exports['nearest-postal']:getPostalAtCoords(coords.x, coords.y)
        end)
    end

    local info = {
        direction = GetCardinalDirection(GetEntityHeading(vehicle)),
        street = street ~= "" and street or "---",
        cross = cross ~= "" and cross or "---",
        postal = (ok and postal) or "---",
    }

    travelInfoCache.vehicle = vehicle
    travelInfoCache.expires = now + 500
    travelInfoCache.info = info
    return info
end

-- The point on the map the crosshair is looking at (map geometry only)
local function GetCrosshairGroundHit(cam)
    local coords = GetCamCoord(cam)
    local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
    local rayhandle = CastRayPointToPoint(coords, coords + (forward_vector * 2000.0), 1, cache.vehicle, 0)
    local hit, endCoords = GetRaycastResult(rayhandle)
    if hit == 1 then
        return endCoords
    end
    return nil
end

local function RenderHeliHUD(heli, cam)
    local heliCoords = GetEntityCoords(heli)
    local groundHit = GetCrosshairGroundHit(cam)

    local heliSpeed = GetEntitySpeed(heli) * 1.943844 -- m/s to knots
    local heliHeading = GetEntityHeading(heli)
    local heliAlt = heliCoords.z * 3.28084 -- game units to feet

    local locked = helicamState.locked_on_vehicle
    local travelInfo
    if locked and DoesEntityExist(locked) then
        travelInfo = GetVehicleTravelInfo(locked)
    else
        travelInfo = { direction = "---", street = "---", cross = "---", postal = "---" }
    end

    local elevationText, slantRangeText, targetLocation
    if groundHit then
        elevationText = ("%d FT"):format(math.floor(groundHit.z * 3.28084))
        slantRangeText = ("%d M"):format(math.floor(#(heliCoords - groundHit)))
        targetLocation = GetLocationLabel(groundHit)
    else
        elevationText = "--- FT"
        slantRangeText = "--- M"
        targetLocation = "---"
    end

    local day, month, year = GetClockDayOfMonth(), GetClockMonth() + 1, GetClockYear()
    local hour, minute, second = GetClockHours(), GetClockMinutes(), GetClockSeconds()

    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.55)
    SetTextColour(255, 255, 255, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString((
        "%s\n%s\nSPD   %d KTS   HDG   %03d °T\nALT   %d FT\n\n%02d/%02d/%02d\n%02d:%02d:%02d Z"
    ):format(
        GetDepartmentName(heli),
        GetLocationLabel(heliCoords),
        math.floor(heliSpeed), math.floor(heliHeading),
        math.floor(heliAlt),
        day, month, year % 100,
        hour, minute, second
    ))
    DrawText(0.04, 0.03)

    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.55)
    SetTextColour(255, 255, 255, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextJustification(2) -- right-aligned
    SetTextWrap(0.0, 0.96)
    SetTextEntry("STRING")
    AddTextComponentString((
        "%s\nDIR   %s   RD   %s\nXST   %s   PSTL   %s\nELV   %s\nSLT   %s"
    ):format(targetLocation, travelInfo.direction, travelInfo.street, travelInfo.cross, travelInfo.postal, elevationText, slantRangeText))
    DrawText(0.0, 0.03)
end

-- Keeps a locked vehicle from despawning. Vehicles that are already mission entities
-- (e.g. a player's own car) are left as they are.
local function FlagTarget(vehicle)
    DecorSetInt(vehicle, "Target", 2)
    if IsEntityAMissionEntity(vehicle) then return end

    NetworkRequestControlOfEntity(vehicle)
    local attempts = 0
    while not NetworkHasControlOfEntity(vehicle) and attempts < 50 do
        Wait(0)
        attempts = attempts + 1
    end
    if not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then return end

    SetNetworkIdCanMigrate(VehToNet(vehicle), true)
    SetEntityAsMissionEntity(vehicle, true, true)
    target_flagged = true
end

local function ClearTargetFlags()
    if target_vehicle and DoesEntityExist(target_vehicle) then
        DecorRemove(target_vehicle, "Target")
        if target_flagged then
            SetEntityAsMissionEntity(target_vehicle, false, true)
        end
    end
    target_flagged = false
end

local function ReleaseTarget()
    ClearTargetFlags()

    local spot = currentSpot()
    if spot and spot.mode == "tracking" and spot.operator == cache.serverId then
        requestSpotlight("off")
    end

    target_vehicle = nil
    target_plate = nil
    helicamState.locked_on_vehicle = nil
end

local function BuildFreeCam(heli, rot, saved_fov)
    local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    AttachCamToEntity(cam, heli, 0.0, 0.0, -1.5, true)
    SetCamRot(cam, rot, 2)
    SetCamFov(cam, saved_fov)
    RenderScriptCams(true, false, 0, 1, 0)
    return cam
end

---=========================
--- Helicam Render Loop	====
---=========================

local function startHelicamLoop(heli)
    local lPed = cache.ped

    for _, eventName in ipairs(Config.DisableEventsWhileHelicam) do
        TriggerEvent(eventName, false)
    end

    SetTimecycleModifier("heliGunCam")
    SetTimecycleModifierStrength(0.3)

    local scaleform = RequestScaleformMovie("HELI_CAM")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end

    local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    AttachCamToEntity(cam, heli, 0.0, 0.0, -1.5, true)
    SetCamRot(cam, 0.0, 0.0, GetEntityHeading(heli))
    SetCamFov(cam, fov)
    RenderScriptCams(true, false, 0, 1, 0)

    PushScaleformMovieFunction(scaleform, "SET_CAM_LOGO")
    PushScaleformMovieFunctionParameterInt(0) -- 0 = no logo, 1 = LSPD
    PopScaleformMovieFunctionVoid()

    helicamState.cam = cam
    helicamState.locked_on_vehicle = nil

    while helicam and not IsEntityDead(lPed) and GetVehiclePedIsIn(lPed) == heli and GetEntityHeightAboveGround(heli) >= 1.5 do
        -- Sync cam reference in case an onPressed callback swapped it (e.g. lock-off rebuilds cam)
        cam = helicamState.cam

        local zoomvalue = (1.0 / (fov_max - fov_min)) * (fov - fov_min)
        local locked = helicamState.locked_on_vehicle

        if locked then
            if DoesEntityExist(locked) then
                PointCamAtEntity(cam, locked, 0.0, 0.0, 0.0, true)
                RenderVehicleInfo(locked)

                -- Auto-release if target flies out of range
                local dist = #(GetEntityCoords(heli) - GetEntityCoords(locked))
                if dist > maxtargetdistance then
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                    ReleaseTarget()
                    -- Rebuild free cam at current angle
                    local rot = GetCamRot(cam, 2)
                    local saved_fov = GetCamFov(cam)
                    DestroyCam(cam, false)
                    cam = BuildFreeCam(heli, rot, saved_fov)
                    helicamState.cam = cam
                end
            else
                -- Entity deleted
                ReleaseTarget()
            end
        else
            CheckInputRotation(cam, zoomvalue)
            local vehicle_detected = GetVehicleInView(cam)
            if vehicle_detected and DoesEntityExist(vehicle_detected) then
                RenderVehicleInfo(vehicle_detected)
            end
        end

        HandleZoom(cam)
        HideHUDThisFrame()
        RenderHeliHUD(heli, cam)

        PushScaleformMovieFunction(scaleform, "SET_ALT_FOV_HEADING")
        PushScaleformMovieFunctionParameterFloat(GetEntityCoords(heli).z)
        PushScaleformMovieFunctionParameterFloat(zoomvalue)
        PushScaleformMovieFunctionParameterFloat(GetCamRot(cam, 2).z)
        PopScaleformMovieFunctionVoid()
        DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)

        local spot = Entity(heli).state.helicamSpotlight
        if spot and spot.mode == "manual" and spot.operator == cache.serverId then
            local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
            local camcoords = GetCamCoord(cam)
            DrawSpotLight(camcoords, forward_vector, 255, 255, 255, 800.0, 10.0, brightness, spotradius, 1.0, 1.0)

            -- Tell the server where the light is pointed so everyone else can draw it
            local now = GetGameTimer()
            if now - lastAimSent >= AIM_SEND_INTERVAL then
                lastAimSent = now
                local aim = GetCrosshairGroundHit(cam) or (camcoords + forward_vector * 800.0)
                TriggerServerEvent("helicam:aim", aim)
            end
        end

        Wait(0)
    end

    -- Cleanup
    for _, eventName in ipairs(Config.DisableEventsWhileHelicam) do
        TriggerEvent(eventName, true)
    end
    -- Manual spotlight still on: switch to tracking if a vehicle is locked, otherwise off
    local spot = currentSpot()
    if spot and spot.mode == "manual" and spot.operator == cache.serverId then
        if target_vehicle and DoesEntityExist(target_vehicle) and GetVehiclePedIsIn(lPed) == heli then
            requestSpotlight("tracking")
        else
            requestSpotlight("off")
        end
    end
    helicam = false
    helicamState.cam = nil
    helicamState.locked_on_vehicle = nil
    ClearTimecycleModifier()
    fov = (fov_max + fov_min) * 0.5
    RenderScriptCams(false, false, 0, 1, 0)
    SetScaleformMovieAsNoLongerNeeded(scaleform)
    DestroyCam(cam, false)
    SetNightvision(false)
    SetSeethrough(false)
    vision_state = 0
end

---=========================
--- Vehicle Cache		====
--- Spawns the heli thread only while in a valid heli model.
--- No thread runs when the player is not in a recognised heli.
---=========================

lib.onCache("vehicle", function(vehicle)
    if not vehicle then
        -- Left the vehicle. The server switches the spotlight off.
        if helicam then helicam = false end
        ClearTargetFlags()
        target_vehicle = nil
        target_plate = nil
        helicamState.locked_on_vehicle = nil
        currentHeli = nil

		for _, keybind in ipairs(helicamKeybinds) do
			keybind:disable(true)
		end

        return
    end

    if not lib.table.contains(heliModels, GetEntityModel(vehicle)) then return end

	for _, keybind in ipairs(helicamKeybinds) do
		keybind:disable(false)
	end
    currentHeli = vehicle

    if helicamThreadRunning then return end
    helicamThreadRunning = true

    CreateThread(function()
        while currentHeli do
            -- Outside helicam: check if tracked target has gone out of range
            if not helicam and target_vehicle then
                local dist = #(GetEntityCoords(currentHeli) - GetEntityCoords(target_vehicle))
                if dist > maxtargetdistance then
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                    ReleaseTarget()
                end
            end

            -- Render target info overlay outside helicam
            if not helicam and target_vehicle and vehicle_display ~= 2 then
                RenderVehicleInfo(target_vehicle)
            end

            -- When helicam is activated, hand off to the render loop (blocks here until helicam exits)
            if helicam then
                startHelicamLoop(currentHeli)
            end

            -- Light wait: all discrete input is event-driven via onPressed keybinds.
            -- We only need this loop for the distance check and info overlay.
            Wait(0)
        end

        helicamThreadRunning = false
    end)
end)

---=========================
--- Keybinds			====
---=========================

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_helicam',
    description = Config.Keybinds["toggle_helicam"].description,
    defaultKey = Config.Keybinds["toggle_helicam"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_helicam"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        if GetEntityHeightAboveGround(currentHeli) < 1.5 then return end
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
        if helicam then
            helicam = false -- signals startHelicamLoop to exit
        else
            helicam = true -- thread will pick this up and call startHelicamLoop
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_vision',
    description = Config.Keybinds["toggle_vision"].description,
    defaultMapper = Config.Keybinds["toggle_vision"].defaultMapper,
    defaultKey = Config.Keybinds["toggle_vision"].defaultKey,
	disabled = true,
    onPressed = function()
        if not currentHeli or not helicam then return end
        ChangeVision()
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_display',
    description = Config.Keybinds["toggle_display"].description,
    defaultKey = Config.Keybinds["toggle_display"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_display"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        ChangeDisplay()
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_spotlight',
    description = Config.Keybinds["toggle_spotlight"].description,
    defaultKey = Config.Keybinds["toggle_spotlight"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_spotlight"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end

        local spot = currentSpot()
        local mode = spot and spot.mode or "off"

        if helicam then
            -- Inside helicam (any seat): toggle the manual spotlight that follows the camera
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            if mode == "manual" and spot.operator == cache.serverId then
                requestSpotlight("off")
            else
                lastAimSent = 0
                requestSpotlight("manual")
            end
            return
        end

        -- Outside helicam: pilot only
        if GetPedInVehicleSeat(currentHeli, -1) ~= cache.ped then return end
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)

        if mode == "tracking" then
            TriggerServerEvent("helicam:pauseSpotlight", not spot.paused)
        elseif target_vehicle and DoesEntityExist(target_vehicle) then
            requestSpotlight("tracking")
        elseif mode == "off" then
            requestSpotlight("forward")
        else
            requestSpotlight("off")
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_lock_on',
    description = Config.Keybinds["toggle_lock_on"].description,
    defaultKey = Config.Keybinds["toggle_lock_on"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_lock_on"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end

        if helicam then
            local locked = helicamState.locked_on_vehicle
            if locked then
                -- Release lock
                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                ReleaseTarget()
                -- Rebuild free cam so we can pan freely again
                local cam = helicamState.cam
                if cam then
                    local rot = GetCamRot(cam, 2)
                    local saved_fov = GetCamFov(cam)
                    DestroyCam(cam, false)
                    helicamState.cam = BuildFreeCam(currentHeli, rot, saved_fov)
                end
            else
                -- Lock on to whatever vehicle is in the camera's crosshair
                local cam = helicamState.cam
                if not cam then return end
                local detected = GetVehicleInView(cam)
                if not detected then return end

                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)

                local spot = currentSpot()
                local wasTracking = spot and spot.mode == "tracking" and spot.operator == cache.serverId
                local wasPaused = wasTracking and spot.paused

                -- Drop the previous target before taking the new one
                ClearTargetFlags()

                target_vehicle = detected
                target_plate = GetVehicleNumberPlateText(target_vehicle)
                FlagTarget(target_vehicle)
                helicamState.locked_on_vehicle = target_vehicle

                if wasTracking then
                    -- Re-target the tracking spotlight to the new vehicle
                    requestSpotlight(wasPaused and "off" or "tracking")
                end
            end
        else
            -- Outside helicam: manually release target
            if not target_vehicle then return end
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            ReleaseTarget()
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_rappel',
    description = Config.Keybinds["toggle_rappel"].description,
    defaultKey = Config.Keybinds["toggle_rappel"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_rappel"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        if GetEntityHeightAboveGround(currentHeli) < 1.5 then return end
        local lPed = cache.ped
        if GetPedInVehicleSeat(currentHeli, 1) == lPed or GetPedInVehicleSeat(currentHeli, 2) == lPed then
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            TaskRappelFromHeli(lPed, 1)
        else
            SetNotificationTextEntry("STRING")
            AddTextComponentString("~r~Can't rappel from this seat")
            DrawNotification(false, false)
            PlaySoundFrontend(-1, "5_Second_Timer", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", false)
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_light_up',
    description = Config.Keybinds["spotlight_light_up"].description,
    defaultKey = Config.Keybinds["spotlight_light_up"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_light_up"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        adjustSpotlight(1.0, 0.0)
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_light_down',
    description = Config.Keybinds["spotlight_light_down"].description,
    defaultKey = Config.Keybinds["spotlight_light_down"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_light_down"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        adjustSpotlight(-1.0, 0.0)
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_radius_up',
    description = Config.Keybinds["spotlight_radius_up"].description,
    defaultKey = Config.Keybinds["spotlight_radius_up"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_radius_up"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        adjustSpotlight(0.0, 1.0)
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_radius_down',
    description = Config.Keybinds["spotlight_radius_down"].description,
    defaultKey = Config.Keybinds["spotlight_radius_down"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_radius_down"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        adjustSpotlight(0.0, -1.0)
    end
})

---=========================
--- Spotlight Rendering	====
---=========================
-- server.lua sends the helicopter position and aim point of each manual/tracking beam to
-- nearby players. Updates are blended so the beam moves smoothly. If the helicopter or
-- target is streamed here, its real position is used instead.

local BEAM_INTERVAL = 100 -- ms between updates from the server (STREAM_INTERVAL in server.lua)
local BEAM_TIMEOUT = 500  -- ms without an update before a beam is dropped

local beams = {} -- [heli netId] = beam
local beamThreadRunning = false

local function blend(from, to, updated, now)
    local t = (now - updated) / BEAM_INTERVAL
    if t >= 1.0 then return to end
    return from + (to - from) * t
end

local function drawBeam(netID, beam, now)
    -- the operator draws their own manual beam straight from the camera in the helicam loop
    if beam.mode == "manual" and beam.operator == cache.serverId then return end

    local origin
    if NetworkDoesEntityExistWithNetworkId(netID) then
        local heli = NetToVeh(netID)
        if DoesEntityExist(heli) then
            origin = GetEntityCoords(heli)
        end
    end
    origin = origin or blend(beam.heliFrom, beam.heliTo, beam.updated, now)

    if beam.mode == "manual" then
        origin = origin + vector3(0.0, 0.0, -1.5)
        local direction = blend(beam.aimFrom, beam.aimTo, beam.updated, now) - origin
        local length = #direction
        if length < 0.1 then return end
        direction = direction / length

        DrawSpotLight(origin.x, origin.y, origin.z, direction.x, direction.y, direction.z,
            255, 255, 255, 800.0, 10.0, beam.brightness, beam.radius, 1.0, 1.0)
        return
    end

    local targetCoords
    if beam.target and NetworkDoesEntityExistWithNetworkId(beam.target) then
        local target = NetToVeh(beam.target)
        if DoesEntityExist(target) then
            targetCoords = GetEntityCoords(target)
        end
    end
    targetCoords = targetCoords or blend(beam.aimFrom, beam.aimTo, beam.updated, now)

    local direction = targetCoords - origin
    local length = #direction
    if length < 0.1 then return end
    direction = direction / length

    DrawSpotLight(origin.x, origin.y, origin.z, direction.x, direction.y, direction.z,
        255, 255, 255, length + 20.0, 10.0, beam.brightness, 4.0, 1.0, 0.0)
end

local function startBeamThread()
    if beamThreadRunning then return end
    beamThreadRunning = true

    CreateThread(function()
        while next(beams) do
            local now = GetGameTimer()

            for netID, beam in pairs(beams) do
                if now - beam.updated > BEAM_TIMEOUT then
                    beams[netID] = nil
                else
                    drawBeam(netID, beam, now)
                end
            end

            Wait(0)
        end

        beamThreadRunning = false
    end)
end

RegisterNetEvent("helicam:beam", function(netID, mode, operator, heliCoords, aim, beamBrightness, beamRadius, targetNetID)
    if source == "" then return end
    if type(heliCoords) ~= "vector3" or type(aim) ~= "vector3" then return end

    local now = GetGameTimer()
    local beam = beams[netID]

    if beam and beam.mode == mode then
        -- carry on from wherever the blend currently is, so there is no jump
        beam.heliFrom = blend(beam.heliFrom, beam.heliTo, beam.updated, now)
        beam.aimFrom = blend(beam.aimFrom, beam.aimTo, beam.updated, now)
    else
        beam = { heliFrom = heliCoords, aimFrom = aim }
        beams[netID] = beam
    end

    beam.mode = mode
    beam.operator = operator
    beam.heliTo = heliCoords
    beam.aimTo = aim
    beam.brightness = (tonumber(beamBrightness) or 1.0) + 0.0
    beam.radius = (tonumber(beamRadius) or 4.0) + 0.0
    beam.target = targetNetID
    beam.updated = now

    startBeamThread()
end)

---=========================
--- Forward Searchlight	====
---=========================
-- The helicopter's built-in light, switched from the state bag on the helicopter.

local forwardLights = {} -- [bagName] = GetGameTimer() the helicopter was last seen
local forwardThreadRunning = false

local function startForwardThread()
    if forwardThreadRunning then return end
    forwardThreadRunning = true

    CreateThread(function()
        while next(forwardLights) do
            local now = GetGameTimer()

            for bagName, lastSeen in pairs(forwardLights) do
                local heli = GetEntityFromStateBagName(bagName)

                if heli ~= 0 and DoesEntityExist(heli) then
                    local spot = Entity(heli).state.helicamSpotlight
                    if not spot or spot.mode ~= "forward" then
                        -- switched off, or a different entity is using this bag name now
                        forwardLights[bagName] = nil
                    else
                        forwardLights[bagName] = now
                        if not IsVehicleSearchlightOn(heli) then
                            SetVehicleSearchlight(heli, true, false)
                        end
                    end
                elseif now - lastSeen > 300000 then
                    -- not seen for five minutes; the state is sent again if it comes back into range
                    forwardLights[bagName] = nil
                end
            end

            Wait(500)
        end

        forwardThreadRunning = false
    end)
end

local function setForwardLight(bagName, value)
    if value and value.mode == "forward" then
        forwardLights[bagName] = GetGameTimer()
        startForwardThread()
        return
    end

    if forwardLights[bagName] then
        forwardLights[bagName] = nil
        local heli = GetEntityFromStateBagName(bagName)
        if heli ~= 0 and DoesEntityExist(heli) then
            SetVehicleSearchlight(heli, false, false)
        end
    end
end

AddStateBagChangeHandler("helicamSpotlight", nil, function(bagName, _, value)
    if bagName:sub(1, 7) ~= "entity:" then return end
    setForwardLight(bagName, value)
end)

-- Pick up searchlights that were already on when this resource (re)started.
CreateThread(function()
    Wait(1000)
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        if NetworkGetEntityIsNetworked(vehicle) then
            local value = Entity(vehicle).state.helicamSpotlight
            if value then
                setForwardLight(("entity:%d"):format(NetworkGetNetworkIdFromEntity(vehicle)), value)
            end
        end
    end
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource ~= cache.resource then return end
    ClearTargetFlags()
end)
