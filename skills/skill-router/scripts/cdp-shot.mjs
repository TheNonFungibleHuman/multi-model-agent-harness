// cdp-shot.mjs — accurate viewport screenshots via Chrome DevTools Protocol.
// Chrome's --window-size has a minimum width on Windows, so CLI screenshots of
// a 390px mobile page are laid out wider and then cropped. Device-metrics
// emulation avoids that and is what the design gate needs.
//
// Usage: node cdp-shot.mjs <file-or-url> <out.png> [width] [height]
import { spawn } from "node:child_process";
import { existsSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { dirname, resolve } from "node:path";

const candidates = [
  `${process.env.ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe`,
  `${process.env["ProgramFiles(x86)"]}\\Google\\Chrome\\Application\\chrome.exe`,
  `${process.env.LOCALAPPDATA}\\Google\\Chrome\\Application\\chrome.exe`,
  `${process.env.ProgramFiles}\\Microsoft\\Edge\\Application\\msedge.exe`,
  `${process.env["ProgramFiles(x86)"]}\\Microsoft\\Edge\\Application\\msedge.exe`,
];
const chrome = candidates.find((p) => existsSync(p));
if (!chrome) {
  console.error("cdp-shot: no Chrome/Edge found");
  process.exit(1);
}

const target = process.argv[2];
const out = process.argv[3];
if (!target || !out) {
  console.error("usage: node cdp-shot.mjs <file-or-url> <out.png> [width] [height]");
  process.exit(1);
}
const width = Number(process.argv[4] || 1440);
const height = Number(process.argv[5] || 900);
const url = /^[a-z]+:\/\//i.test(target)
  ? target
  : new URL("file:///" + resolve(target).replace(/\\/g, "/")).href;

const port = 9300 + Math.floor(Math.random() * 400);
const profile = `${process.env.TEMP}\\cdp-shot-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
const child = spawn(chrome, [
  "--headless=new",
  "--disable-gpu",
  "--no-first-run",
  "--no-default-browser-check",
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${profile}`,
  "about:blank",
], { stdio: "ignore" });

async function getJson(path, method = "GET") {
  for (let i = 0; i < 120; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}${path}`, { method });
      if (r.ok) return await r.json();
    } catch {}
    await sleep(100);
  }
  throw new Error("CDP did not become ready");
}

let ws;
try {
  const page = await getJson("/json/new?about:blank", "PUT");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 1;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? p.reject(new Error(JSON.stringify(msg.error))) : p.resolve(msg.result);
    }
  };
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const i = id++;
    pending.set(i, { resolve, reject });
    ws.send(JSON.stringify({ id: i, method, params }));
  });

  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: width <= 500,
  });
  await send("Page.navigate", { url });
  await sleep(900);
  // Let fonts settle without waiting for network-idle on remote assets.
  await send("Runtime.evaluate", { expression: "document.fonts && document.fonts.ready", awaitPromise: true }).catch(() => {});
  await sleep(200);

  const shot = await send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });
  mkdirSync(dirname(resolve(out)), { recursive: true });
  writeFileSync(resolve(out), Buffer.from(shot.data, "base64"));
  console.log(`${width}x${height} screenshot written to ${resolve(out)}`);
} finally {
  try { ws && ws.close(); } catch {}
  child.kill();
  await sleep(200);
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}
