-- Einsatzerfassung FF Auersthal – Datenbankschema (Stand der Migrationen bis 2026-11-10)
-- Referenz/Neuaufbau. Änderungen am Live-Projekt immer als Migration einspielen und hier nachziehen.
-- Mitgliederdaten stehen bewusst NICHT im Repo (nur in der Datenbank).

create or replace function public.ist_admin() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'rolle') = 'admin', false);
$$;

create table public.einsaetze (
  id uuid primary key default gen_random_uuid(),   -- wird vom Tablet erzeugt (Offline-Anlage)
  data jsonb not null default '{}'::jsonb,           -- gesamter Einsatz als JSON-Dokument
  status text generated always as (coalesce(data->>'status','aktiv')) stored,
  datum text generated always as (coalesce(data->>'datum','')) stored,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index einsaetze_status_idx on public.einsaetze (status);
create index einsaetze_datum_idx on public.einsaetze (datum desc);

create table public.mitglieder (
  nr integer primary key,
  name text not null,
  gruppe char(1) not null default 'm' check (gruppe in ('m','r'))   -- m = Mannschaft, r = Reserve
);

alter table public.einsaetze enable row level security;
alter table public.mitglieder enable row level security;

create policy "einsaetze lesen" on public.einsaetze for select to authenticated using (true);
create policy "einsaetze anlegen" on public.einsaetze for insert to authenticated with check (true);
create policy "einsaetze aendern" on public.einsaetze for update to authenticated using (true) with check (true);
create policy "einsaetze loeschen: admin oder abgeschlossen" on public.einsaetze
  for delete to authenticated using (public.ist_admin() or status = 'abgeschlossen');

create policy "mitglieder lesen" on public.mitglieder for select to authenticated using (true);
create policy "mitglieder admin insert" on public.mitglieder for insert to authenticated with check (public.ist_admin());
create policy "mitglieder admin update" on public.mitglieder for update to authenticated using (public.ist_admin()) with check (public.ist_admin());
create policy "mitglieder admin delete" on public.mitglieder for delete to authenticated using (public.ist_admin());

grant select, insert, update, delete on public.einsaetze to authenticated;
grant select, insert, update, delete on public.mitglieder to authenticated;
revoke all on public.einsaetze from anon;
revoke all on public.mitglieder from anon;

-- Tiefes JSON-Merge: Objekte rekursiv, null löscht den Schlüssel, Arrays/Skalare ersetzen
create or replace function public.jsonb_deep_merge(a jsonb, b jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare k text; v jsonb; result jsonb;
begin
  if a is null or jsonb_typeof(a) <> 'object' then a := '{}'::jsonb; end if;
  result := a;
  for k, v in select * from jsonb_each(b) loop
    if jsonb_typeof(v) = 'null' then result := result - k;
    elsif jsonb_typeof(v) = 'object' then result := jsonb_set(result, array[k], public.jsonb_deep_merge(result -> k, v), true);
    else result := jsonb_set(result, array[k], v, true);
    end if;
  end loop;
  return result;
end $$;

create or replace function public.einsatz_patch(p_id uuid, p_patch jsonb) returns integer
language plpgsql security invoker set search_path = '' as $$
declare v integer;
begin
  update public.einsaetze
     set data = public.jsonb_deep_merge(data, p_patch), version = version + 1, updated_at = now()
   where id = p_id returning version into v;
  if v is null then raise exception 'Einsatz nicht gefunden'; end if;
  return v;
end $$;
revoke execute on function public.einsatz_patch(uuid, jsonb) from anon, public;
grant execute on function public.einsatz_patch(uuid, jsonb) to authenticated;

create or replace function public.mitglieder_setzen(p_liste jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if not public.ist_admin() then raise exception 'Nur Admin'; end if;
  delete from public.mitglieder;
  insert into public.mitglieder (nr, name, gruppe)
  select (e->>'nr')::int, left(trim(e->>'name'),100), case when e->>'gruppe'='r' then 'r' else 'm' end
    from jsonb_array_elements(p_liste) e
   where (e->>'nr')::int > 0 and trim(coalesce(e->>'name','')) <> '';
end $$;
revoke execute on function public.mitglieder_setzen(jsonb) from anon, public;
grant execute on function public.mitglieder_setzen(jsonb) to authenticated;

-- Realtime
alter publication supabase_realtime add table public.einsaetze;
alter table public.einsaetze replica identity full;

-- Fotos: privater Bucket, Pfad <einsatzId>/<datei>.jpg, Auslieferung über signierte URLs
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 8388608, array['image/jpeg','image/png','image/webp']);
create policy "fotos lesen" on storage.objects for select to authenticated using (bucket_id = 'fotos');
create policy "fotos hochladen" on storage.objects for insert to authenticated with check (bucket_id = 'fotos');
create policy "fotos loeschen" on storage.objects for delete to authenticated using (bucket_id = 'fotos');

-- Auth (im Dashboard angelegt): tablet@einsatz.feuerwehr-auersthal.at (normal),
-- admin@einsatz.feuerwehr-auersthal.at mit raw_app_meta_data.rolle = 'admin'. Self-Signup deaktiviert.
