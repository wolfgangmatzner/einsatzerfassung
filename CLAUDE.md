# Einsatzerfassung FF Auersthal – Entwicklerhinweise

Tablet-Web-App (PWA) der Freiwilligen Feuerwehr Auersthal zur Einsatzerfassung. Sprache der App und der Kommunikation mit dem Auftraggeber (Wolfgang Matzner): Deutsch.

## Aufbau
- `index.html` – gesamte App (HTML/CSS/JS in einer Datei, kein Build, kein Framework)
- `lib/` – supabase-js 2.119.0 und jsPDF 2.5.1, lokal eingebunden (keine CDNs)
- `sw.js` – Service Worker (Netz zuerst, Cache als Rückfall; `version.txt` wird nie gecacht). Bei Änderung der Dateiliste `CACHE`-Namen erhöhen
- `manifest.json`, `icon*.png`, `icon.svg` – PWA
- `supabase/schema.sql` – Referenz des Datenbankschemas (Live-Änderungen als Migration über den Supabase-Connector, dann hier nachziehen)
- `.github/workflows/pages.yml` – Deploy auf GitHub Pages bei Push auf `main`; stempelt `__BUILD__` in index.html und schreibt `version.txt`
- `.github/workflows/keepalive.yml` – täglicher Ping, damit das Supabase-Gratisprojekt nicht pausiert

Live: https://wolfgangmatzner.github.io/einsatzerfassung/ · Supabase-Projekt `zukookhfrgmffottgrng` (eu-west-1)

## Datenmodell
Ein Einsatz = eine Zeile in `einsaetze` mit JSON-Dokument `data`. Wichtige Felder: `art, einsatz, ort, gemeinde, ueberoertlich, datum, ausfahrt, rueckkehr, rueckkehrDatum, fz[], m{nr:true}, r{nr:true}, el, zuteilung{nr:fz}, fzRollen{fz:{ma,gk}}, as{nr:true} (Atemschutzträger), ffs{name:{aktiv,fz,mann,extra}}, kraefte{rettung{NAH,NEF,RTW,Arzt,FR},polizei,stellen{},sonst}, atemschutz{}, schaden{}, material{}, wetter[], temp, unfallfz{id:{…,fotos{}}}, personen{id:{…,fotos{}}}, fotos{id:{asset,text}}, lage, massnahmen, uebergabe, brandwache, kostenpflichtig, bemerkung, status`.
Schreiben immer als Patch über RPC `einsatz_patch` (tiefes Merge, `null` löscht einen Schlüssel).

## Zentrale Mechanismen in index.html
- `api(a, body, opts)` – einzige Stelle mit Supabase-Aufrufen
- `schreibe(patch)` / `schreibeFuer(id, patch)` → `warteschlange` (localStorage `ffa-queue`) → `qAbarbeiten()` mit Wiederholung; Jobs `{typ:"neu"|"patch", id, …}`
- Offline: `cache` (localStorage `ffa-cache`: Liste, Mitglieder, Rolle), `mitQueue()` legt offene Änderungen über den Serverstand, neue Einsätze bekommen die UUID am Gerät
- `pollen()` + Realtime-Kanal; `fuelleFormular(e)` rendert alles aus dem Dokument
- Sektionen: `sektion(ziel, offen, merken)`, `ALLE_SEKTIONEN`, `zusammenfassung()`, `standardOffen()`; Klappzustand pro Einsatz in localStorage `ffa-klapp-<id>`
- Auto-Update: `BUILD`, `updatePruefen()`, `updateAnwenden()`
- Rollen: `rolle` = "user" | "admin" (aus JWT app_metadata.rolle)

Einsatzarten: Brand, Technisch, Schadstoff, Brandsicherheitswache (Kurz: BSW), Fehlalarm, Übung (früher „Sonstiges“).

## Regeln
- Keine Klarnamen der Mitglieder ins Repo (öffentlich!). Mitglieder liegen nur in der Datenbank.
- Keine Passwörter/Service-Keys ins Repo. Der Publishable Key in index.html ist öffentlich und okay.
- Supabase ist aus der Claude-Sandbox nicht erreichbar: Logik lokal mit gemocktem `api()` (Playwright, file://) testen, echte Tests macht der Nutzer am Gerät.
- Nach jedem Push prüfen, ob der Pages-Workflow erfolgreich war.
- Zielgeräte: Samsung-Android-Tablets (Chrome) und iPhone (Safari) – große Tippflächen, kein seitliches Scrollen.

## Offene Ideen
Foto-Warteschlange für Offline, Export/Backup-Knopf im Admin-Bereich, eigene Domain einsatz.feuerwehr-auersthal.at, Alarm-Taste, Vollständigkeitsprüfung beim Abschließen, automatisches Löschen von Ausweisfotos, Wappen im PDF.
