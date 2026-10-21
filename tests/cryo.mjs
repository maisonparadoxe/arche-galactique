// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/cryo.mjs
// Cryo : un membre à terre que personne ne relève est reclôné, avec un malus de vitesse.
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
  p.send({ t: "hello", token: name + "-cryo", name, color: -1, species: "humain", ornament: "aucun" });
  await sleep(300);
  return p;
}
async function waitScene(p, name, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}

const a = await phone("Anne");
await a.cmd({ cmd: "goto", scene: "choix" });
await waitScene(a, "choix", 4000);
a.vote("paikan"); await sleep(1800); a.vote("decouverte");
await waitScene(a, "carte", 8000);
await a.cmd({ cmd: "goto", scene: "abordage", args: { layout: "galion" } });
await waitScene(a, "abordage", 4000);
await a.cmd({ cmd: "skip_intro" });
await a.cmd({ cmd: "freeze" });
await a.cmd({ cmd: "no_revive" });
let d = await a.dbg();
const me = d.members.find((m) => !m.free);
await a.cmd({ cmd: "down", id: me.id });
d = await a.dbg();
check(d.members.find((m) => m.id === me.id).downed, "le membre est à terre");
await sleep(15500);
d = await a.dbg();
const m2 = d.members.find((m) => m.id === me.id);
check(!m2.downed && d.clonings === 1, `la cryo le refabrique (clonages : ${d.clonings})`);
check(m2.clone_gen === 1, "il est marqué « clone I »");
check(d.run.clones_total === 1, "la run retient le clonage");
await a.cmd({ cmd: "goto", scene: "boutique" });
await waitScene(a, "boutique", 4000);
d = await a.dbg();
check(d.items.includes("cuve"), "la boutique propose la cuve de jouvence");
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
