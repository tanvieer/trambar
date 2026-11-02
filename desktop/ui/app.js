// Panel and tray state for the Windows/Linux port. Mirrors Store.swift + Views.swift.
import * as EFA from "./efa.js";

const { invoke } = window.__TAURI__.core;
const autostart = window.__TAURI__.autostart;
const win = window.__TAURI__.window.getCurrentWindow();

const REFRESH = 30000;
const ICON = { tram: "🚋", bus: "🚌", train: "🚆", other: "🚶" };

let settings = { stops: [], routes: [], showNearby: true, order: [] };
let deps = {}, trips = {}, nearby = [];
let lastUpdate = null, error = null, locationMsg = null, editing = false, routeFrom = null;
let lastFix = null;

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const clock = (d) => d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
const routeId = (r) => r.from.id + ">" + r.to.id;

// CVAG platform codes like "TO" (tram, east side) become "east side".
// Track numbers and anything else are shown as they come.
// German when the system's language is German, English otherwise.
const DE = /^de\b/i.test(navigator.language);
const L = (en, de) => (DE ? de : en);
const SIDES = DE
  ? { N: "Nordseite", O: "Ostseite", S: "Südseite", W: "Westseite" }
  : { N: "north side", O: "east side", S: "south side", W: "west side" };
function platform(code) {
  const m = /^[A-Z]?([NOSW])$/.exec(code);
  return m ? SIDES[m[1]] : code;
}

// "now", "4 min", or a clock time once it is more than an hour away.
function countdown(d, now) {
  const m = Math.floor((d - now) / 60000);
  if (m < 1) return L("now", "jetzt");
  if (m < 60) return `${m} min`;
  return clock(d);
}

// Saved stops and routes in panel order. Without an order, routes come first.
function items() {
  const all = [
    ...settings.routes.map((r) => ({ id: "route:" + routeId(r), route: r })),
    ...settings.stops.map((s) => ({ id: "stop:" + s.id, stop: s })),
  ];
  const rank = new Map(settings.order.map((id, i) => [id, i]));
  return all.map((it, i) => [it, rank.get(it.id) ?? settings.order.length + i])
    .sort((a, b) => a[1] - b[1]).map((x) => x[0]);
}

const firstStop = () => items().find((i) => i.stop)?.stop ?? null;

function headline() {
  const id = firstStop()?.id ?? (settings.showNearby ? nearby[0]?.id : null);
  const cut = Date.now() - 30000;
  return (deps[id] || []).find((d) => !d.cancelled && d.when > cut) ?? null;
}

let trayTitle;
function updateTray() {
  const d = headline();
  const title = d ? `${d.line} · ${countdown(d.when, new Date())}` : null;
  if (title !== trayTitle) { trayTitle = title; invoke("set_tray", { title }); }
}

async function save() {
  await invoke("save_settings", { json: JSON.stringify(settings, null, 2) });
  refresh();
}

// MARK: refresh

async function refresh() {
  let failed = false;
  const ids = new Set([...settings.stops.map((s) => s.id), ...(settings.showNearby ? nearby.slice(0, 3).map((s) => s.id) : [])]);
  await Promise.all([
    ...[...ids].map((id) => EFA.departures(id).then((r) => (deps[id] = r), () => (failed = true))),
    ...settings.routes.map((r) => EFA.journeys(r.from.id, r.to.id).then((j) => (trips[routeId(r)] = j), () => (failed = true))),
  ]);
  error = failed ? L("Some data could not be loaded — showing the last known times.", "Einige Daten konnten nicht geladen werden – es werden die letzten bekannten Zeiten angezeigt.") : null;
  if (!failed) lastUpdate = new Date();
  updateTray();
  if (!editing) render();
}

// Desktop location goes through the webview: Windows Location service, GeoClue on Linux.
function locate() {
  if (!settings.showNearby) return;
  if (!navigator.geolocation) { locationMsg = L("Location is not available on this system.", "Standort ist auf diesem System nicht verfügbar."); return; }
  navigator.geolocation.getCurrentPosition(async (p) => {
    locationMsg = null;
    const { latitude: lat, longitude: lon } = p.coords;
    // Only look stops up again once we have moved; Wi-Fi fixes jitter a little.
    if (lastFix && nearby.length && distance(lastFix, [lat, lon]) < 75) return;
    lastFix = [lat, lon];
    try { nearby = await EFA.nearbyStops(lat, lon); refresh(); } catch {}
  }, () => {
    locationMsg = L("Location is off for TramBar. Turn on location services in your system settings.", "Standort ist für TramBar aus. Schalte die Ortungsdienste in den Systemeinstellungen ein.");
    if (!editing) render();
  }, { timeout: 20000, maximumAge: 120000 });
}

function distance([a, b], [c, d]) {
  const r = Math.PI / 180, x = (d - b) * r * Math.cos(((a + c) / 2) * r), y = (c - a) * r;
  return Math.hypot(x, y) * 6371000;
}

// MARK: render

function delayBadge(min, realtime) {
  if (min > 0) return `<span class="late">+${min}</span>`;
  return realtime ? `<span class="live" title="Live">●</span>` : "";
}

function stopCard(title, subtitle, list, now, max = 5) {
  let rows;
  if (!list) rows = `<div class="muted">${L("Loading…", "Lädt…")}</div>`;
  else {
    const up = list.filter((d) => d.when > now - 30000).slice(0, max);
    rows = up.length ? up.map((d) => `
      <div class="row${d.cancelled ? " cancelled" : ""}" title="${esc(d.line)} → ${esc(d.destination)}, ${L("planned", "planmäßig")} ${clock(d.planned)}">
        <span class="kind">${ICON[d.kind]}</span><b class="line">${esc(d.line)}</b>
        <span class="dest">${esc(d.destination)}</span>
        ${d.platform ? `<span class="small muted" title="${L("Platform", "Steig")} ${esc(d.platform)}">${esc(platform(d.platform))}</span>` : ""}
        <span class="spacer"></span>
        ${d.cancelled ? `<span class="late small">${L("cancelled", "fällt aus")}</span>` : `${delayBadge(d.delay, !!d.estimated)}<b class="time">${countdown(d.when, now)}</b>`}
      </div>`).join("") : `<div class="muted small">${L("No departures soon", "Keine Abfahrten in Kürze")}</div>`;
  }
  return `<section class="card"><h3>${esc(title)}${subtitle ? ` <span class="small muted">${esc(subtitle)}</span>` : ""}</h3>${rows}</section>`;
}

function routeCard(r, now) {
  const up = (trips[routeId(r)] || []).filter((j) => j.departs > now - 30000).slice(0, 2);
  const rows = up.length ? up.map((j) => `
    <div class="row${j.cancelled ? " cancelled" : ""}">
      <b class="dest">${esc(j.lines.join(" › "))}</b>
      ${j.platform ? `<span class="small muted">${platform(j.platform) === j.platform ? "Gl. " + esc(j.platform) : esc(platform(j.platform))}</span>` : ""}
      <span class="spacer"></span>
      ${j.cancelled ? `<span class="late small">${L("cancelled", "fällt aus")}</span>` :
        `<span class="muted">${clock(j.departs)} → ${clock(j.arrives)}</span>${delayBadge(j.delay, j.realtime)}<b class="time">${countdown(j.departs, now)}</b>`}
    </div>`).join("") : `<div class="muted small">${L("Loading…", "Lädt…")}</div>`;
  return `<section class="card"><h3>${esc(r.from.name)} → ${esc(r.to.name)}</h3>${rows}</section>`;
}

function renderDepartures() {
  const now = new Date();
  let h = error ? `<div class="warn small">⚠ ${esc(error)}</div>` : "";
  for (const it of items()) h += it.route ? routeCard(it.route, now) : stopCard(it.stop.name, null, deps[it.stop.id], now);
  if (settings.showNearby) {
    const saved = new Set(settings.stops.map((s) => s.id));
    const near = nearby.filter((s) => !saved.has(s.id)).slice(0, 3);
    h += `<div class="label">${L("NEAR YOU", "IN DER NÄHE")}</div>`;
    if (locationMsg) h += `<div class="muted small">${esc(locationMsg)}</div>`;
    else if (!near.length) h += `<div class="muted small">${L("Finding stops near you…", "Suche Haltestellen in der Nähe…")}</div>`;
    for (const s of near) h += stopCard(s.name, s.distance != null ? `${s.distance} m` : null, deps[s.id], now, 4);
  }
  if (!settings.stops.length && !settings.routes.length && !settings.showNearby)
    h += `<div class="muted">${L("Nothing saved yet. Press Edit to add a stop or a route.", "Noch nichts gespeichert. Mit „Bearbeiten“ fügst du eine Haltestelle oder Strecke hinzu.")}</div>`;
  $("#body").innerHTML = h;
}

function renderEdit() {
  const list = items(), first = firstStop()?.id;
  $("#body").innerHTML = `
    <div class="label">${L("SAVED · TOP TO BOTTOM", "GESPEICHERT · VON OBEN NACH UNTEN")}</div>
    ${list.length ? "" : `<div class="muted small">${L("Nothing saved yet.", "Noch nichts gespeichert.")}</div>`}
    ${list.map((it, i) => `
      <div class="row edit">
        <span class="dest">${it.stop ? esc(EFA.fullName(it.stop)) + (it.stop.id === first ? ` <span class="small muted" title="${L("Shown in the tray: the highest stop in this list", "Im Tray: die oberste Haltestelle dieser Liste")}">· tray</span>` : "")
          : `${esc(it.route.from.name)} → ${esc(it.route.to.name)}`}</span>
        <span class="spacer"></span>
        <button data-move="${i}:-1" ${i === 0 ? "disabled" : ""} title="${L("Move up", "Nach oben")}">▲</button>
        <button data-move="${i}:1" ${i === list.length - 1 ? "disabled" : ""} title="${L("Move down", "Nach unten")}">▼</button>
        <button data-remove="${i}" title="${L("Remove", "Entfernen")}">−</button>
      </div>`).join("")}
    <hr>
    <div class="search" data-kind="stop"><input placeholder="${L("Add a stop…", "Haltestelle hinzufügen…")}"><div class="results"></div></div>
    ${routeFrom ? `<div class="row small"><span>${L("From", "Von")} ${esc(routeFrom.name)}</span><span class="spacer"></span><button id="cancelRoute">${L("Cancel", "Abbrechen")}</button></div>
      <div class="search" data-kind="to"><input placeholder="${L("To…", "Nach…")}"><div class="results"></div></div>`
      : `<div class="search" data-kind="from"><input placeholder="${L("Add a route: from…", "Strecke hinzufügen: von…")}"><div class="results"></div></div>`}
    <hr>
    <label class="row"><input type="checkbox" id="nearby" ${settings.showNearby ? "checked" : ""}> ${L("Show stops near my location", "Haltestellen in meiner Nähe zeigen")}</label>
    <label class="row"><input type="checkbox" id="autostart"> ${L("Open at login", "Beim Anmelden öffnen")}</label>`;

  $("#body").querySelectorAll("[data-move]").forEach((b) => (b.onclick = () => {
    const [i, off] = b.dataset.move.split(":").map(Number);
    const ids = list.map((x) => x.id);
    [ids[i], ids[i + off]] = [ids[i + off], ids[i]];
    settings.order = ids; save(); renderEdit();
  }));
  $("#body").querySelectorAll("[data-remove]").forEach((b) => (b.onclick = () => {
    const it = list[Number(b.dataset.remove)];
    if (it.stop) settings.stops = settings.stops.filter((s) => s.id !== it.stop.id);
    else settings.routes = settings.routes.filter((r) => routeId(r) !== routeId(it.route));
    save(); renderEdit();
  }));
  $("#body").querySelectorAll(".search").forEach(wireSearch);
  const cancel = $("#cancelRoute");
  if (cancel) cancel.onclick = () => { routeFrom = null; renderEdit(); };
  $("#nearby").onchange = (e) => {
    settings.showNearby = e.target.checked;
    if (settings.showNearby) locate(); else nearby = [];
    save();
  };
  const auto = $("#autostart");
  autostart.isEnabled().then((on) => (auto.checked = on));
  auto.onchange = () => (auto.checked ? autostart.enable() : autostart.disable());
}

function wireSearch(box) {
  const input = box.querySelector("input"), out = box.querySelector(".results");
  let timer, seq = 0;
  input.oninput = () => {
    clearTimeout(timer);
    const v = input.value.trim();
    if (v.length < 3) { out.innerHTML = ""; return; }
    timer = setTimeout(async () => {
      const mine = ++seq;
      const res = (await EFA.searchStops(v).catch(() => [])).slice(0, 6);
      if (mine !== seq) return;
      out.innerHTML = res.map((s, i) => `<button class="result" data-i="${i}">${esc(EFA.fullName(s))}</button>`).join("");
      out.querySelectorAll("button").forEach((b) => (b.onclick = () => pick(box.dataset.kind, res[Number(b.dataset.i)])));
    }, 300);
  };
}

function pick(kind, s) {
  s = { ...s, distance: null };
  if (kind === "stop") {
    if (!settings.stops.some((x) => x.id === s.id)) settings.stops.push(s);
    save();
  } else if (kind === "from") {
    routeFrom = s;
  } else {
    const r = { from: routeFrom, to: s };
    if (!settings.routes.some((x) => routeId(x) === routeId(r))) settings.routes.push(r);
    routeFrom = null;
    save();
  }
  renderEdit();
}

function render() {
  $("#title").textContent = editing ? L("Edit stops & routes", "Haltestellen & Strecken bearbeiten") : L("Departures", "Abfahrten");
  $("#edit").textContent = editing ? L("Done", "Fertig") : L("Edit", "Bearbeiten");
  $("#updated").textContent = !editing && lastUpdate ? `${L("updated", "aktualisiert")} ${clock(lastUpdate)}` : "";
  $("#reload").hidden = editing;
  editing ? renderEdit() : renderDepartures();
}

// MARK: start

$("#edit").onclick = () => { editing = !editing; routeFrom = null; render(); };
$("#reload").onclick = () => refresh();
$("#quit").onclick = () => invoke("quit");
$("#reload").title = L("Refresh now", "Jetzt aktualisieren");
$("#quit").title = L("Quit TramBar", "TramBar beenden");
document.addEventListener("keydown", (e) => e.key === "Escape" && win.hide());
window.onPanelShown = () => { if (!editing) render(); };

try { settings = { ...settings, ...JSON.parse(await invoke("load_settings")) }; } catch {}
render();
refresh();
locate();
setInterval(refresh, REFRESH);
setInterval(() => { updateTray(); if (!editing) renderDepartures(); }, 15000);
setInterval(locate, 5 * 60000);
