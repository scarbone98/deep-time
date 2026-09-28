# DEEP TIME

Backrooms through prehistory. You're holding a camcorder and noclipping down through Earth's layers. Each level is one period of deep time: huge, foggy, empty, and not empty.

Pure dread. No weapons. You can only hide, sneak, and run.

Godot 4.5 (GL Compatibility), GDScript. Built for the web, without threads.

## Level 1: The Coal Forest (Carboniferous, ~307 MYA)

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

Every mesh is procedural (`src/meshes.gd`). The creature and effect sounds are synthesized at load time (`src/synth.gd`). The swamp ambience is two CC0 field recordings; see `audio/CREDITS.md`.

## Controls

Desktop: WASD move · mouse look · Shift run · C / Ctrl crouch · F lamp · Esc pause

Phone (portrait or landscape): left thumb is a floating stick (drag past the ring to run) · right thumb looks · LAMP and CROUCH buttons. Touch mode turns on automatically on touchscreens; force it with `?touch`.

## Dev

```sh
./tools/build_web.sh          # export to build/web
./tools/publish_pages.sh      # build + force-push to gh-pages
```

Dev flags are a URL query on web, or `-- key=value` on desktop:
`play` (skip title), `seed=N`, `mill=D` + `mturn=rad` (spawn it D m ahead), `exit` (start by the door), `light`, `fly`, `freeze`, `yaw=` / `pitch=` (degrees), `die`, `win`, `touch`, `debug` (logs position and yaw), `shots=N` (first N shots done), `near=eryops|scorp` + `neard=m` (start beside one).

Screenshots: serve `build/web` on :8792, then run `node tools/shot.mjs "?play&seed=42" out.png 12000`. Playwright must be resolvable.

## Next eras

Cambrian seafloor (Anomalocaris) → Permian desert (gorgonopsids) → Cretaceous floodplain (raptors in the tall growth, sauropods in the fog) → Pleistocene snow and caves (short-faced bear).
