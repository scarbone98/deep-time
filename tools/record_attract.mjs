// Usage: node record_attract.mjs "?play&attract&seed=42&ts=0.09" outdir 450, then ffmpeg -framerate 30 the PNGs.
// Copy to /tmp (playwright lives in /tmp/node_modules) and serve build/web on :8792. Game time follows wall time, so ts= slows it to match the capture rate.
// Records the attract scene frame by frame on a paused clock.
import { chromium } from 'playwright';
const [, , q = '?play&attract&seed=42', dir = '/tmp/dtrec', frames = '450'] = process.argv;
const b = await chromium.launch({ executablePath: '/home/sami/.nix-profile/bin/chromium',
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: 540, height: 960 } });
let ready = false;
p.on('console', m => { if (/seed/.test(m.text())) ready = true; if (/^pos/.test(m.text())) console.log(Date.now(), m.text()); if (/error/i.test(m.text())) console.log(m.text()); });
await p.clock.install();
await p.goto('http://127.0.0.1:8792/index.html' + q);
for (let i = 0; i < 600 && !ready; i++) { await p.clock.runFor(50); await new Promise(r => setTimeout(r, 50)); }
console.log('ready', ready);
await p.clock.runFor(1500);
const fs = await import('node:fs'); fs.mkdirSync(dir, { recursive: true });
for (let f = 0; f < Number(frames); f++) {
  await p.clock.runFor(Number(process.env.STEP || 1000 / 30));
  await p.screenshot({ path: `${dir}/f${String(f).padStart(4, '0')}.png` });
}
await b.close();
