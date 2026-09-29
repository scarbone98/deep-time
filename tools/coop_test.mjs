// Copy to /tmp (playwright lives in /tmp/node_modules), serve build/web on :8792, run a local server, SRV=ws://127.0.0.1:PORT node coop_test.mjs
// Two browsers co-op against a local server. Fake mic so voice negotiates.
import { chromium } from 'playwright';
const srv = process.env.SRV || 'ws://127.0.0.1:8913';
const ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'];
const b = { close: async () => process.exit(0) };
const mk = async (q, tag) => {
  const br = await chromium.launch({ executablePath: '/home/sami/.nix-profile/bin/chromium', args: ARGS });
  const ctx = await br.newContext({ viewport: { width: 960, height: 540 }, permissions: ['microphone'] });
  const p = await ctx.newPage();
  p.on('console', m => { const t = m.text(); if (/error|ERROR|seed|room|WARN|net:|auto/i.test(t) && !/X509/.test(t)) console.log(tag, t); });
  p.on('crash', () => console.log(tag, 'CRASH'));
  p.on('pageerror', e => console.log(tag, 'pageerror', e.message));
  await p.goto('http://127.0.0.1:8792/index.html?server=' + encodeURIComponent(srv) + '&' + q);
  return p;
};
const a = await mk('host=ALICE&code=WEBT&autostart=2&yaw=180&emote=1&light', 'A');
await a.waitForTimeout(6000);
await a.screenshot({ path: '/tmp/dt/co-lobby.png' });
const bb = await mk('join=WEBT&name=BOB&yaw=0&light', 'B');
await a.waitForTimeout(16000);
await a.screenshot({ path: '/tmp/dt/co-a.png' });
await bb.screenshot({ path: '/tmp/dt/co-b.png' });
const v = await bb.evaluate(() => ({ peers: Object.keys(window.dtVoice.peers), ok: window.dtVoice.ok, err: window.dtVoice.err,
  conn: Object.values(window.dtVoice.peers).map(P => P.pc.connectionState), heard: Object.values(window.dtVoice.peers).map(P => !!P.gain) }));
console.log('voice B', JSON.stringify(v));
await b.close();
