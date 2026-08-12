-- =====================================================================
-- HKN Portal — Complete Schema
-- Generated: July 2026, from live introspection of the production
-- Supabase project (dovmjcanfmswxofazvgc), not from memory.
-- Updated: August 2026 — get_public_data() session ordering fix applied
-- (see README "Known Fixes" for why the original ORDER BY was buggy).
-- Updated: August 2026 — added student-photos Storage bucket, its
-- access policies, and the students.photo_path column (foundation
-- only — upload/display UI not yet built as of this update).
--
-- Run this top-to-bottom on a FRESH Supabase project to recreate the
-- entire structure: tables, constraints, RLS, policies, functions,
-- grants, and the minimum seed data needed to log in and use the
-- portal before restoring a JSON backup.
--
-- After running this file:
--   1. Register the dev project's URL/key in a dev copy of index.html
--   2. Add the dev domain to this project's Auth > URL Configuration
--      — BOTH the "Site URL" field AND the "Redirect URLs" list (these
--      are separate settings; see README for why both matter)
--   3. Add the dev domain to Google Cloud Console authorized origins
--   4. Log in as rajiv@ or portal@ (seeded below) and use Backup &
--      Restore to load a real JSON snapshot for students/sessions/
--      teachers/templates/lookup_config
-- =====================================================================


-- =====================================================================
-- SECTION 1 — TABLES
-- =====================================================================

create table admins (
  email       text primary key,
  first_name  text not null,
  last_name   text not null,
  phone       text default '',
  created_at  timestamptz not null default now()
);

create table teachers (
  id          uuid primary key default gen_random_uuid(),
  first_name  text,
  last_name   text,
  email       text not null unique,
  phone       text,
  role        text not null default 'teacher',
  created_at  timestamptz not null default now()
);

create table students (
  id                      text primary key,
  student_id              text unique,
  status                  text not null,
  first_name              text,
  last_name               text,
  parent_first_name       text,
  parent_last_name        text,
  parent_email            text,
  phone                   text,
  dob                     date,
  address                 text,
  grade                   text,
  alt_contact_first_name  text,
  alt_contact_last_name   text,
  alt_contact_email       text,
  alt_contact_phone       text,
  speaking_score          integer default 0,
  reading_score           integer default 0,
  writing_score           integer default 0,
  intake_assessed         boolean default false,
  intake_assessed_date    timestamptz,
  notes                   text,
  "timestamp"             timestamptz default now(),
  session_data            jsonb not null default '[]'::jsonb,
  status_history          jsonb not null default '[]'::jsonb,
  last_parent_access      timestamptz,
  photo_path              text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create table sessions (
  id               text primary key,
  term             text,
  year             integer,
  fees             numeric default 0,
  enrollment_open  boolean default false,
  class_dates      date[] default '{}'::date[],
  class_notes      jsonb default '{}'::jsonb,
  refunds          jsonb default '[]'::jsonb,
  created_at       timestamptz not null default now()
);

create table templates (
  id          text primary key,
  name        text,
  subject     text,
  body        text,
  created_by  text,
  created_at  timestamptz not null default now()
);

create table settings (
  id                       integer primary key default 1,
  fee_tracker_session      text,
  motd                     text,
  motd_date                text,
  intake_enabled           boolean default false,
  staff_enabled            boolean default false,
  active_student_message   text,
  inactivity_minutes       integer default 45
);

create table lookup_config (
  id          uuid primary key default gen_random_uuid(),
  type        text not null,
  value       text not null,
  sort_order  integer default 0,
  book_level  text
);

create table scoring_guide (
  level       text primary key,
  content     text default '',
  updated_at  timestamptz not null default now()
);

create table book_inventory (
  id              uuid primary key default gen_random_uuid(),
  session         text not null,
  book_level      text not null,
  book_type       text not null,
  starting_stock  integer not null default 0,
  updated_at      timestamptz not null default now(),
  unique (session, book_level, book_type)
);

create table book_replacements (
  id          uuid primary key default gen_random_uuid(),
  date        date not null,
  session     text not null,
  student_id  text not null,
  first_name  text not null,
  last_name   text not null,
  book_level  text not null,
  book_type   text not null,
  reason      text not null,
  notes       text not null default '',
  logged_by   text not null,
  created_at  timestamptz not null default now()
);

create table book_teacher_copies (
  id            uuid primary key default gen_random_uuid(),
  date          date not null,
  session       text not null,
  teacher_name  text not null,
  book_level    text not null,
  book_type     text not null,
  reason        text not null,
  notes         text not null default '',
  returned      boolean not null default false,
  logged_by     text not null,
  created_at    timestamptz not null default now()
);


-- =====================================================================
-- SECTION 2 — SECURITY DEFINER FUNCTIONS
-- (created before RLS policies since policies reference them)
-- =====================================================================

create or replace function is_admin()
returns boolean
language sql
stable security definer
as $function$
  select exists (
    select 1 from admins
    where lower(email) = lower(auth.jwt() ->> 'email')
  )
  or exists (
    select 1 from teachers
    where lower(email) = lower(auth.jwt() ->> 'email')
    and role = 'admin'
  );
$function$;

create or replace function is_portal_user()
returns boolean
language sql
stable security definer
as $function$
  select exists (
    select 1 from teachers
    where lower(email) = lower(auth.jwt() ->> 'email')
  );
$function$;

create or replace function get_teacher_by_email(lookup_email text)
returns table(first_name text, last_name text, role text)
language sql
stable security definer
as $function$
  select first_name, last_name, role from (
    select a.first_name, a.last_name, 'admin'::text as role, 1 as priority
    from admins a
    where lower(a.email) = lower(lookup_email)
    union all
    select t.first_name, t.last_name, t.role, 2 as priority
    from teachers t
    where lower(t.email) = lower(lookup_email)
  ) combined
  order by priority
  limit 1;
$function$;

-- UPDATED August 2026: sessions are now ordered by each session's actual
-- earliest class date, not by (year, term-as-text). The old approach
-- broke whenever two sessions shared the same year value (e.g. Fall-2026
-- and Spring-2026 both have year=2026) — 'Fall' sorts alphabetically
-- before 'Spring', putting the chronologically LATER Fall session before
-- the EARLIER Spring session in the returned list. This caused the
-- parent portal to show stale (Spring) info instead of current (Fall)
-- info for students with data in both sessions. See README "Known Fixes".
create or replace function get_public_data()
returns json
language sql
stable security definer
as $function$
  select json_build_object(
    'intakeEnabled',        s.intake_enabled,
    'activeStudentMessage', s.active_student_message,
    'sessions', (
      select json_agg(
        json_build_object(
          'name',           sess.id,
          'term',           sess.term,
          'year',           sess.year,
          'fees',           sess.fees,
          'enrollmentOpen', sess.enrollment_open,
          'classDates',     sess.class_dates,
          'classNotes',     sess.class_notes
        )
        order by (select min(d) from unnest(sess.class_dates) d)
      )
      from sessions sess
    )
  )
  from settings s
  where s.id = 1;
$function$;

create or replace function lookup_student(
  p_parent_email text,
  p_first_name   text,
  p_dob          text
)
returns json
language sql
stable security definer
as $function$
  select row_to_json(s)
  from students s
  where lower(s.parent_email) = lower(p_parent_email)
    and lower(s.first_name)   = lower(p_first_name)
    and s.dob::text           = p_dob
  limit 1;
$function$;

create or replace function save_student_from_intake(student_json json)
returns json
language plpgsql
security definer
as $function$
declare
  s json := student_json;
begin
  insert into students (
    id, student_id, status,
    first_name, last_name,
    parent_first_name, parent_last_name, parent_email,
    phone, dob, address, grade,
    alt_contact_first_name, alt_contact_last_name,
    alt_contact_email, alt_contact_phone,
    speaking_score, reading_score, writing_score,
    intake_assessed, intake_assessed_date,
    notes, "timestamp",
    session_data, status_history,
    last_parent_access,
    updated_at
  ) values (
    s->>'id',
    nullif(s->>'studentId', ''),
    s->>'status',
    s->>'firstName',
    s->>'lastName',
    s->>'parentFirstName',
    s->>'parentLastName',
    s->>'parentEmail',
    s->>'phone',
    nullif(s->>'dob', '')::date,
    s->>'address',
    s->>'grade',
    s->>'altContactFirstName',
    s->>'altContactLastName',
    s->>'altContactEmail',
    s->>'altContactPhone',
    coalesce((s->>'speakingScore')::int, 0),
    coalesce((s->>'readingScore')::int, 0),
    coalesce((s->>'writingScore')::int, 0),
    coalesce((s->>'intakeAssessed')::boolean, false),
    nullif(s->>'intakeAssessedDate', '')::timestamptz,
    s->>'notes',
    nullif(s->>'timestamp', '')::timestamptz,
    coalesce((s->'sessionData')::jsonb, '[]'::jsonb),
    coalesce((s->'statusHistory')::jsonb, '[]'::jsonb),
    now(),
    now()
  )
  on conflict (id) do update set
    student_id             = nullif(excluded.student_id, ''),
    status                 = excluded.status,
    first_name             = excluded.first_name,
    last_name              = excluded.last_name,
    parent_first_name      = excluded.parent_first_name,
    parent_last_name       = excluded.parent_last_name,
    parent_email           = excluded.parent_email,
    phone                  = excluded.phone,
    dob                    = excluded.dob,
    address                = excluded.address,
    grade                  = excluded.grade,
    alt_contact_first_name = excluded.alt_contact_first_name,
    alt_contact_last_name  = excluded.alt_contact_last_name,
    alt_contact_email      = excluded.alt_contact_email,
    alt_contact_phone      = excluded.alt_contact_phone,
    notes                  = excluded.notes,
    session_data           = excluded.session_data,
    status_history          = excluded.status_history,
    last_parent_access      = now(),
    updated_at              = now();

  return json_build_object('saved', true, 'id', s->>'id');
end;
$function$;

create or replace function get_distributed_books(
  p_session      text,
  p_prev_session text
)
returns table (book_level text, distributed bigint)
language sql
stable security definer
as $function$
  select
    current_sd->>'bookLevel' as book_level,
    count(*) as distributed
  from students s,
    jsonb_array_elements(s.session_data) current_sd
  where s.status = 'Active'
    and current_sd->>'session' = p_session
    and current_sd->>'bookLevel' is not null
    and current_sd->>'bookLevel' != ''
    and not exists (
      select 1
      from jsonb_array_elements(s.session_data) prev_sd
      where prev_sd->>'session' = p_prev_session
        and prev_sd->>'bookLevel' = current_sd->>'bookLevel'
    )
  group by current_sd->>'bookLevel'
  order by current_sd->>'bookLevel';
$function$;

-- NOTE: rls_auto_enable() is an event-trigger-backing function seen in
-- production. Its actual CREATE EVENT TRIGGER registration could not be
-- introspected from the queries we ran (event triggers live in a
-- different system catalog) and may simply be a Supabase-platform
-- default already present on every new project. Included here for
-- completeness/reference only — not required for the app to function,
-- since every table below explicitly enables RLS on its own.
create or replace function rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;


-- =====================================================================
-- SECTION 3 — GRANTS (anonymous parent-portal access)
-- =====================================================================

revoke execute on function get_public_data() from public;
grant execute on function get_public_data() to anon;

revoke execute on function lookup_student(text, text, text) from public;
grant execute on function lookup_student(text, text, text) to anon;

revoke execute on function save_student_from_intake(json) from public;
grant execute on function save_student_from_intake(json) to anon;

grant execute on function get_distributed_books(text, text) to authenticated;

-- get_teacher_by_email(), is_admin(), is_portal_user() were never
-- explicitly restricted in production and remain at Postgres default
-- (executable by PUBLIC) — intentionally left as-is here to match.


-- =====================================================================
-- SECTION 4 — ROW LEVEL SECURITY
-- =====================================================================

alter table admins               enable row level security;
alter table teachers             enable row level security;
alter table students             enable row level security;
alter table sessions             enable row level security;
alter table templates            enable row level security;
alter table settings             enable row level security;
alter table lookup_config        enable row level security;
alter table scoring_guide        enable row level security;
alter table book_inventory       enable row level security;
alter table book_replacements    enable row level security;
alter table book_teacher_copies  enable row level security;

-- admins: intentionally ZERO policies for anon/authenticated.
-- Only SECURITY DEFINER functions (is_admin, get_teacher_by_email) can
-- read this table. This is what makes it un-reachable by any portal
-- feature, including JSON restore. Do not add policies here.

-- teachers
create policy "teachers_select_own_or_admin"
  on teachers for select
  using (is_admin() OR is_portal_user() OR (lower(auth.jwt() ->> 'email') = lower(email)));

create policy "teachers_admin_write"
  on teachers for all
  using (is_admin())
  with check (is_admin());

-- students
create policy "students_select_admin"
  on students for select
  using (is_admin());

create policy "students_select_teacher"
  on students for select
  using (is_portal_user());

create policy "students_teacher_update"
  on students for update
  using (is_portal_user())
  with check (is_portal_user());

create policy "students_admin_write"
  on students for all
  using (is_admin())
  with check (is_admin());

-- sessions
create policy "sessions_select_authenticated"
  on sessions for select
  using (is_portal_user());

create policy "sessions_admin_write"
  on sessions for all
  using (is_admin())
  with check (is_admin());

-- templates
create policy "templates_select_authenticated"
  on templates for select
  using (is_portal_user());

create policy "templates_admin_write"
  on templates for all
  using (is_admin())
  with check (is_admin());

-- settings
create policy "settings_select_authenticated"
  on settings for select
  using (is_portal_user());

create policy "settings_admin_write"
  on settings for all
  using (is_admin())
  with check (is_admin());

-- lookup_config
create policy "lookup_config_select_authenticated"
  on lookup_config for select
  using (is_portal_user());

create policy "lookup_config_admin_write"
  on lookup_config for all
  using (is_admin())
  with check (is_admin());

-- scoring_guide
create policy "scoring_guide_select_authenticated"
  on scoring_guide for select
  using (is_portal_user());

create policy "scoring_guide_admin_write"
  on scoring_guide for all
  using (is_admin())
  with check (is_admin());

-- book_inventory
create policy "book_inventory_read"
  on book_inventory for select
  using (is_portal_user());

create policy "book_inventory_admin_write"
  on book_inventory for all
  using (is_admin())
  with check (is_admin());

-- book_replacements
create policy "book_replacements_read"
  on book_replacements for select
  using (is_portal_user());

create policy "book_replacements_admin_write"
  on book_replacements for all
  using (is_admin())
  with check (is_admin());

-- book_teacher_copies
create policy "book_teacher_copies_read"
  on book_teacher_copies for select
  using (is_portal_user());

create policy "book_teacher_copies_admin_write"
  on book_teacher_copies for all
  using (is_admin())
  with check (is_admin());


-- =====================================================================
-- SECTION 4B — STORAGE (student photos)
-- Added August 2026. Private bucket — not publicly accessible via a
-- bare URL. Read access for any admin/teacher; upload/replace/delete
-- restricted to admin only. Reuses the same is_admin()/is_portal_user()
-- functions already used throughout this schema.
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('student-photos', 'student-photos', false)
on conflict (id) do nothing;

create policy "student_photos_select"
on storage.objects for select
using (
  bucket_id = 'student-photos'
  and is_portal_user()
);

create policy "student_photos_insert"
on storage.objects for insert
with check (
  bucket_id = 'student-photos'
  and is_admin()
);

create policy "student_photos_update"
on storage.objects for update
using (
  bucket_id = 'student-photos'
  and is_admin()
)
with check (
  bucket_id = 'student-photos'
  and is_admin()
);

create policy "student_photos_delete"
on storage.objects for delete
using (
  bucket_id = 'student-photos'
  and is_admin()
);


-- =====================================================================
-- SECTION 5 — SEED DATA
-- Minimum data needed to log in and use the portal before restoring a
-- real JSON backup. students/sessions/teachers/templates/lookup_config
-- are intentionally left empty — that's what JSON restore is for.
-- =====================================================================

-- Admins — without this, nobody can log in at all
insert into admins (email, first_name, last_name) values
  ('rajiv@hindikineev.org',  'Rajiv', 'Mathur'),
  ('portal@hindikineev.org', 'HKN',   'Portal');

-- Settings — single row must exist before first login
insert into settings (id, intake_enabled, staff_enabled, inactivity_minutes)
values (1, true, true, 45);

-- Scoring guide — 9 empty rows, one per class level
insert into scoring_guide (level, content) values
  ('Beg-1', ''), ('Beg-2', ''), ('Beg-3', ''),
  ('Int-1', ''), ('Int-2', ''), ('Int-3', ''), ('Int-4', ''),
  ('Adv-1', ''), ('Adv-2', '');

-- Book inventory — 10 rows, placeholder starting stock (0).
-- Update real starting stock via the portal's Book Inventory page once
-- logged in — these are operational numbers, not part of the schema.
insert into book_inventory (session, book_level, book_type, starting_stock) values
  ('Fall-2026', 'Book 1', 'Textbook',      0),
  ('Fall-2026', 'Book 1', 'Exercise Book', 0),
  ('Fall-2026', 'Book 2', 'Textbook',      0),
  ('Fall-2026', 'Book 2', 'Exercise Book', 0),
  ('Fall-2026', 'Book 3', 'Textbook',      0),
  ('Fall-2026', 'Book 3', 'Exercise Book', 0),
  ('Fall-2026', 'Book 4', 'Textbook',      0),
  ('Fall-2026', 'Book 4', 'Exercise Book', 0),
  ('Fall-2026', 'Book 5', 'Textbook',      0),
  ('Fall-2026', 'Book 5', 'Exercise Book', 0);


-- =====================================================================
-- VERIFY — run these after the script completes
-- =====================================================================
-- select count(*) from admins;         -- expect 2
-- select count(*) from settings;       -- expect 1
-- select count(*) from scoring_guide;  -- expect 9
-- select count(*) from book_inventory; -- expect 10
-- select table_name from information_schema.tables where table_schema='public' order by table_name; -- expect 11 tables
-- select routine_name from information_schema.routines where routine_schema='public' order by routine_name; -- expect 8 functions
