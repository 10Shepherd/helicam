# Differences from the original script

`helicam` is a modified version of
[filo_helicam](https://github.com/filo-studios/filo_helicam) by filo studios,
which is itself a refactor of
[FiveM-Helicam](https://github.com/Zerofour04/FiveM-Helicam) by Zerofour04
(from the Heli Script by mraes, rjross2013 and Loque).

This file lists what this version changes relative to filo_helicam. It was
written by comparing the files with filo_helicam 1.0.1, so treat it as a
summary rather than a complete changelog.

Last updated: 2026-11-15

## Summary

| Area               | Original                                          | This version                                                  |
| ------------------ | ------------------------------------------------- | ------------------------------------------------------------- |
| Spotlight sync     | One-off events relayed to every player            | State bag on the helicopter, beams streamed to nearby players |
| Who sees the beam  | Players who were in range when it was switched on | Anyone within 700 m of the helicopter or of the lit spot      |
| Spotlights         | One per player                                    | One per helicopter                                            |
| Server checks      | None                                              | Sender must be in a listed helicopter; values checked         |
| Flight display     | Not present                                       | Added                                                         |
| Helicopter models  | Listed in `client.lua`                            | `Config.HeliModels`, shared with the server                   |
| Version checker    | Downloads and runs a script on start              | Removed                                                       |
| Default camera key | `E`                                               | `B`                                                           |

## Removed

- **Version checker** (`version_check.lua`), which fetched a Lua script from
  GitHub on every start and ran it.
- **Spotlight direction decorators** (`SpotvectorX/Y/Z` on the player ped).
  The aim point is sent through the server instead.
- **Entity enumerator and plate search** used to find a tracked vehicle on
  other clients. The server now knows where the target is.
- **All `heli:*` spotlight events.** They are replaced by the events listed
  under "Spotlight" below.
- The Discord link in the manifest, since it pointed at the original
  author's support server.

## Changed

### Spotlight

- The spotlight of each helicopter is stored by the server in a state bag on
  the helicopter (`helicamSpotlight`): mode, operator, brightness, radius and,
  for tracking, the target, its plate and whether it is paused.
- The server sends the manual and tracking beams ten times a second to every
  player within 700 m of the helicopter or of the lit spot. Clients blend
  between updates. A player who comes into range later still sees the beam.
- The operator of the manual spotlight sends the point the camera is looking
  at ten times a second.
- There is one spotlight per helicopter. Turning one on from another seat
  replaces the one that was on.
- The manual spotlight can be used from any seat in the camera. The forward
  searchlight and the tracking spotlight stay with the pilot.
- Brightness and radius are clamped on the server (1 to 10 and 4 to 10).
- The server switches a spotlight off when whoever turned it on leaves the
  helicopter or the server.
- New events, all from client to server unless noted:
  `helicam:setSpotlight`, `helicam:pauseSpotlight`,
  `helicam:spotlightSettings`, `helicam:aim`, and `helicam:beam` (server to
  client).

### Server checks

- Every spotlight event is ignored unless the sender is sitting in a model
  from `Config.HeliModels`. The forward searchlight also requires the pilot
  seat.
- Arguments are type-checked, the aim point has to be within 2100 m of the
  helicopter, and events are rate limited per player. Switching a light off
  is never rate limited.

### Lock-on

- A locked vehicle that is already a mission entity (for example another
  player's car) is no longer taken control of or re-flagged, and releasing
  the lock no longer strips the flag from it.
- The locked vehicle can be released with the lock-on key from any seat
  outside the camera.

### Configuration and keys

- `Config.HeliModels` moved to `config.lua` so the server can use it.
  `as350` was added next to `polmav`.
- Default keys: camera `E` to `B`, brightness `Y`/`Down` to `Up`/`Down`,
  radius `Caps Lock`/`Left Shift` to `Right`/`Left`.

## Added

- **Flight display** in the top corners of the camera view: department name
  (per model and livery, `Config.HUD`), location, speed in knots, heading,
  altitude, date and time on the left; location, elevation and slant range of
  the point under the crosshair on the right, plus direction of travel, road,
  cross street and postal of a locked vehicle.
- **Optional nearest-postal support** for the postal on the display.
- **`Config.DisableEventsWhileHelicam`**: local events triggered when the
  camera opens and closes, so another HUD can hide itself.
- **Cleanup on resource stop**: the camera, vision modes and target flags
  are reset if the resource is stopped while in use.
- `README.md`, `knownlimitation.txt`, `.gitignore` and this file.

## Fixed

- Players who were out of range when a spotlight was switched on never saw
  it. They now do.
- A spotlight could stay on after its operator left the helicopter or
  disconnected.
- Any player could trigger the spotlight events for everyone on the server
  with any values.
- Added a guard so a second helicopter thread cannot start when changing
  helicopters quickly.
- Typo in the manifest description ("helicoper").
