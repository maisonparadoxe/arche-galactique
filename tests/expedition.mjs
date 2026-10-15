// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/expedition.mjs
// Variable SHOTS=dossier pour enregistrer une capture de chaque écran (rendu graphique nécessaire).
// Deux faux téléphones jouent une expédition complète (victoire), puis une seconde (défaite).
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const N = [false, false, false, false];
const SHOT_DIR = process.env.SHOTS || "";
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? "OK  " : "FAIL"} ${label}`); if (!ok) failures++; };

async function phone(profile) {
  const ws = new WebSocket("ws://127.0.0.1:9080");
  const inbox = [];
  ws.onmessage = (e) => inbox.push(JSON.parse(e.data));
  await new Promise((r) => (ws.onopen = r));
  const p = {
    ws, inbox, x: 0, y: 0, b: N, name: profile.name,
    send: (o) => ws.send(JSON.stringify(o)),
    last: (t) => [...inbox].reverse().find((m) => m.t === t),
    async dbg() { const n = inbox.length; p.send({ t: "dbg" }); for (let i = 0; i < 60; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } throw new Error("pas de réponse dbg"); },
    async cmd(o) { p.send({ t: "dbg_cmd", ...o }); await sleep(80); },
    async tp(x, y) { p.send({ t: "dbg_tp", x, y }); await sleep(80); },
    vote: (id) => p.send({ t: "vote", id }),
  };
  setInterval(() => p.send({ t: "in", x: p.x, y: p.y, b: p.b }), 33);
  p.send({ t: "hello", token: profile.name + "-tok", ...profile });
  await sleep(250);
  return p;
}
async function hold(p, b, ms) { p.b = b; await sleep(ms); p.b = N; await sleep(120); }
async function waitScene(p, name, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  const d = await p.dbg(); throw new Error(`scène attendue ${name}, actuelle ${d.scene}`);
}
async function waitNotScene(p, name, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene !== name) return d; await sleep(150); }
  throw new Error(`toujours dans ${name}`);
}
let shotN = 0;
async function shot(p, label) { if (SHOT_DIR) { await p.cmd({ cmd: "shot", path: `${SHOT_DIR}/${String(++shotN).padStart(2, "0")}-${label}.png` }); await sleep(250); } }
const both = (a, b, id) => { a.vote(id); b.vote(id); };

const a = await phone({ name: "Pascal", color: 0, species: "humain", ornament: "couronne" });
const b = await phone({ name: "Éléa", color: 1, species: "salamandrin", ornament: "fleur" });

// ---- Académie → choix du vaisseau
let d = await a.dbg();
check(d.scene === "academie", "on démarre à l'Académie");
await a.tp(500, 618);
await hold(a, [true, false, false, false], 120);
d = await waitScene(a, "choix");
check(a.last("layout").mode === "vote" && a.last("layout").options.length === 3, "les téléphones affichent le vote des 3 vaisseaux");
await shot(a, "choix-vaisseau");
a.vote("paikan"); b.vote("nautile"); await sleep(300);
b.vote("paikan");
await sleep(1800);
check(a.last("layout").mode === "vote" && a.last("layout").options.map((o) => o.id).join() === "decouverte,normal,difficile", "puis vote de la difficulté (Découverte, Normal, Difficile)");
await shot(a, "choix-difficulte");
both(a, b, "normal");
d = await waitScene(a, "carte", 8000);
check(d.run.ship === "paikan" && d.run.fuel === 4, `expédition lancée sur le Païkan (carburant ${d.run.fuel})`);
check(a.last("vote_done") && a.last("vote_done").id === "normal", "le résultat du vote est annoncé sur le téléphone");

// ---- Parcours de la carte jusqu'au boss
let combatTested = false, shopTested = false, eventTested = false, guard = 0;
while (guard++ < 30) {
  d = await a.dbg();
  if (d.scene === "bilan") break;
  if (d.scene === "carte") {
    if (shotN < 3) await shot(a, "carte");
    const ch = d.choices;
    // on préfère ce qui n'a pas encore été testé
    const pref = ch.find((c) => c.type === "combat" && !combatTested) || ch.find((c) => c.type === "boutique" && !shopTested)
      || ch.find((c) => (c.type === "evenement" || c.type === "halte") && !eventTested) || ch[0];
    const fuelBefore = d.run.fuel;
    both(a, b, String(pref.id));
    d = await waitNotScene(a, "carte", 8000);
    check(d.run.fuel === Math.max(0, fuelBefore - 1) || fuelBefore === 0, `saut vers « ${pref.type} » (carburant ${fuelBefore} → ${d.run.fuel})`);
    continue;
  }
  if (d.scene === "combat") {
    if (!combatTested) {
      combatTested = true;
      await a.cmd({ cmd: "freeze_enemy" });
      d = await a.dbg();
      check(d.enemy_hull > 0 && d.weapons.length === 2, `combat contre ${d.enemy} (coque ${d.enemy_hull})`);
      // Murs et portes : traverser de la coursive vers l'armurerie en passant par la porte
      const armes = d.rooms.find((r) => r.id === "armes");
      // Poste d'armes
      await a.tp(d.console_x - 40, d.console_y);
      await hold(a, [true, false, false, false], 120);
      d = await a.dbg();
      check(d.gunner > 0 && a.last("layout").mode === "armes", "Pascal s'installe au poste d'armes, la manette change");
      // Viser la salle des boucliers ennemie et attendre la charge
      const target = d.enemy_rooms.find((r) => r.id === "boucliers");
      for (let i = 0; i < 80; i++) {
        d = await a.dbg();
        const dx = target.x - d.cross_x, dy = target.y - d.cross_y, dist = Math.hypot(dx, dy);
        if (dist < 10) break;
        const k = Math.min(1, dist / 50); a.x = dx / dist * k; a.y = dy / dist * k; await sleep(40);
      }
      a.x = 0; a.y = 0;
      for (let i = 0; i < 60 && !(await a.dbg()).weapons[0].ready; i++) await sleep(200);
      const before = await a.dbg();
      check(a.last("armes") && a.last("armes").weapons.length === 2, "le téléphone reçoit la charge des armes");
      await shot(a, "combat-visee");
      a.send({ t: "act", a: "fire", w: 0 }); await sleep(150);
      a.send({ t: "act", a: "fire", w: 1 }); await sleep(1100);
      d = await a.dbg();
      const hurt = d.enemy_hull < before.enemy_hull || d.enemy_shields < before.enemy_shields;
      check(hurt, `tir manuel : coque ennemie ${before.enemy_hull} → ${d.enemy_hull}, boucliers ${before.enemy_shields} → ${d.enemy_shields}`);
      a.send({ t: "act", a: "quit" }); await sleep(150);
      check(a.last("layout").mode === "base", "Pascal quitte le poste");
      // Incendie : la Salamandrine l'éteint
      await a.cmd({ cmd: "fire", room: "coursive" });
      d = await a.dbg();
      check(d.fires.length >= 1, "un incendie se déclare dans la coursive");
      const f = d.fires.find((x) => x[2] === "coursive");
      await b.tp(f[0] - 30, f[1]);
      await hold(b, [false, true, false, false], 2300);
      d = await a.dbg();
      check(!d.fires.some((x) => x[2] === "coursive"), "Éléa éteint l'incendie");
      // Réparation : l'Humain répare les armes
      await a.cmd({ cmd: "damage", system: "armes" });
      d = await a.dbg();
      check(d.sys_damage.armes === 1, "les armes sont endommagées");
      await a.tp(armes.x - 50, armes.y + 10);
      await hold(a, [false, true, false, false], 2800);
      d = await a.dbg();
      check(d.sys_damage.armes === 0, "Pascal répare les armes");
      // Déplacement à travers une porte : de la coursive vers le pont (à droite)
      const cours = d.rooms.find((r) => r.id === "coursive"), pont = d.rooms.find((r) => r.id === "pont");
      await a.tp(cours.x + 60, cours.y + 20);  // légèrement décalé de la porte : le glissement doit aider
      a.x = 1; await sleep(1500); a.x = 0; await sleep(80);
      d = await a.dbg();
      check(d.x > pont.x - 40, `passage de porte coursive → pont (x = ${d.x.toFixed(0)}, pont = ${pont.x.toFixed(0)})`);
      await shot(a, "combat");
    }
    await a.cmd({ cmd: "enemy_hull", value: 0 });
    d = await a.dbg();
    check(d.state === "won", `victoire contre ${d.enemy}`);
    await waitNotScene(a, "combat", 8000);
    continue;
  }
  if (d.scene === "evenement") {
    if (!eventTested) { eventTested = true; await shot(a, "evenement"); }
    const lay = a.last("layout");
    const opt = lay.options.find((o) => !o.disabled);
    both(a, b, opt.id);
    await sleep(1600);
    d = await a.dbg();
    check(d.phase === "resultat", `événement « ${d.event} » : choix « ${opt.label} »`);
    if (shotN < 8) await shot(a, "evenement-resultat");
    both(a, b, "ok");
    await waitNotScene(a, "evenement", 6000);
    continue;
  }
  if (d.scene === "boutique") {
    if (!shopTested) {
      shopTested = true;
      await shot(a, "boutique");
      const lay = a.last("layout");
      const fuelOpt = lay.options.find((o) => o.id === "carburant");
      const before = d.run;
      if (fuelOpt && !fuelOpt.disabled) {
        both(a, b, "carburant"); await sleep(1700);
        d = await a.dbg();
        check(d.run.fuel === before.fuel + 3 && d.run.scrap === before.scrap - 6, `achat de carburant (${before.fuel}→${d.run.fuel}, ferraille ${before.scrap}→${d.run.scrap})`);
      } else {
        check(true, `boutique visitée (ferraille ${before.scrap}, carburant trop cher)`);
      }
    }
    both(a, b, "partir");
    await waitNotScene(a, "boutique", 6000);
    continue;
  }
  if (d.scene === "academie") throw new Error("retour inattendu à l'Académie");
  await sleep(300);
}
d = await waitScene(a, "bilan", 10000);
check(d.run.victory === true, `fin d'expédition : victoire (coque ${d.run.hull}/${d.run.hull_max}, colons ${d.run.colons})`);
check(combatTested, `scènes traversées : combat ${combatTested}, boutique ${shopTested}, événement ${eventTested} (selon la carte tirée)`);
await shot(a, "bilan-victoire");
both(a, b, "retour");
d = await waitScene(a, "academie", 6000);
check(a.last("layout").mode === "base", "retour à l'Académie, manette de base");

// ---- Deuxième expédition : défaite
await a.tp(500, 618);
await hold(a, [true, false, false, false], 120);
await waitScene(a, "choix");
both(a, b, "libellule");
await sleep(1800);
both(a, b, "decouverte");
d = await waitScene(a, "carte", 8000);
check(d.run.difficulty === "decouverte" && d.run.layers === 4 && d.run.fuel === 6 && d.run.scrap === 25, `Découverte : 3 sauts, carburant ${d.run.fuel}, ferraille ${d.run.scrap}`);
check(d.run.ship === "libellule" && d.run.hull === 22, "nouvelle expédition sur la Libellule");
const combat = d.choices.find((c) => c.type === "combat");
both(a, b, String(combat.id));
d = await waitScene(a, "combat", 8000);
check(d.rooms.length === 5, "plan de la Libellule (5 salles)");
check(d.enemy_hull === 4, `en Découverte, l'éclaireur n'a que ${d.enemy_hull} de coque (8 en Normal)`);
await a.cmd({ cmd: "hull", value: 0 });
d = await a.dbg();
check(d.state === "lost", "la coque tombe à zéro : défaite");
d = await waitScene(a, "bilan", 8000);
check(d.run.victory === false, "bilan de défaite");
await shot(a, "bilan-defaite");

console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
