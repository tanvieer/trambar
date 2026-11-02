// Client for the public EFA servers. Free, no key. Port of EFA.swift.
// VMS (hosted by VVO) finds stops anywhere in Germany, but only has realtime for
// Saxony. Stop ids carry the state ("de:09:..." is Bavaria), so departures and
// trips go to the server of that state when it has its own live data.
const VMS = "https://efa.vvo-online.de/VMSSL3/";
const REGIONAL = {
  "05": "https://efa.vrr.de/standard/",     // North Rhine-Westphalia (VRR)
  "08": "https://www.efa-bw.de/nvbw/",      // Baden-Württemberg (NVBW)
  "09": "https://bahnland-bayern.de/efa/",  // Bavaria (BEG)
};
const serverFor = (stopID) => REGIONAL[stopID.split(":")[1]] ?? VMS;
// Plain fetch hits CORS on servers without the header; the Tauri one does not.
const httpFetch = window.__TAURI__?.http?.fetch ?? fetch;

async function get(endpoint, params, base = VMS) {
  const q = new URLSearchParams({ outputFormat: "rapidJSON", language: "de", ...params });
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15000);
  try {
    const r = await httpFetch(base + endpoint + "?" + q, { signal: ctrl.signal });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return await r.json();
  } finally {
    clearTimeout(t);
  }
}

// "Chemnitz, Bernsdorf" -> "Bernsdorf": every stop here is in Chemnitz anyway.
const shortPlace = (n) => (n.startsWith("Chemnitz, ") ? n.slice(10) : n);
const date = (v) => (typeof v === "string" ? new Date(v) : null);
const isCancelled = (x) =>
  (x.realtimeStatus || []).some((s) => s.includes("CANCEL")) || x.isCancelled === true;

function kind(c) {
  if (c === 4) return "tram";
  if ([5, 6, 7, 10, 11].includes(c)) return "bus";
  if ([0, 1, 2, 3, 13, 14, 15, 16].includes(c)) return "train";
  return "other";
}

function stop(l) {
  if (!l.id) return null;
  const d = l.properties?.distance;
  return {
    id: l.id,
    name: l.disassembledName || shortPlace(l.name || l.id),
    place: l.parent?.name ?? null,
    distance: d == null ? null : Number(d),
  };
}

export const fullName = (s) => (s.place ? `${s.name}, ${s.place}` : s.name);
const mins = (est, plan) => (est ? Math.round((est - plan) / 60000) : 0);

export async function searchStops(text) {
  const j = await get("XML_STOPFINDER_REQUEST", { type_sf: "any", name_sf: text, anyObjFilter_sf: "2" });
  return (j.locations || []).map(stop).filter(Boolean);
}

export async function nearbyStops(lat, lon, radius = 1000, max = 5) {
  const j = await get("XML_COORD_REQUEST", {
    coord: `${lon.toFixed(6)}:${lat.toFixed(6)}:WGS84[DD.DDDDD]`,
    coordOutputFormat: "WGS84[DD.DDDDD]",
    type_1: "STOP", radius_1: String(radius), inclFilter: "1", max: String(max),
  });
  return (j.locations || []).map(stop).filter(Boolean)
    .sort((a, b) => (a.distance ?? 1e9) - (b.distance ?? 1e9));
}

export async function departures(stopID, limit = 8) {
  const j = await get("XML_DM_REQUEST", {
    type_dm: "stop", name_dm: stopID, mode: "direct", useRealtime: "1", limit: String(limit),
  }, serverFor(stopID));
  return (j.stopEvents || []).flatMap((e) => {
    const t = e.transportation;
    const planned = date(e.departureTimePlanned);
    if (!t || !planned) return [];
    const estimated = date(e.departureTimeEstimated);
    const platform = e.location?.properties?.platform || null;
    return [{
      line: t.number || t.disassembledName || "?",
      kind: kind(t.product?.class),
      destination: shortPlace(t.destination?.name || ""),
      planned, estimated, platform,
      cancelled: isCancelled(e),
      when: estimated || planned,
      delay: mins(estimated, planned),
    }];
  });
}

export async function journeys(from, to, count = 4) {
  const j = await get("XML_TRIP_REQUEST2", {
    type_origin: "stop", name_origin: from,
    type_destination: "stop", name_destination: to,
    useRealtime: "1", calcNumberOfTrips: String(count),
  }, serverFor(from));
  return (j.journeys || []).flatMap((jr) => {
    const legs = jr.legs || [];
    const o = legs[0]?.origin, d = legs.at(-1)?.destination;
    const depP = date(o?.departureTimePlanned), arrP = date(d?.arrivalTimePlanned);
    if (!depP || !arrP) return [];
    const depE = date(o.departureTimeEstimated), arrE = date(d.arrivalTimeEstimated);
    // Footpaths have no line number; leave them out of the summary.
    const lines = legs.map((l) => l.transportation?.disassembledName || l.transportation?.number).filter(Boolean);
    return [{
      lines, platform: o.properties?.platform || null,
      cancelled: legs.some(isCancelled),
      departs: depE || depP, arrives: arrE || arrP,
      realtime: !!depE, delay: mins(depE, depP),
    }];
  });
}
