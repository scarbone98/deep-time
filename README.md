# DEEP TIME

A time-travelling heist through prehistory, Backrooms style. You're holding a camcorder and noclipping down through Earth's layers. Each level is one period of deep time: huge, foggy, empty, and not empty.

Pure dread. No weapons. You can only hide, sneak, and run.

Godot 4.5 (GL Compatibility), GDScript. Built for the web, without threads.

## How it plays

Lethal Company in deep time. You start in the **Chrono Hub**, a little station floating outside time, and walk to the **TIME CONSOLE** to drop into an era.

- **The Bureau's quota.** Bring home the target within 3 drops and the next quota goes up. Miss it and you're fired: credits wiped, hats kept.
- **Carry it back.** Loot goes into **4 hand slots** (1-4 or the mouse wheel to switch; what you're holding is in your hands, in first person and for your friends).
  - Big eggs take **both hands**: no switching until you put them down.
  - **E** picks up, **G** sets down, **T** throws. Friends catch throws by being in the way, and eggs crack if they fall hard.
- **The rift stays open where you land, for 7 minutes.** Set loot down on the rift's carpet, and everything on the carpet comes home when the crew leaves. Press E at the door to leave; anything in your hands comes too.
  - Halfway through, the hunters get bolder. In the last minute the rift strains.
  - When it collapses, anyone still out is lost, with whatever they carry.
- **Risk:** cheap loot is near the rift, eggs are far out in nests, and taking an egg brings the parent. Loot glints through the fog.
- **The SHOP kiosk** sells cosmetics for your chibi time-traveller (suits, hats, face gear) and gear: squeaky decoys (Q), a bigger pack (+1 slot) and a long-life battery.

Money, quota, cosmetics, gear and look sensitivity are saved on the device (`user://deeptime.cfg`). In co-op the room keeps its own quota. Level data is in `src/eras.gd`; the shop catalogue is in `src/shop.gd`.

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

### Level 3: Hell Creek (Late Cretaceous)

Dinosaurs, in a foggy redwood forest with cycads and the first flowers.
- **Raptors** (Dakotaraptor) hunt in a pair, by sight and sound: noise brings them over to look, and once they see you they're faster than you.
- **The T. rex** only sees movement. You feel its footsteps before you see it. Stand still.
- **Triceratops** herds graze. Their eggs ($190) are the prize.
- Also: T. rex teeth, raptor feathers, amber, ammonites, and the first flowers.

## Co-op (up to 4, server authoritative)

**PLAY WITH FRIENDS** (on the title card or at the console): host a room and share its 4-letter code, or join one. The crew meets in the hub, sees each other's outfits, and the host drives the time console.

- **Server authoritative.** One headless Godot process (`-- server port=N`, the same project exported with the "Server" preset) hosts every room. Each room runs the real level (`main.gd` in `server` mode) inside its own SubViewport, so each room gets its own physics world.
  - The server owns every player's position, every creature, the loot, deaths and the rift. Clients send only input (30 Hz); they predict their own movement and reconcile it against 20 Hz snapshots.
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

Desktop: WASD move · mouse look · Shift run · Space jump · C / Ctrl crouch · F lamp · E grab / use · G drop · T throw · 1-4 / wheel switch hands · Q decoy · [ ] look sensitivity · Esc pause · co-op: Z X V B emotes, M mute

Phone (portrait or landscape): left thumb is a floating stick (drag past the ring to run) · right thumb looks · LAMP, CROUCH, JUMP, GRAB / USE, DROP, THROW, SWAP and DECOY buttons. Touch mode turns on automatically on touchscreens; force it with `?touch`.

## Dev

```sh
./tools/build_web.sh          # export to build/web
./tools/publish_pages.sh      # build + force-push to gh-pages
```

Dev flags are a URL query on web, or `-- key=value` on desktop:
`play` (skip title), `level=N` (0 is the hub), `seed=N`, `mill=D` + `mturn=rad` (spawn it D m ahead), `exit` (start by the rift), `loot=N` (start by loot #N), `give=N,N` (start carrying them), `money=N`, `shop` / `console` (open that panel), `light`, `fly`, `freeze`, `yaw=` / `pitch=` (degrees), `die`, `touch`, `debug`, `near=eryops|scorp|scuto|dicy` + `neard=m`, `attract` + `ts=` (cabinet video scene; see tools/record_attract.mjs). `rift=S` (S seconds left on the rift). Co-op: `autostart=LEVEL,PLAYERS`, `bot`, `emote=N`, `throwat=S`; server: `give` (everyone starts holding two things), `debug` (log events). Flags only apply to the first load.

Screenshots: serve `build/web` on :8792, then run `node tools/shot.mjs "?play&seed=42" out.png 12000`. Playwright must be resolvable.

## Next eras

Cambrian seafloor (Anomalocaris) → Permian desert (gorgonopsids) → Cretaceous floodplain (raptors in the tall growth, sauropods in the fog) → Pleistocene snow and caves (short-faced bear).
