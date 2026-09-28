// Copy to /tmp (playwright lives in /tmp/node_modules) and serve build/web on :8792.
// Drives the web build with real touch events on an emulated phone.
// Usage: node dt-touch.mjs portrait|landscape outprefix
import { chromium } from 'playwright';
const [, , orient = 'portrait', out = '/tmp/dt/t'] = process.argv;
const [W, H] = orient === 'portrait' ? [390, 844] : [844, 390];
const b = await chromium.launch({ executablePath: '/home/sami/.nix-profile/bin/chromium',
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = await b.newContext({ viewport: { width: W, height: H }, hasTouch: true, isMobile: true, deviceScaleFactor: 1 });
const p = await ctx.newPage();
p.on('console', m => { const t = m.text(); if (/error|seed|pos/i.test(t)) console.log('console:', t); });
p.on('pageerror', e => console.log('pageerror:', e.message));
const cdp = await ctx.newCDPSession(p);
const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
// Godot viewport coords -> page px
const vw = W > H ? 640 : 360, vh = W > H ? 360 : 640;
const sc = Math.min(W / vw, H / vh);
const cw = W / sc, ch = H / sc;
const px = (x, y) => ({ x: x * sc, y: y * sc });
await p.goto((process.env.BASE || 'http://127.0.0.1:8792') + '/index.html?seed=42&debug&yaw=180');
await p.waitForTimeout(9000);
await p.screenshot({ path: out + '0-title.png' });
await touch('touchStart', [{ ...px(cw / 2, ch / 2), id: 9 }]); await touch('touchEnd', []);
await p.waitForTimeout(1500);
// lamp on
const lamp = px(cw - 62, ch - 190);
await touch('touchStart', [{ ...lamp, id: 1 }]); await touch('touchEnd', []);
await p.waitForTimeout(500);
// left stick pushed forward + right thumb dragging to look
const s0 = px(90, ch - 110);
const l0 = px(cw * 0.75, ch * 0.45);
await touch('touchStart', [{ ...s0, id: 1 }]);
await touch('touchMove', [{ x: s0.x, y: s0.y - 40 * sc, id: 1 }]);
await touch('touchStart', [{ x: s0.x, y: s0.y - 40 * sc, id: 1 }, { ...l0, id: 2 }]);
for (let i = 1; i <= 20; i++) {
  await touch('touchMove', [{ x: s0.x, y: s0.y - 40 * sc, id: 1 }, { x: l0.x + i * 3 * sc, y: l0.y, id: 2 }]);
  await p.waitForTimeout(100);
}
await p.screenshot({ path: out + '1-walking.png' });
await touch('touchEnd', []);
await p.waitForTimeout(1500);
await p.screenshot({ path: out + '2-after.png' });
await b.close();
