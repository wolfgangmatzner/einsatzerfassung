# Einsatzerfassung FF Auersthal

Tablet-App zur Erfassung von Einsätzen (Mannschaft, Fahrzeuge, weitere Kräfte, Fotos, PDF-Bericht).

- Frontend: `index.html` (eine Datei, kein Build) – gehostet über GitHub Pages
- Backend: Supabase (Postgres, Auth, Storage, Realtime), Projekt `Einsatztablets`
- Logins: `tablet@…` (alle Tablets) und `admin@…` (Mitglieder pflegen, Einsätze löschen)

`keepalive.yml` pingt das Supabase-Projekt täglich an, damit es im Gratis-Tarif nicht pausiert wird.
