// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/postes.mjs
// Postes de pilotage et de machines en combat.
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
  p.cur = N;
  setInterval(() => p.send({ t: "in", x: 0, y: 0, b: p.cur }), 33);
  p.send({ t: "hello", token: name + "-post", name, color: -1, species: "humain", ornament: "aucun" });
  await sleep(300);
  return p;
}
async function waitScene(p, name, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}
const tp = (p, x, y) => { p.send({ t: "dbg_tp", x, y }); return sleep(150); };
const press = async (p, i) => { const b = [false, false, false, false]; b[i] = true; p.cur = b; await sleep(200); p.cur = N; await sleep(150); };

const a = await phone("Anne");
const b = await phone("Bob");
await a.cmd({ cmd: "goto", scene: "choix" });
await waitScene(a, "choix", 4000);
a.vote("paikan"); b.vote("paikan"); await sleep(1800); a.vote("decouverte"); b.vote("decouverte");
await waitScene(a, "carte", 8000);
await a.cmd({ cmd: "goto", scene: "combat", args: { enemy: "eclaireur" } });
await waitScene(a, "combat", 4000);
await a.cmd({ cmd: "freeze_enemy" });
let d = await a.dbg();
const base = d.evasion;
await tp(a, d.pilot_x, d.pilot_y);
await press(a, 0);
d = await a.dbg();
check(d.pilot !== 0, "Anne s'assoit au pilotage");
check(d.evasion > base, `un pilote améliore l'esquive (${base} → ${d.evasion})`);
a.send({ t: "act", a: "fire", w: 0 }); await sleep(200);
d = await a.dbg();
const withManeuver = d.evasion;
check(d.maneuver > 0 && withManeuver > 0.3, `manœuvre : esquive ${withManeuver}`);
await tp(b, d.eng_x, d.eng_y);
await press(b, 0);
d = await a.dbg();
check(d.engineer !== 0, "Bob s'assoit aux machines");
b.send({ t: "act", a: "fire", w: 1 }); await sleep(200);
d = await a.dbg();
check(d.power === "boucliers", "l'énergie va aux boucliers");
b.send({ t: "act", a: "fire", w: 3 }); await sleep(200);
d = await a.dbg();
check(d.sealed === true, "les cloisons se ferment");
b.send({ t: "act", a: "quit" }); await sleep(200);
d = await a.dbg();
check(d.engineer === 0 && d.sealed === false, "quitter les machines libère le poste");
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
