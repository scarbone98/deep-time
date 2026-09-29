# DEEP TIME

Backrooms through prehistory. You're holding a camcorder and noclipping down through Earth's layers. Each level is one period of deep time: huge, foggy, empty, and not empty.

Pure dread. No weapons. You can only hide, sneak, and run.

Godot 4.5 (GL Compatibility), GDScript. Built for the web, without threads.

## Levels

Each level is one layer of deep time. Fill the camcorder's shot list, then find the Backrooms fragment that leads down to the next layer. Clearing a level unlocks the next one, and you can pick any unlocked layer on the title card. Best times are saved on the device (`user://deeptime.cfg`, which is IndexedDB on the web).

Level definitions (look, sound, shot list, text) live in `src/eras.gd`.

### Level 1: The Coal Forest (Carboniferous, ~307 MYA)

**Goal: fill the camcorder's shot list, then find the way out.** Keep a creature near the centre of frame, close enough and unobstructed, until the red bar fills.

| Shot | Creature | The catch |
|---|---|---|
| 1 | **Meganeura** (griffinfly) | Drawn to your lamp. Their droning near you counts as noise. |
| 2 | **Eryops** (2 m amphibian) | Lies in the deep pools and sinks at any nearby noise. It only resurfaces after ~6 to 9 s of quiet, and its eyes shine in the lamp. |
| 3 | **Pulmonoscorpius** | Sits motionless beside fallen logs. It rattles inside ~4.5 m and strikes if you're still inside ~3.6 m when the rattle ends. |
| 4 | **Arthropleura** | The thing hunting you. It needs 3 s in frame. |

- **Arthropleura hunts by vibration:**
  - Walking footsteps carry 7 m, running 20 m, crouching 2 m. Water makes every step louder, and so does panting when you're out of breath.
  - Stand still and it can crawl right past you.
- **Each finished shot** darkens the swamp and makes the millipede bolder and faster.
- **The way out** is a scrap of the Backrooms in the swamp, 130 to 165 m from the start. It stays dark until the list is complete. Then its light comes on and a **second millipede** wakes up.
- **The swamp:** a new layout every run, with scale trees, giant horsetails, tree ferns, fern carpet, fallen logs and black, wadeable pools.

### Level 2: The Red Waste (Permian, ~259 MYA)

Red dunes and dry washes, sandstone outcrops, Glossopteris trees, and bones. The hunter is the opposite of Level 1's: **Inostrancevia can't hear you, but it sees everything.**

- Its awareness builds while you're in its view cone with a clear line of sight. It builds faster when you're close, moving, or have the lamp on, and slower when you're crouched.
- It prowls, then stalks (low, with a growl), then charges (with a roar), and it's faster than you can run. Put rock between you: it goes to where it last saw you and searches.

| Shot | Creature | The catch |
|---|---|---|
| 1 | **Scutosaurus** | Armoured grazers in slow, drifting herds. Harmless and loud. |
| 2 | **Dicynodon** | Sits in its burrow mouth. It ducks underground if you walk up on it or shine the lamp at it, so crouch in. |
| 3 | **Inostrancevia** | 3 s in frame. |

Every mesh is procedural (`src/meshes.gd`). The creature and effect sounds are synthesized at load time (`src/synth.gd`). The swamp ambience is two CC0 field recordings; see `audio/CREDITS.md`.

## Co-op (up to 4, server authoritative)

**PLAY WITH FRIENDS** on the title card: host a room and share its 4-letter code, or join one. The host picks the level.

- **Server authoritative.** One headless Godot process (`-- server port=N`, the same project exported with the "Server" preset) hosts every room. Each room runs the real level (`main.gd` in `server` mode) inside its own SubViewport, so each room gets its own physics world.
  - The server owns every player's position, every creature, shots, deaths and the door. Clients send only input (30 Hz); they predict their own movement and reconcile it against 20 Hz snapshots.
  - Creatures are puppets on clients. Levels are built from the room's seed, so every creature list lines up by index. See `src/net.gd`.
- **Everyone films their own shot list.** The first finished list wakes the second hunter. Each player has to get through the door; the level ends when nobody is left inside. Anyone through means the crew goes deeper.
- **Proximity voice.** Browser WebRTC (Opus, echo cancellation), signalled through the game server and placed in 3D at each speaker's head, with a camcorder band-pass (`src/voice.gd`).
  - **Talking is noise:** the millipede hears you.
  - The living can't hear the dead; the dead hear everyone.
- **Ragdolls and spectating.** Caught players flop, then watch a living friend's tape (click or tap to switch).
- **Emotes:** 1 wave, 2 point, 3 scream (loud, so it carries), 4 camera flash (whites out anyone you catch in the face). M mutes the mic. On phones they're the EMOTE and MIC buttons.

### Running the server

```sh
godot4 --headless --path . -- server port=8910      # local
./tools/deploy_server.sh                            # Fly.io (app deep-time-coop, see server/fly.toml)
```

The web build connects to `wss://deep-time-coop.fly.dev` by default. Override it with `?server=ws://127.0.0.1:8910`. Dev shortcuts: `?host=NAME&code=ABCD&autostart=2`, `?join=ABCD&name=NAME`. `tools/coop_test.mjs` drives two browsers (with fake mics) against a local server.

## Controls

Desktop: WASD move · mouse look · Shift run · C / Ctrl crouch · F lamp · Esc pause · co-op: 1-4 emotes, M mute

Phone (portrait or landscape): left thumb is a floating stick (drag past the ring to run) · right thumb looks · LAMP and CROUCH buttons. Touch mode turns on automatically on touchscreens; force it with `?touch`.

## Dev

```sh
./tools/build_web.sh          # export to build/web
./tools/publish_pages.sh      # build + force-push to gh-pages
```

Dev flags are a URL query on web, or `-- key=value` on desktop:
`play` (skip title), `seed=N`, `mill=D` + `mturn=rad` (spawn it D m ahead), `exit` (start by the door), `light`, `fly`, `freeze`, `yaw=` / `pitch=` (degrees), `die`, `win`, `touch`, `debug` (logs position and yaw), `shots=N` (first N shots done), `near=eryops|scorp|scuto|dicy` + `neard=m` (start beside one), `level=N`, `attract` + `ts=` (cabinet video scene; see tools/record_attract.mjs).

Screenshots: serve `build/web` on :8792, then run `node tools/shot.mjs "?play&seed=42" out.png 12000`. Playwright must be resolvable.

## Next eras

Cambrian seafloor (Anomalocaris) → Permian desert (gorgonopsids) → Cretaceous floodplain (raptors in the tall growth, sauropods in the fog) → Pleistocene snow and caves (short-faced bear).
