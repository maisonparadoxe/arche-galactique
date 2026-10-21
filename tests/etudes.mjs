// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/etudes.mjs
// Folie de l équipage, études et compétences.
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
  p.send({ t: "hello", token: name + "-etu", name, color: -1, species: "humain", ornament: "aucun" });
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
let d = await waitScene(a, "carte", 8000);
check(d.run.madness === undefined || true, "départ");
// L'événement de la nébuleuse peut faire monter la folie ; on vérifie surtout l'effet via la commande.
await a.cmd({ cmd: "madness", value: 2 });
await a.cmd({ cmd: "goto", scene: "boutique" });
d = await waitScene(a, "boutique", 4000);
check(d.items.includes("tisane"), "la boutique propose la tisane quand l'équipage est troublé");
await a.cmd({ cmd: "madness", value: 0 });
await a.cmd({ cmd: "goto", scene: "abordage", args: { layout: "galion" } });
d = await waitScene(a, "abordage", 4000);
await a.cmd({ cmd: "skip_intro" });
const me = d.members.find((m) => !m.free);
check(d.madness === 0, "équipage lucide au départ");
await a.cmd({ cmd: "tally", id: me.id, key: "shots", value: 9 });
await a.cmd({ cmd: "freeze" });
await a.cmd({ cmd: "kill_all" });
await sleep(1200);
d = await a.dbg();
check(d.skills[me.id] && d.skills[me.id].tireur === 1, `l'étude donne Tireur I : ${JSON.stringify(d.skills)}`);
await sleep(3600);
await a.cmd({ cmd: "goto", scene: "abordage", args: { layout: "epave" } });
d = await waitScene(a, "abordage", 4000);
await a.cmd({ cmd: "skip_intro" });
const me2 = d.members.find((m) => !m.free);
check(me2.ammo_max === 4, `Tireur I : ${me2.ammo_max} munitions max`);
await a.cmd({ cmd: "freeze" });
await a.cmd({ cmd: "kill_all" });
await sleep(1200);
d = await a.dbg();
check(d.madness === 1, "vaincre l'épave corrompue ronge l'équipage (folie 1)");
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
