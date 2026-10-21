// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/colonie.mjs
// Colonie : bâtiments, bonus de départ, bilan.
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
  p.send({ t: "hello", token: name + "-col", name, color: -1, species: "humain", ornament: "aucun" });
  await sleep(300);
  return p;
}
async function waitScene(p, name, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}

const a = await phone("Anne");
async function startRun() {
  await a.cmd({ cmd: "goto", scene: "choix" });
  await waitScene(a, "choix", 4000);
  a.vote("paikan"); await sleep(1800); a.vote("decouverte");
  return waitScene(a, "carte", 8000);
}
let d = await startRun();
const base = { scrap: d.run.scrap, fuel: d.run.fuel, hull_max: d.run.hull_max, renown: d.run.renown };
check(d.colony.pop === 0 && d.colony.buildings.length === 0, "colonie vide au départ");
await a.cmd({ cmd: "colony", value: 50000 });
d = await startRun();
check(d.run.scrap === base.scrap + 6, `Forge : +6 ferraille (${base.scrap} → ${d.run.scrap})`);
check(d.run.fuel === base.fuel + 1, "Citerne : +1 carburant");
check(d.run.hull_max === base.hull_max + 4, "Chantier naval : +4 coque");
check(d.run.renown === 0, "le Conseil des anciens n est pas encore construit");
check(d.colony.buildings.join() === "forge,citerne,chantier", `bâtiments : ${d.colony.buildings}`);
await a.cmd({ cmd: "end_run", win: true });
d = await waitScene(a, "bilan", 4000);
check(d.colony.expeditions === 1 && d.colony.pop > 50000, `la victoire peuple l'arche (${d.colony.pop})`);
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
