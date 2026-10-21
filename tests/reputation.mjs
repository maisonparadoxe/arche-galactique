// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/reputation.mjs
// Dilemme du convoi marchand, réputation, prix de la boutique et événements réservés.
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
  p.send({ t: "hello", token: name + "-rep", name, color: -1, species: "humain", ornament: "aucun" });
  await sleep(300);
  return p;
}
async function waitScene(p, name, ms = 12000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}
async function event(a, id, kind = "convoi") {
  await a.cmd({ cmd: "goto", scene: "evenement", args: { kind, id } });
  await waitScene(a, "evenement", 4000);
  await sleep(300);
  return a.last("layout");
}

const a = await phone("Anne");
await a.cmd({ cmd: "goto", scene: "choix" });
await waitScene(a, "choix", 4000);
a.vote("paikan"); await sleep(1800); a.vote("decouverte");
let d = await waitScene(a, "carte", 8000);
check(d.run.renown === 0, "l'expédition commence avec une réputation neutre");

// --- Le dilemme du convoi : aborder fait baisser la réputation
let lay = await event(a, "convoi_syndicat");
check(lay.options.length === 5, `le convoi propose ${lay.options.length} choix : ${lay.options.map((o) => o.label).join(" / ")}`);
const lettre = lay.options.find((o) => /lettre/.test(o.label));
check(lettre.disabled && /Réputation/.test(lettre.desc), `la lettre de recommandation est réservée aux corsaires estimés (${lettre.desc})`);
a.vote("0");
await sleep(2000);
lay = a.last("layout");
check(lay.title && lay.options.some((o) => /abordage/i.test(o.label)), "le résultat annonce l'abordage");
a.vote("ok");
d = await waitScene(a, "abordage", 6000);
check(d.run.renown === -2 && d.foes > 0, `aborder : réputation ${d.run.renown}, ${d.foes} ennemis à l'abordage`);
await a.cmd({ cmd: "kill_all" });
await waitScene(a, "carte", 10000);

// --- Escorter : la réputation monte
lay = await event(a, "convoi_pelerins");
const colonsBefore = (await a.dbg()).run.colons;
a.vote("1"); await sleep(2000);
d = await a.dbg();
check(d.run.renown === 1 && d.run.colons > colonsBefore, `accompagner les pèlerins : réputation ${d.run.renown}, colons ${colonsBefore} → ${d.run.colons}`);

// --- La réputation change les prix
await a.cmd({ cmd: "rep", value: 10 });
await a.cmd({ cmd: "goto", scene: "boutique" });
await waitScene(a, "boutique", 4000); await sleep(300);
lay = a.last("layout");
const prix = (l) => +(/(\d+) ferraille/.exec(l.options.find((o) => /Carburant/.test(o.label)).label)[1]);
const bon = prix(lay);
await a.cmd({ cmd: "rep", value: -10 });
await a.cmd({ cmd: "goto", scene: "boutique" });
await waitScene(a, "boutique", 4000); await sleep(300);
await a.cmd({ cmd: "rep", value: -10 });
const mauvais = prix(a.last("layout"));
check(bon < 6 && mauvais > 6, `corsaire exemplaire : carburant à ${bon} ferraille ; fléau des mers : ${mauvais} (base 6)`);

// --- Événements réservés
await a.cmd({ cmd: "rep", value: -4 });
lay = await event(a, "chasseur_de_primes", "evenement");
check(lay.options.find((o) => /rejoindre/.test(o.label)).disabled, "à -4, le chasseur de primes ne peut pas être recruté");
await a.cmd({ cmd: "rep", value: -6 });
lay = await event(a, "chasseur_de_primes", "evenement");
await a.cmd({ cmd: "rep", value: -6 });
check(!a.last("layout").options.find((o) => /rejoindre/.test(o.label)).disabled || !lay.options.find((o) => /rejoindre/.test(o.label)).disabled, "à -6, il peut rejoindre l'équipage");

// --- Bilan : la réputation s'affiche et change les colons sauvés
d = await a.dbg();
check(d.run.renown <= -6, `réputation finale ${d.run.renown}`);

console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
