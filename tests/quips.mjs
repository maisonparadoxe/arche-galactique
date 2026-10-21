// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/quips.mjs
// Répliques humoristiques : bulles rares, avec délai.
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
  p.send({ t: "hello", token: name + "-quip", name, color: -1, species: "humain", ornament: "aucun" });
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
await sleep(300);
let d = await a.dbg();
check(d.quips.length === 0, "pas de réplique au repos");
await a.cmd({ cmd: "quip", situation: "victoire" });
d = await a.dbg();
check(d.quips.length === 1 && d.quips[0].length > 10, `une réplique s'affiche : « ${d.quips[0]} »`);
await sleep(4200);
d = await a.dbg();
check(d.quips.length === 0, "la bulle disparaît après quelques secondes");
// Rareté : sans forcer, le délai global bloque les répliques qui suivent.
await a.cmd({ cmd: "quip", situation: "coffre" });
d = await a.dbg();
check(d.quips.length === 1, "réplique forcée suivante");
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
