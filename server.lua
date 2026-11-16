-- FiveM Heli Cam by mraes, Version 1.3 (2017-06-12)
-- Modified by rjross2013 (2017-06-23)
-- Further modified by Loque (2017-08-15)
-- Converted to ox_lib keybinds by .exe Studios (filo) (2026-02-19)

-- Spotlight state bag on each helicopter:
-- { mode = "forward" | "manual" | "tracking", operator = serverId, brightness, radius,
--   target = netId, plate = string, paused = bool }
-- Manual and tracking beams are also streamed to nearby players further down.
local STATE_KEY = "helicamSpotlight"
local MIN_EVENT_INTERVAL = 50 -- ms between spotlight events from one player
local STREAM_INTERVAL = 100   -- ms between beam updates sent to nearby players
local STREAM_RANGE = 700.0    -- sent to players this close to the helicopter or to the lit spot
local MAX_AIM_DISTANCE = 2100.0

local activeHelis = {} -- [netId] = spot table while that helicopter has a spotlight on
local aimPoints = {}   -- [netId] = vector3 the manual spotlight is pointed at
local lastEvent = {}   -- [source] = GetGameTimer() of their last accepted event
local lastAim = {}     -- [source] = GetGameTimer() of their last accepted aim update

-- Returns the recognized helicopter the player is sitting in, and whether they are its pilot.
local function getHeli(playerSrc)
	local ped = GetPlayerPed(playerSrc)
	if ped == 0 then return nil end

	local veh = GetVehiclePedIsIn(ped, false)
	if veh == 0 then return nil end

	local model = GetEntityModel(veh)
	for _, allowed in ipairs(Config.HeliModels) do
		if model == allowed then
			return veh, GetPedInVehicleSeat(veh, -1) == ped
		end
	end
	return nil
end

local function throttled(playerSrc)
	local now = GetGameTimer()
	local last = lastEvent[playerSrc]
	if last and now - last < MIN_EVENT_INTERVAL then return true end
	lastEvent[playerSrc] = now
	return false
end

local function clamp(value, min, max, default)
	if type(value) ~= "number" or value ~= value then return default end
	return math.max(min, math.min(max, value))
end

local function saveSpotlight(heli, spot)
	local netID = NetworkGetNetworkIdFromEntity(heli)
	Entity(heli).state:set(STATE_KEY, spot, true)
	activeHelis[netID] = spot
	if spot.mode ~= "manual" then
		aimPoints[netID] = nil
	end
end

local function clearSpotlight(heli)
	local netID = NetworkGetNetworkIdFromEntity(heli)
	Entity(heli).state:set(STATE_KEY, nil, true)
	activeHelis[netID] = nil
	aimPoints[netID] = nil
end

RegisterNetEvent("helicam:setSpotlight", function(mode, brightness, radius, targetNetID, plate, paused)
	local src = source
	local heli, isPilot = getHeli(src)
	if not heli then return end

	-- switching off is never throttled, so a light can't get stuck on
	if mode == "off" then
		if Entity(heli).state[STATE_KEY] then
			clearSpotlight(heli)
		end
		return
	end

	if throttled(src) then return end
	if mode ~= "forward" and mode ~= "manual" and mode ~= "tracking" then return end
	if mode == "forward" and not isPilot then return end

	local spot = {
		mode = mode,
		operator = src,
		brightness = clamp(brightness, 1.0, 10.0, 1.0),
		radius = clamp(radius, 4.0, 10.0, 4.0),
	}

	if mode == "tracking" then
		-- passed on to other clients, so type-check rather than trust
		if math.type(targetNetID) ~= "integer" then return end
		if type(plate) ~= "string" or #plate > 16 then return end
		spot.target = targetNetID
		spot.plate = plate
		spot.paused = paused == true
	end

	saveSpotlight(heli, spot)
end)

RegisterNetEvent("helicam:pauseSpotlight", function(paused)
	local src = source
	if throttled(src) then return end

	local heli = getHeli(src)
	if not heli then return end

	local spot = Entity(heli).state[STATE_KEY]
	if not spot or spot.mode ~= "tracking" then return end

	spot.paused = paused == true
	saveSpotlight(heli, spot)
end)

RegisterNetEvent("helicam:spotlightSettings", function(brightness, radius)
	local src = source
	if throttled(src) then return end

	local heli = getHeli(src)
	if not heli then return end

	local spot = Entity(heli).state[STATE_KEY]
	if not spot then return end

	spot.brightness = clamp(brightness, 1.0, 10.0, spot.brightness)
	spot.radius = clamp(radius, 4.0, 10.0, spot.radius)
	saveSpotlight(heli, spot)
end)

-- Where the manual spotlight is pointed. Sent by whoever is operating it, about ten times a second.
RegisterNetEvent("helicam:aim", function(aim)
	local src = source
	if type(aim) ~= "vector3" then return end

	local now = GetGameTimer()
	local last = lastAim[src]
	if last and now - last < MIN_EVENT_INTERVAL then return end
	lastAim[src] = now

	local heli = getHeli(src)
	if not heli then return end

	local netID = NetworkGetNetworkIdFromEntity(heli)
	local spot = activeHelis[netID]
	if not spot or spot.mode ~= "manual" or spot.operator ~= src then return end
	if #(GetEntityCoords(heli) - aim) > MAX_AIM_DISTANCE then return end

	aimPoints[netID] = aim
end)

-- Stream each manual/tracking beam to the players close enough to see it.
CreateThread(function()
	while true do
		if not next(activeHelis) then
			Wait(500)
		else
			Wait(STREAM_INTERVAL)

			local players = nil

			for netID, spot in pairs(activeHelis) do
				local heli = NetworkGetEntityFromNetworkId(netID)

				if heli ~= 0 and DoesEntityExist(heli) and spot.mode ~= "forward" and not spot.paused then
					local aim = nil

					if spot.mode == "manual" then
						aim = aimPoints[netID]
					else
						local target = NetworkGetEntityFromNetworkId(spot.target)
						if target ~= 0 and DoesEntityExist(target) then
							aim = GetEntityCoords(target)
						end
					end

					if aim then
						local heliCoords = GetEntityCoords(heli)

						if not players then
							players = {}
							for _, playerId in ipairs(GetPlayers()) do
								local ped = GetPlayerPed(playerId)
								if ped ~= 0 then
									players[#players + 1] = { id = tonumber(playerId), coords = GetEntityCoords(ped) }
								end
							end
						end

						for i = 1, #players do
							local player = players[i]
							if #(player.coords - heliCoords) < STREAM_RANGE or #(player.coords - aim) < STREAM_RANGE then
								TriggerClientEvent("helicam:beam", player.id, netID, spot.mode, spot.operator,
									heliCoords, aim, spot.brightness, spot.radius, spot.target)
							end
						end
					end
				end
			end
		end
	end
end)

-- Switch a spotlight off once whoever turned it on has left the helicopter or the server.
CreateThread(function()
	while true do
		Wait(1000)

		for netID, spot in pairs(activeHelis) do
			local heli = NetworkGetEntityFromNetworkId(netID)

			if heli == 0 or not DoesEntityExist(heli) then
				activeHelis[netID] = nil
				aimPoints[netID] = nil
			else
				local operatorPed = GetPlayerPed(spot.operator)
				if operatorPed == 0 or GetVehiclePedIsIn(operatorPed, false) ~= heli then
					clearSpotlight(heli)
				end
			end
		end
	end
end)

AddEventHandler("playerDropped", function()
	lastEvent[source] = nil
	lastAim[source] = nil
end)
