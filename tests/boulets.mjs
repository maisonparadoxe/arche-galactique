// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/boulets.mjs
// Chargement des canons : boulets de la soute aux armes.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const N = [false, false, false, false];
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? "OK  " : "FAIL"} ${label}`); if (!ok) failures++; };

async function phone(name) {
  const ws = new WebSocket("ws://127.0.0.1:9080");
  const inbox = [];
  ws.onmessage = (e) => inbox.push(JSON.parse(e.data));
  await new Promise((r) => (ws.onopen = r));
  const p = {
    ws, inbox,
    send: (o) => ws.readyState === 1 && ws.send(JSON.stringify(o)),
    last: (t) => [...inbox].reverse().find((m) => m.t === t),
    async dbg() { const n = inbox.length; p.send({ t: "dbg" }); for (let i = 0; i < 60; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } throw new Error("pas de réponse dbg"); },
    async cmd(o) { p.send({ t: "dbg_cmd", ...o }); await sleep(120); },
    vote: (id) => p.send({ t: "vote", id }),
  };
  setInterval(() => p.send({ t: "in", x: 0, y: 0, b: N }), 33);
  p.send({ t: "hello", token: name + "-boul", name, color: -1, species: "humain", ornament: "aucun" });
  await sleep(300);
  return p;
}
async function waitScene(p, name, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}
const tp = (p, x, y) => { p.send({ t: "dbg_tp", x, y }); return sleep(150); };

const a = await phone("Anne");
await a.cmd({ cmd: "goto", scene: "choix" });
await waitScene(a, "choix", 4000);
a.vote("paikan"); await sleep(1800); a.vote("decouverte");
await waitScene(a, "carte", 8000);
await a.cmd({ cmd: "goto", scene: "combat", args: { enemy: "eclaireur" } });
await waitScene(a, "combat", 4000);
await a.cmd({ cmd: "freeze_enemy" });
let d = await a.dbg();
check(d.shells === 4, `la soute démarre avec ${d.shells} boulets`);
// ravitaillement par un porteur : soute → armes
await tp(a, d.magazine_x, d.magazine_y);
await sleep(300);
d = await a.dbg();
check(d.carrying === true, "Anne prend un boulet à la soute");
const before = d.shells;
const armes = d.rooms.find((r) => r.system === "armes");
await tp(a, d.console_x - 10, d.console_y);
await sleep(300);
d = await a.dbg();
check(d.carrying === false && d.shells === before + 2, `livraison aux armes : ${before} → ${d.shells} boulets`);
// sans boulets, plus de tir automatique
await tp(a, 40, 40);
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
