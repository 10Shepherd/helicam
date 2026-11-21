# helicam

A helicopter camera for FiveM with night and thermal vision, vehicle lock-on,
an on-screen flight display and a spotlight that other players can see. No
framework needed.

## Features

- **Camera**: a camera under the helicopter that pans with the mouse and
  zooms with the scroll wheel. Works from any seat while the helicopter is
  off the ground.
- **Vision modes**: normal, night vision and thermal.
- **Vehicle info**: speed, model and plate of the vehicle under the
  crosshair or locked on.
- **Lock-on**: lock the camera to a vehicle. It stays locked up to 700 m
  away and keeps showing the vehicle's info after you leave the camera.
- **Flight display**: department name, location, speed, heading and altitude
  of the helicopter, plus the location, elevation and distance of the point
  the camera is looking at. With a vehicle locked it also shows its direction
  of travel, road, cross street and postal.
- **Spotlight**, one per helicopter:
  - manual: follows the camera, usable from any seat
  - tracking: follows the locked vehicle, can be paused
  - forward: the helicopter's own searchlight
- **Synced beams**: the manual and tracking beams are sent to every player
  within 700 m of the helicopter or of the lit spot, so people on the ground
  see the light even when the helicopter is far away.
- **Rappel** from the rear seats.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- OneSync enabled
- Optional: [nearest-postal](https://github.com/DevBlocky/nearest-postal) for
  the postal on the flight display

## Installation

1. Put the folder in your `resources` directory.
2. Add to `server.cfg`, after `ox_lib`:

   ```cfg
   ensure helicam
   ```

3. List your helicopter models in `config.lua` (`Config.HeliModels`).

## Configuration

Everything is in `config.lua`.

| Setting                            | What it controls                                                       |
| ---------------------------------- | ---------------------------------------------------------------------- |
| `Config.HeliModels`                | Helicopter models the camera works in                                  |
| `Config.HUD.DefaultDepartmentName` | Department name on the flight display                                  |
| `Config.HUD.DepartmentNames`       | Department name per model and livery                                   |
| `Config.DisableEventsWhileHelicam` | Local events triggered when the camera opens and closes, to hide a HUD |
| `Config.Keybinds`                  | Default keys                                                           |

Zoom limits, pan speed, lock-on range and the speed unit (`Km/h` or `MPH`)
are at the top of `client.lua`. Beam range and update rate are at the top of
`server.lua`.

The default `DepartmentNames` and the `hud:toggle` event are examples from
the server this was built on. Change or empty them for yours.

## Controls

Players can change these under Settings > Key Bindings > FiveM.

| Key                | In the camera                    | Outside the camera                                         |
| ------------------ | -------------------------------- | ---------------------------------------------------------- |
| `B`                | Close the camera                 | Open the camera                                            |
| Mouse              | Pan                              |                                                            |
| Scroll wheel       | Zoom                             |                                                            |
| Right mouse button | Normal / night vision / thermal  |                                                            |
| `Space`            | Lock on to a vehicle / release   | Release the locked vehicle                                 |
| `U`                | Manual spotlight on/off          | Pilot: forward searchlight, or tracking spotlight on/pause |
| `Up` / `Down`      | Spotlight brightness             | Spotlight brightness                                       |
| `Right` / `Left`   | Manual spotlight radius          | Manual spotlight radius                                    |
| `Q`                | Vehicle info: full / short / off | Vehicle info: full / short / off                           |
| `X`                |                                  | Rappel (rear seats)                                        |

With a vehicle locked, the pilot's `U` outside the camera turns the tracking
spotlight on and then pauses and resumes it. Without one it switches the
forward searchlight.

## For developers

The spotlight of each helicopter is a state bag on the helicopter entity,
set by the server:

```lua
Entity(heli).state.helicamSpotlight
-- nil when off, otherwise:
-- { mode = "forward" | "manual" | "tracking", operator = serverId,
--   brightness = number, radius = number,
--   target = netId, plate = string, paused = boolean }   -- last three: tracking only
```

Events in `Config.DisableEventsWhileHelicam` are triggered on the client with
`false` when the camera opens and `true` when it closes.

## Credits and licence

Licensed under the MIT License (see `LICENSE.md`).

This is a modified version of
[filo_helicam](https://github.com/filo-studios/filo_helicam) by filo studios,
which is a refactor of
[FiveM-Helicam](https://github.com/Zerofour04/FiveM-Helicam) by Zerofour04.
That in turn comes from the
[Heli Script](https://forum.cfx.re/t/release-heli-script/24094) by mraes, as
modified by rjross2013 and Loque. Loque's version credits Guadmaz's Simple
Police Searchlight, devilkkw's Speed Camera, nynjardin's Simple Outlaw Alert
and IllidanS4's FiveM Entity Iterators.

See `difference.md` for what this version changes.

## AI use

AI assistance was used.
