# DEEP TIME

A time-travelling heist through prehistory, Backrooms style. You're holding a camcorder and noclipping down through Earth's layers. Each level is one period of deep time: huge, foggy, empty, and not empty.

Pure dread. No weapons. You can only hide, sneak, and run.

Godot 4.5 (GL Compatibility), GDScript. Built for the web, without threads.

## How it plays

**A time-travelling heist.** You start in the **Chrono Hub**, a little station floating outside time.

1. Walk to the **TIME CONSOLE** and drop into an era.
2. Grab what's valuable: eggs, amber, fossils, teeth. The bag holds 3 things, and the heavier it is, the slower and louder you are.
3. Get back through the **rift** (the Backrooms fragment) to cash in. Die and your bag spills where you fell, so a friend can pick it up.
4. Everyone is paid the crew's whole haul. Spend it at the **SHOP** kiosk on cosmetics for your chibi time-traveller: suit colours, hats (party, propeller, cowboy, top hat, dino hood, halo, crown) and face gear.

**Eggs sit in nests**, and they're worth the most. Taking one tells its parent exactly where you are. The first egg taken wakes a second hunter, and every egg darkens the era.

Money, owned cosmetics, your look and best hauls are saved on the device (`user://deeptime.cfg`, IndexedDB on the web). Level data (look, sound, loot tables) is in `src/eras.gd`; the shop catalogue is in `src/shop.gd`.

### Level 1: The Coal Forest (Carboniferous)

Arthropleura hunts by vibration: footsteps, splashing, panting, and your voice in co-op. Loot:
- **Arthropleura eggs** ($150) at its lair
- **Eryops spawn** ($70) by the pools
- **Amber** ($45), **Meganeura wings** ($30), **scale-tree cones** ($15)

Also out there: Eryops sinking in the pools, scorpions by the logs that strike if you linger, and Meganeura swarming your lamp.

### Level 2: The Red Waste (Permian)

Inostrancevia hunts by sight: keep rock between you. Loot:
- **Scutosaurus eggs** ($170) by the herds
- **Dicynodon eggs** ($85) at the burrows
- **Gorgon teeth** ($60) among the bones
- **Amber** ($45), **Glossopteris fossils** ($25)

## Co-op (up to 4, server authoritative)

**PLAY WITH FRIENDS** (on the title card or at the console): host a room and share its 4-letter code, or join one. The crew meets in the hub, sees each other's outfits, and the host drives the time console.

- **Server authoritative.** One headless Godot process (`-- server port=N`, the same project exported with the "Server" preset) hosts every room. Each room runs the real level (`main.gd` in `server` mode) inside its own SubViewport, so each room gets its own physics world.
  - The server owns every player's position, every creature, shots, deaths and the door. Clients send only input (30 Hz); they predict their own movement and reconcile it against 20 Hz snapshots.
  - Creatures are puppets on clients. Levels are built from the room's seed, so every creature list lines up by index. See `src/net.gd`.
- A drop ends when nobody is left in the era, whether they're home or caught. Then everyone returns to the hub and gets paid.
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

Desktop: WASD move · mouse look · Shift run · C / Ctrl crouch · F lamp · E grab / use · G drop · Esc pause · co-op: 1-4 emotes, M mute

Phone (portrait or landscape): left thumb is a floating stick (drag past the ring to run) · right thumb looks · LAMP, CROUCH, GRAB / USE and DROP buttons. Touch mode turns on automatically on touchscreens; force it with `?touch`.

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
