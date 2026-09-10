-- =====================================================================
-- HKN Portal — Complete Schema
-- Generated: July 2026, from live introspection of the production
-- Supabase project (dovmjcanfmswxofazvgc), not from memory.
-- Updated: August 2026 — get_public_data() session ordering fix applied
-- (see README "Known Fixes" for why the original ORDER BY was buggy).
-- Updated: August 2026 — added student-photos Storage bucket, its
-- access policies, and the students.photo_path column (originally
-- foundation only; display + individual per-student upload UI added
-- in a later update the same month — see README "Student Photos").
-- Updated: August 2026 — added teacher_presence table, teachers.
-- last_login column, and update_own_last_login() function. See
-- Section 4C below for an important PostgREST schema cache gotcha
-- hit while building this.
-- Updated: August 2026 — added admins.last_login and get_admin_activity()
-- so admin can see other admins' activity too, without adding any
-- direct SELECT access to the admins table itself.
-- Updated: August 2026 — fixed student_photos_select policy (was
-- is_portal_user() only, excluding admins — see Section 4B below).
-- Updated: August 2026 — rewritten to be fully idempotent (safe to
-- run repeatedly against an EXISTING database, not just a fresh one).
-- Every create table/policy/seed-insert below can now be re-run
-- without erroring or duplicating data — this is the ONE canonical
-- file for both scenarios: standing up a brand-new project, and
-- promoting accumulated changes to an existing one (e.g. production)
-- that already has some but not all of them. No separate "promote to
-- production" script needed anymore.
-- Updated: August 2026 — added explicit ALTER TABLE ADD COLUMN IF NOT
-- EXISTS statements (Section 1B) for admins.last_login, students.
-- photo_path, and teachers.last_login — CREATE TABLE IF NOT EXISTS
-- alone does NOT backfill columns onto a table that already exists,
-- which silently broke the production promotion. See Section 1B and
-- README "Known Fixes" for the full story.
-- Updated: August 2026 — enabled the domain-based Viewer role. Any
-- @hindikineev.org email with no teachers/admins row now gets
-- automatic read-only access via a broadened is_portal_user() and a
-- new synthesized-role branch in get_teacher_by_email(). The one write
-- policy that shared is_portal_user() (students_teacher_update) was
-- changed to a narrower, teachers-table-specific check so this stays
-- read-only at the database layer, not just in the UI.
-- Updated: September 2026 — added settings.interest_confirmation_message
-- and included it in get_public_data(), so admin can customize the
-- message parents see after submitting an interest form (previously
-- hardcoded). See README "Known Fixes" for the app-side bug this
-- surfaced: the confirmation screen initially read from the wrong
-- client-side source (DB.getSettings(), only populated for logged-in
-- staff) instead of the public RPC response, so the custom message
-- never showed for anonymous parents until both were fixed together.
--
-- Run this top-to-bottom on ANY Supabase project — fresh or existing —
-- to bring it fully up to date with everything below: tables,
-- constraints, RLS, policies, functions, grants, and the minimum seed
-- data needed to log in and use the portal before restoring a JSON
-- backup.
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

create table if not exists admins (
  email       text primary key,
  first_name  text not null,
  last_name   text not null,
  phone       text default '',
  last_login  timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists teachers (
  id          uuid primary key default gen_random_uuid(),
  first_name  text,
  last_name   text,
  email       text not null unique,
  phone       text,
  role        text not null default 'teacher',
  last_login  timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists students (
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

create table if not exists sessions (
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

create table if not exists templates (
  id          text primary key,
  name        text,
  subject     text,
  body        text,
  created_by  text,
  created_at  timestamptz not null default now()
);

create table if not exists settings (
  id                       integer primary key default 1,
  fee_tracker_session      text,
  motd                     text,
  motd_date                text,
  intake_enabled           boolean default false,
  staff_enabled            boolean default false,
  active_student_message   text,
  interest_confirmation_message text,
  inactivity_minutes       integer default 45
);

create table if not exists lookup_config (
  id          uuid primary key default gen_random_uuid(),
  type        text not null,
  value       text not null,
  sort_order  integer default 0,
  book_level  text
);

create table if not exists scoring_guide (
  level       text primary key,
  content     text default '',
  updated_at  timestamptz not null default now()
);

create table if not exists book_inventory (
  id              uuid primary key default gen_random_uuid(),
  session         text not null,
  book_level      text not null,
  book_type       text not null,
  starting_stock  integer not null default 0,
  updated_at      timestamptz not null default now(),
  unique (session, book_level, book_type)
);

create table if not exists book_replacements (
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

create table if not exists book_teacher_copies (
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
-- SECTION 1B — COLUMN PATCHES
-- IMPORTANT: CREATE TABLE IF NOT EXISTS only checks whether the TABLE
-- already exists — if it does, the entire statement is skipped,
-- including any columns defined inside it. It does NOT diff the
-- column list and backfill anything missing. So for any column added
-- to a table that already existed BEFORE the column was introduced
-- (as opposed to being part of the table from its very first
-- creation), an explicit ALTER TABLE ADD COLUMN IF NOT EXISTS is
-- required here too — redundant with the column already being listed
-- in CREATE TABLE above for a brand-new database, but essential for
-- patching an existing one that predates it. Found the hard way in
-- August 2026: running the newly-idempotent schema.sql against
-- production silently failed to add these three columns, since
-- admins/students/teachers already existed there — see README "Known
-- Fixes" for the full story.
-- =====================================================================

alter table admins   add column if not exists last_login timestamptz;
alter table students add column if not exists photo_path text;
alter table teachers add column if not exists last_login timestamptz;
alter table settings add column if not exists interest_confirmation_message text;


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

-- Broadened August 2026 — any @hindikineev.org email now passes this
-- check, not just people with a teachers-table row. This is what
-- powers the domain-based Viewer role: anyone with a school email
-- automatically gets read access, no per-person setup needed. This
-- is intentionally broad for READS only — see students_teacher_update
-- below for why the one write policy that used to share this function
-- was changed to a narrower, teachers-table-specific check instead.
create or replace function is_portal_user()
returns boolean
language sql
stable security definer
as $function$
  select exists (
    select 1 from teachers
    where lower(email) = lower(auth.jwt() ->> 'email')
  )
  or lower(auth.jwt() ->> 'email') like '%@hindikineev.org';
$function$;

-- Narrow SECURITY DEFINER function — only ever touches last_login for
-- the calling user's own row. Deliberately not a general "update your
-- own row" RLS policy, which would also let a teacher modify role,
-- email, etc. on their own row. Updated August 2026 to also try
-- admins — an email only ever matches one of the two tables, so the
-- other UPDATE silently affects 0 rows.
create or replace function update_own_last_login()
returns void
language plpgsql
security definer
as $function$
begin
  update teachers
  set last_login = now()
  where lower(email) = lower(auth.jwt() ->> 'email');

  update admins
  set last_login = now()
  where lower(email) = lower(auth.jwt() ->> 'email');
end;
$function$;

-- Narrow, admin-only function to read admin activity. Deliberately
-- NOT a SELECT policy on admins itself — that table stays completely
-- unreachable by any client-side query, by design (see README "Admin
-- Safety Net"). Explicitly gates on is_admin() before returning
-- anything, and only exposes email/name/last_login — not the whole
-- table (e.g. not phone).
create or replace function get_admin_activity()
returns table(email text, first_name text, last_name text, last_login timestamptz)
language plpgsql
stable security definer
as $function$
begin
  if not is_admin() then
    raise exception 'Not authorized';
  end if;
  return query
    select a.email, a.first_name, a.last_name, a.last_login
    from admins a;
end;
$function$;

-- Updated August 2026 — added a third branch that synthesizes a
-- 'viewer' role for any @hindikineev.org email not already an admin
-- or teacher. Powers the domain-based Viewer role — see is_portal_user()
-- above for the matching read-access change this depends on.
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
    union all
    select
      initcap(split_part(lookup_email, '@', 1)) as first_name,
      '' as last_name,
      'viewer'::text as role,
      3 as priority
    where lower(lookup_email) like '%@hindikineev.org'
      and not exists (select 1 from admins where lower(email) = lower(lookup_email))
      and not exists (select 1 from teachers where lower(email) = lower(lookup_email))
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
    'interestConfirmationMessage', s.interest_confirmation_message,
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
drop policy if exists "teachers_select_own_or_admin" on teachers;
create policy "teachers_select_own_or_admin"
  on teachers for select
  using (is_admin() OR is_portal_user() OR (lower(auth.jwt() ->> 'email') = lower(email)));

drop policy if exists "teachers_admin_write" on teachers;
create policy "teachers_admin_write"
  on teachers for all
  using (is_admin())
  with check (is_admin());

-- students
drop policy if exists "students_select_admin" on students;
create policy "students_select_admin"
  on students for select
  using (is_admin());

drop policy if exists "students_select_teacher" on students;
create policy "students_select_teacher"
  on students for select
  using (is_portal_user());

-- Deliberately does NOT use is_portal_user() (unlike other policies on
-- this page) — that function was broadened in August 2026 to grant any
-- @hindikineev.org email read access for the Viewer role, and this is
-- the one WRITE policy that used to share it. Changed to check
-- teachers-table membership directly, so a domain-based Viewer (who
-- has no row in teachers) can read but never write student records,
-- regardless of how broad read access becomes.
drop policy if exists "students_teacher_update" on students;
create policy "students_teacher_update"
  on students for update
  using (exists (select 1 from teachers where lower(email) = lower(auth.jwt() ->> 'email')))
  with check (exists (select 1 from teachers where lower(email) = lower(auth.jwt() ->> 'email')));

drop policy if exists "students_admin_write" on students;
create policy "students_admin_write"
  on students for all
  using (is_admin())
  with check (is_admin());

-- sessions
drop policy if exists "sessions_select_authenticated" on sessions;
create policy "sessions_select_authenticated"
  on sessions for select
  using (is_portal_user());

drop policy if exists "sessions_admin_write" on sessions;
create policy "sessions_admin_write"
  on sessions for all
  using (is_admin())
  with check (is_admin());

-- templates
drop policy if exists "templates_select_authenticated" on templates;
create policy "templates_select_authenticated"
  on templates for select
  using (is_portal_user());

drop policy if exists "templates_admin_write" on templates;
create policy "templates_admin_write"
  on templates for all
  using (is_admin())
  with check (is_admin());

-- settings
drop policy if exists "settings_select_authenticated" on settings;
create policy "settings_select_authenticated"
  on settings for select
  using (is_portal_user());

drop policy if exists "settings_admin_write" on settings;
create policy "settings_admin_write"
  on settings for all
  using (is_admin())
  with check (is_admin());

-- lookup_config
drop policy if exists "lookup_config_select_authenticated" on lookup_config;
create policy "lookup_config_select_authenticated"
  on lookup_config for select
  using (is_portal_user());

drop policy if exists "lookup_config_admin_write" on lookup_config;
create policy "lookup_config_admin_write"
  on lookup_config for all
  using (is_admin())
  with check (is_admin());

-- scoring_guide
drop policy if exists "scoring_guide_select_authenticated" on scoring_guide;
create policy "scoring_guide_select_authenticated"
  on scoring_guide for select
  using (is_portal_user());

drop policy if exists "scoring_guide_admin_write" on scoring_guide;
create policy "scoring_guide_admin_write"
  on scoring_guide for all
  using (is_admin())
  with check (is_admin());

-- book_inventory
drop policy if exists "book_inventory_read" on book_inventory;
create policy "book_inventory_read"
  on book_inventory for select
  using (is_portal_user());

drop policy if exists "book_inventory_admin_write" on book_inventory;
create policy "book_inventory_admin_write"
  on book_inventory for all
  using (is_admin())
  with check (is_admin());

-- book_replacements
drop policy if exists "book_replacements_read" on book_replacements;
create policy "book_replacements_read"
  on book_replacements for select
  using (is_portal_user());

drop policy if exists "book_replacements_admin_write" on book_replacements;
create policy "book_replacements_admin_write"
  on book_replacements for all
  using (is_admin())
  with check (is_admin());

-- book_teacher_copies
drop policy if exists "book_teacher_copies_read" on book_teacher_copies;
create policy "book_teacher_copies_read"
  on book_teacher_copies for select
  using (is_portal_user());

drop policy if exists "book_teacher_copies_admin_write" on book_teacher_copies;
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
--
-- Fixed August 2026: student_photos_select originally used
-- is_portal_user() only, which checks the teachers table specifically.
-- Admins (rajiv@, portal@) live in the separate admins table and have
-- no row in teachers, so uploads failed for them even though they
-- correctly passed is_admin() on the INSERT policy — an upload
-- requires a working SELECT policy too, same lesson as the
-- teacher_presence issue in Section 4C below. Fixed by checking
-- is_admin() OR is_portal_user(), same pattern already used
-- correctly elsewhere (e.g. the teachers table's own SELECT policy).
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('student-photos', 'student-photos', false)
on conflict (id) do nothing;

drop policy if exists "student_photos_select" on storage.objects;
create policy "student_photos_select"
on storage.objects for select
using (
  bucket_id = 'student-photos'
  and (is_admin() or is_portal_user())
);

drop policy if exists "student_photos_insert" on storage.objects;
create policy "student_photos_insert"
on storage.objects for insert
with check (
  bucket_id = 'student-photos'
  and is_admin()
);

drop policy if exists "student_photos_update" on storage.objects;
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

drop policy if exists "student_photos_delete" on storage.objects;
create policy "student_photos_delete"
on storage.objects for delete
using (
  bucket_id = 'student-photos'
  and is_admin()
);


-- =====================================================================
-- SECTION 4C — TEACHER PRESENCE
-- Added August 2026. Lightweight "last seen" heartbeat table — a
-- client-side timer upserts a row for the logged-in user every 60s
-- while a tab is open. Admin can see everyone's; each user can only
-- write their own row. Combined with teachers.last_login (added to
-- the teachers table above), this gives admin a rough "who's active
-- now / when did they last sign in" view without needing a genuine
-- realtime presence system.
--
-- IMPORTANT — a real gotcha hit while building this: PostgREST caches
-- table/policy structure separately from the database itself. Tables
-- and policies created directly via SQL Editor are sometimes not
-- picked up immediately, causing confusing 401/42501 errors on
-- otherwise-correct policies. If this ever recurs after adding new
-- tables/policies via SQL, run:
--   NOTIFY pgrst, 'reload schema';
-- before spending time re-checking policy correctness.
--
-- Also worth knowing: an upsert (INSERT ... ON CONFLICT DO UPDATE)
-- requires a SELECT policy in addition to INSERT/UPDATE — both to
-- check for conflicts, and because PostgREST returns the written row
-- by default. A user needs to be able to SELECT their own row for
-- their own upsert to succeed, not just INSERT/UPDATE it.
-- =====================================================================

create table if not exists teacher_presence (
  email      text primary key,
  last_seen  timestamptz not null default now()
);

alter table teacher_presence enable row level security;

drop policy if exists "teacher_presence_select_admin" on teacher_presence;
create policy "teacher_presence_select_admin"
  on teacher_presence for select
using (is_admin());

drop policy if exists "teacher_presence_select_own" on teacher_presence;
create policy "teacher_presence_select_own"
  on teacher_presence for select
using (lower(email) = lower(auth.jwt() ->> 'email'));

drop policy if exists "teacher_presence_insert_own" on teacher_presence;
create policy "teacher_presence_insert_own"
  on teacher_presence for insert
with check (lower(email) = lower(auth.jwt() ->> 'email'));

drop policy if exists "teacher_presence_update_own" on teacher_presence;
create policy "teacher_presence_update_own"
  on teacher_presence for update
using (lower(email) = lower(auth.jwt() ->> 'email'))
with check (lower(email) = lower(auth.jwt() ->> 'email'));

grant select, insert, update on teacher_presence to authenticated;


-- =====================================================================
-- SECTION 5 — SEED DATA
-- Minimum data needed to log in and use the portal before restoring a
-- real JSON backup. students/sessions/teachers/templates/lookup_config
-- are intentionally left empty — that's what JSON restore is for.
-- =====================================================================

-- Admins — without this, nobody can log in at all
insert into admins (email, first_name, last_name) values
  ('rajiv@hindikineev.org',  'Rajiv', 'Mathur'),
  ('portal@hindikineev.org', 'HKN',   'Portal')
on conflict (email) do nothing;

-- Settings — single row must exist before first login
insert into settings (id, intake_enabled, staff_enabled, inactivity_minutes)
values (1, true, true, 45)
on conflict (id) do nothing;

-- Scoring guide — 9 empty rows, one per class level
insert into scoring_guide (level, content) values
  ('Beg-1', ''), ('Beg-2', ''), ('Beg-3', ''),
  ('Int-1', ''), ('Int-2', ''), ('Int-3', ''), ('Int-4', ''),
  ('Adv-1', ''), ('Adv-2', '')
on conflict (level) do nothing;

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
  ('Fall-2026', 'Book 5', 'Exercise Book', 0)
on conflict (session, book_level, book_type) do nothing;


-- =====================================================================
-- VERIFY — run these after the script completes
-- =====================================================================
-- select count(*) from admins;         -- expect 2
-- select count(*) from settings;       -- expect 1
-- select count(*) from scoring_guide;  -- expect 9
-- select count(*) from book_inventory; -- expect 10
-- select table_name from information_schema.tables where table_schema='public' order by table_name; -- expect 11 tables
-- select routine_name from information_schema.routines where routine_schema='public' order by routine_name; -- expect 8 functions
