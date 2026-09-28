# DEEP TIME

Backrooms through prehistory. You're holding a camcorder and noclipping down through Earth's layers. Each level is one period of deep time: huge, foggy, empty, and not empty.

Pure dread. No weapons. You can only hide, sneak, and run.

Godot 4.5 (GL Compatibility), GDScript. Built for the web, without threads.

## Level 1: The Coal Forest (Carboniferous, ~307 MYA)

- **The swamp:** a new layout every run. It has scale trees (Lepidodendron, Sigillaria), giant horsetails (Calamites), tree ferns, fern carpet, fallen logs, and black, wadeable pools.
- **Arthropleura:** a giant millipede, scaled up for horror. It's blind and hunts by vibration:
  - Walking footsteps carry 7 m, running 20 m, crouching 2 m. Water makes every step louder.
  - When you're out of breath, your panting gives you away.
  - Stand still and it can crawl right past you. Move within ~3 m of it and it feels you.
  - If it hears you within 16 m, it hunts you. Otherwise it comes to investigate, then rears up and searches.
  - It drifts your way more often than chance would suggest.
- **Meganeura:** giant griffinflies. They ignore you, except that they swarm the camcorder lamp, and their droning near you counts as noise.
- **The lamp:** you'll want it, and its battery runs out. It also draws the flies.
- **The way out:** a scrap of the Backrooms standing in the swamp, 130 to 165 m from where you start. You'll find it by its fluorescent hum and a faint smudge of light in the fog.

Every mesh is procedural (`src/meshes.gd`). The creature and effect sounds are synthesized at load time (`src/synth.gd`). The swamp ambience is two CC0 field recordings; see `audio/CREDITS.md`.

## Controls

WASD move · mouse look · Shift run · C / Ctrl crouch · F lamp · Esc pause

## Dev

```sh
./tools/build_web.sh          # export to build/web
./tools/publish_pages.sh      # build + force-push to gh-pages
```

Dev flags are a URL query on web, or `-- key=value` on desktop:
`play` (skip title), `seed=N`, `mill=D` + `mturn=rad` (spawn it D m ahead), `exit` (start by the door), `light`, `fly`, `freeze`, `yaw=` / `pitch=` (degrees), `die`, `win`.

Screenshots: serve `build/web` on :8792, then run `node tools/shot.mjs "?play&seed=42" out.png 12000`. Playwright must be resolvable.

## Next eras

Cambrian seafloor (Anomalocaris) → Permian desert (gorgonopsids) → Cretaceous floodplain (raptors in the tall growth, sauropods in the fog) → Pleistocene snow and caves (short-faced bear).
