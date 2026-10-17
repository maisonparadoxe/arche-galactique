// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/abordage.mjs
// Trois faux téléphones à l'abordage : caméra solidaire, relève, coups, victoire et repli.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const N = [false, false, false, false];
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? "OK  " : "FAIL"} ${label}`); if (!ok) failures++; };

async function phone(name, species) {
  const ws = new WebSocket("ws://127.0.0.1:9080");
  const inbox = [];
  ws.onmessage = (e) => inbox.push(JSON.parse(e.data));
  await new Promise((r) => (ws.onopen = r));
  const p = {
    ws, inbox, name, x: 0, y: 0, b: N,
    send: (o) => ws.readyState === 1 && ws.send(JSON.stringify(o)),
    last: (t) => [...inbox].reverse().find((m) => m.t === t),
    async dbg() { const n = inbox.length; p.send({ t: "dbg" }); for (let i = 0; i < 60; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } throw new Error("pas de réponse dbg"); },
    async cmd(o) { p.send({ t: "dbg_cmd", ...o }); await sleep(100); },
    async tp(x, y) { p.send({ t: "dbg_tp", x, y }); await sleep(100); },
  };
  setInterval(() => p.send({ t: "in", x: p.x, y: p.y, b: p.b }), 33);
  p.send({ t: "hello", token: name + "-ab", name, color: -1, species, ornament: "aucun" });
  await sleep(300);
  return p;
}
async function hold(p, b, ms) { p.b = b; await sleep(ms); p.b = N; await sleep(120); }
const A = [true, false, false, false], B = [false, true, false, false];
async function waitScene(p, name, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}

const a = await phone("Anne", "humain");
const b = await phone("Boris", "automate");
const c = await phone("Clara", "colosse");
await a.cmd({ cmd: "goto", scene: "abordage", args: { layout: "galion" } });
let d = await waitScene(a, "abordage", 5000);
check(d.foes >= 8 && d.chests === 4, `galion : ${d.foes} ennemis, ${d.chests} coffres, ${d.members.length} membres d'équipage`);
check(d.members.every((m) => m.x < 330), "tout l'équipage démarre sur la passerelle");
await a.cmd({ cmd: "freeze" });
await sleep(2000);
d = await a.dbg();
check(d.state === "fight", "l'introduction est passée : le combat commence");
check(a.last("hint") && a.last("hint").hints["0"] === "Frapper" && a.last("hint").hints["2"] === "Roulade" && /^Tirer/.test(a.last("hint").hints["1"]),
  `touches affichées : ${JSON.stringify(a.last("hint")?.hints)}`);

// --- Solidarité : un seul joueur avance, les autres restent à la passerelle
a.y = 0; a.x = 1;
await sleep(8500);
d = await a.dbg();
const ma = d.members.find((m) => m.id === d.me);
check(ma.x - d.cam_x <= 1280 - 40, `le joueur qui court ne sort pas de l'image (x ${Math.round(ma.x)}, caméra ${Math.round(d.cam_x)})`);
const behind = d.members.filter((m) => !m.downed && m.id !== d.me && m.x < ma.x - 480);
check(d.cam_x < 400 && behind.length >= 1, `la caméra ne suit pas un joueur seul (caméra ${Math.round(d.cam_x)}, ${behind.length} équipier(s) à la traîne)`);
check(d.blocked[0] > 0 && d.laggard !== 0, `le groupe est retenu : on désigne l'équipier en retard (n° ${d.laggard}, ${d.blocked_t.toFixed(1)} s)`);

// --- Tout le monde avance : la caméra suit
b.x = 1; c.x = 1;
await sleep(7000);
d = await a.dbg();
const inView = d.members.filter((m) => !m.downed).every((m) => m.x >= d.cam_x - 1 && m.x <= d.cam_x + 1280 + 1);
check(d.cam_x > 250, `groupe uni : la caméra avance (${Math.round(d.cam_x)})`);
check(inView, "personne ne sort de l'image");
a.x = 0; b.x = 0; c.x = 0;

// --- À terre et relevé
d = await a.dbg();
const bId = (await b.dbg()).me;
await b.cmd({ cmd: "down", id: bId });
d = await a.dbg();
check(d.members.find((m) => m.id === bId).downed, "Boris est à terre");
check(b.last("hint") && b.last("hint").hints["3"] === "Changer" && Object.keys(b.last("hint").hints).length === 1, "à terre, son téléphone ne propose plus que « Changer »");
const mb = d.members.find((m) => m.id === bId);
await c.cmd({ cmd: "tp_member", id: (await c.dbg()).me, x: mb.x + 30, y: mb.y });
await a.cmd({ cmd: "tp_member", id: (await a.dbg()).me, x: mb.x - 30, y: mb.y });
await sleep(1800);
d = await a.dbg();
check(d.members.find((m) => m.id === bId).revive > 0 || !d.members.find((m) => m.id === bId).downed, "des équipiers proches relèvent Boris");
await sleep(2500);
d = await a.dbg();
check(!d.members.find((m) => m.id === bId).downed, "Boris est debout");

// --- Un coup d'épée tue
await a.cmd({ cmd: "freeze", on: true });
d = await a.dbg();
const target = d.foe_list.find((f) => f.type === "marin");
await a.cmd({ cmd: "cam", x: Math.max(0, target.x - 640), y: 0 });
await a.cmd({ cmd: "tp_all", x: target.x - 40, y: target.y });
await sleep(200);
const before = (await a.dbg()).foes;
await hold(a, A, 150);
d = await a.dbg();
check(d.foes < before && d.kills >= 1, `un coup d'épée a tué un ennemi (${before} → ${d.foes})`);

// --- Le pistolet vise tout seul
d = await a.dbg();
const far = d.foe_list.filter((f) => f.type !== "capitaine" && f.x > 1020 && f.x < 1260).sort((p, q) => q.x - p.x)[0];
await a.cmd({ cmd: "cam", x: Math.max(0, far.x - 900), y: 0 });
await a.cmd({ cmd: "tp_all", x: far.x - 170, y: far.y });
a.x = 0.3; await sleep(120); a.x = 0;   // se tourner vers la droite
await sleep(200);
const b4 = (await a.dbg()).foes;
await hold(a, B, 900);
d = await a.dbg();
check(d.foes < b4, `le pistolet touche sans viser (${b4} → ${d.foes})`);
check(/^Tirer/.test(a.last("hint").hints["1"]) && a.last("hint").hints["1"].includes("○"), `les cartouches se vident sur la manette (${a.last("hint").hints["1"]})`);

// --- Victoire
await a.cmd({ cmd: "kill_all" });
await sleep(500);
d = await a.dbg();
check(d.state === "won", "tous les ennemis vaincus : abordage réussi");
d = await waitScene(a, "carte", 9000);
check(d.run.scrap >= 10, `retour à la carte, ferraille ${d.run.scrap}`);

// --- Île, puis repli
await a.cmd({ cmd: "goto", scene: "abordage", args: { layout: "ile" } });
d = await waitScene(a, "abordage", 5000);
check(d.layout_id === "ile" && d.world_w > 2000, `île au trésor : monde de ${d.world_w} px, ${d.foes} ennemis`);
await a.cmd({ cmd: "freeze" });
await sleep(2000);
const hull0 = (await a.dbg()).run.hull;
for (const m of (await a.dbg()).members) await a.cmd({ cmd: "down", id: m.id });
await sleep(500);
d = await a.dbg();
check(d.state === "lost", "tout l'équipage à terre : repli");
await waitScene(a, "carte", 9000);
d = await a.dbg();
check(d.run.hull === hull0 - 3, `le repli coûte 3 de coque (${hull0} → ${d.run.hull})`);

console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
