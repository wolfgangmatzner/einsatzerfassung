// Einsatzerfassung – App-Hülle offline verfügbar machen
const CACHE = "einsatz-v2";
const DATEIEN = ["./", "index.html", "lib/supabase.js", "lib/jspdf.umd.min.js", "manifest.json", "icon-192.png", "icon-512.png", "icon-180.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(DATEIEN)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.endsWith("version.txt")) return; // Supabase-Aufrufe nie cachen
  // Netz zuerst (immer aktuelle Version), bei fehlendem/zu langsamem Netz aus dem Cache
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const treffer = await cache.match(e.request, { ignoreSearch: true });
    try {
      const netz = await Promise.race([
        fetch(e.request),
        new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), treffer ? 4000 : 20000)),
      ]);
      if (netz && netz.ok) cache.put(e.request, netz.clone());
      return netz;
    } catch (err) {
      if (treffer) return treffer;
      throw err;
    }
  })());
});
