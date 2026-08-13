# HKN Portal — Project README
*Last updated: August 13, 2026*

---

## What This Project Is

A web-based student management portal for **Hindi Ki Neev (HKN)**, a Bay Area community Hindi school.
Built as a single HTML file (`index.html`) with a Supabase PostgreSQL backend and Google OAuth login.

**Status: cutover complete.** `portal.hindikineev.org` is now running the new
Supabase-based system in production. The old Drive/Apps Script backend has
been retired from active use.

**Notable features:**
- **Send Email** and the **Template Editor** both have a rich-text formatting
  toolbar (Bold/Italic/Underline/color/size) — compose messages get saved as
  real HTML, not plain text
- **School Attributes** is organized into 4 subtabs: Portal Settings,
  Teachers, Classes, and Edit Scoring Guide
- **Book Inventory** page tracks starting stock, replacements, and teacher
  copies, with distributed-book counts calculated live from student data
- **Parent portal** (anonymous access) lets parents look up their child's
  status, attendance, and scores without logging in
- **Classes** page groups students into cards by teacher + class time, with
  Teacher and Class Level filter dropdowns (matching the Student Directory's
  filter pattern). Each class card also has a **📝 Add Homework Note**
  button — see "Homework Notes" section below
- **FAQs** page (renamed from "Parent Guide") is linked prominently on the
  parent portal's Welcome screen, not just the detailed info page — teacher
  feedback was that nobody read "Parent Guide" but they will read "FAQs"

---

## Files in This Repo / Folder

| File | Purpose | How to edit |
|------|---------|-------------|
| `index.html` | The entire portal — staff portal, parent portal, all features | VS Code or any text editor. Deploy by uploading to GitHub (overwrites by matching filename — no deletion needed). |
| `HKN_FAQs.html` | Parent-facing FAQ page (renamed from `HKN_Parent_Guide.html` in August 2026 — see "Editing the FAQs" below) | VS Code — find the question/answer text you want to change, edit between the tags, save. |
| `schema.sql` | Complete, consolidated database schema — every table, function, RLS policy, and grant, built from live introspection of production. Used to stand up a fresh (e.g. dev/staging) Supabase project from scratch. | Reference/setup only — not something you "run" against an already-configured project. |

---

## Running Locally

```bash
cd D:\hkn-portal
npx serve . -l 8080
```

Then open `http://localhost:8080` in Chrome.

**Requirements:** Node.js installed on your machine.

**To stop:** press `Ctrl+C` in the Command Prompt window.

---

## Supabase (Database)

**Production Project URL:** `https://dovmjcanfmswxofazvgc.supabase.co`
**Production Dashboard:** `https://supabase.com/dashboard/project/dovmjcanfmswxofazvgc`
**Production Publishable key:** stored in `index.html` (safe to be public)

**Dev Project URL:** `https://fbujsdqjqeavfykgsttp.supabase.co`
**Dev Dashboard:** `https://supabase.com/dashboard/project/fbujsdqjqeavfykgsttp`
**Dev Publishable key:** stored in `index.html` (safe to be public)

**Secret/service role key:** never put this in `index.html` — only used for one-time admin tasks directly in Supabase

### Two separate projects, one shared `index.html`

`portal.hindikineev.org` (production) and `portal-new.hindikineev.org` (dev)
each have their **own, fully independent Supabase project** — genuinely
isolated data, not the shared setup used earlier in this project. `index.html`
picks the correct one automatically based on its own domain:

```javascript
const SUPABASE_CONFIG = (window.location.hostname === 'portal.hindikineev.org')
  ? { url: 'https://dovmjcanfmswxofazvgc.supabase.co', key: '...' }  // production
  : { url: 'https://fbujsdqjqeavfykgsttp.supabase.co', key: '...' }; // dev/portal-new
```

This means the **exact same file** can be uploaded to both repos unchanged —
no manual editing needed to deploy to one vs. the other. Production is the
narrow, explicit case; anything else (portal-new, localhost, anywhere else)
safely defaults to the dev project — so a misconfiguration can never
accidentally point somewhere at production.

**Setting up the dev project from scratch** (already done once, but useful
if it's ever needed again — e.g. after a true host migration): run
`schema.sql` top-to-bottom in a fresh Supabase project's SQL Editor, then
configure Auth (Site URL **and** Redirect URLs — see below) and the Google
provider (same Client ID/Secret as production, or a fresh Client ID if the
shared one ever behaves oddly for a new project — see "Known Fixes" if this
comes up again). Two Google Cloud Console pieces are also needed per new
Supabase project: the app domain as an **Authorized JavaScript origin**, and
that specific project's own callback URL
(`https://<project-ref>.supabase.co/auth/v1/callback`) as an **Authorized
redirect URI** — these aren't automatically shared even when the same
Client ID is reused across projects.

### Tables (12 total)

| Table | What it stores |
|-------|---------------|
| `students` | All student records — bio info, `session_data` (attendance, scores, teacher, class level, book level, and per-session `notes` — see "Homework Notes" below), `status_history`, `last_parent_access` |
| `sessions` | School sessions (Fall-2026, Spring-2026 etc.) with class dates, fees, enrollment status |
| `teachers` | Teacher/admin accounts, including `last_login` — see "Teacher & Admin Activity" below |
| `templates` | Email templates |
| `settings` | Portal settings (MOTD, intake/staff enabled, inactivity timer) — single row, `id = 1` |
| `lookup_config` | Class levels, book levels, class times, class names |
| `scoring_guide` | Scoring guide content per class level (9 rows: Beg-1 through Adv-2), editable by admin in-portal |
| `book_inventory` | Starting book stock per session/book level/type |
| `book_replacements` | Log of replacement books issued to students |
| `book_teacher_copies` | Log of books given to teachers |
| `admins` | Two protected admin accounts (`rajiv@`, `portal@`) — see "Admin Safety Net" below |
| `teacher_presence` | Lightweight "last seen" heartbeat, one row per user — see "Teacher & Admin Activity" below |

### SECURITY DEFINER Functions (10 total)
- `is_admin()` / `is_portal_user()` — core role-check functions used by every RLS policy
- `get_teacher_by_email(lookup_email)` — returns role for a logged-in user; checks `admins` first, then `teachers`
- `get_public_data()` — returns settings + sessions for the anonymous parent portal. **Sessions are ordered by each session's actual earliest class date** (not by year/term text — see "Known Fixes" below for why this matters)
- `lookup_student(email, first_name, dob)` — anonymous parent lookup
- `save_student_from_intake(student_json)` — anonymous parent enrollment/interest submission
- `get_distributed_books(session, prev_session)` — calculates new books needed for a session
- `update_own_last_login()` — sets `last_login` (on `teachers` or `admins`, whichever actually has a matching row) for the calling user's own row only (see "Teacher & Admin Activity" below)
- `get_admin_activity()` — the *only* way to read anything from `admins` client-side; explicitly gates on `is_admin()` and returns just email/name/last_login, not the whole table
- `rls_auto_enable()` — Supabase-platform event trigger support function (not actively required by the app)

### Supabase Daily Backups
Supabase automatically backs up the database daily. For self-managed backups, use the
portal's **Backup & Restore** page to download a JSON file.

---

## Admin Safety Net — the `admins` table

**Do not delete or modify this table casually.** It exists specifically so that
`rajiv@hindikineev.org` and `portal@hindikineev.org` can never be locked out
of the portal, no matter what happens to the `teachers` table.

**Why it exists:** restoring an old JSON backup (from before Supabase existed,
or any backup whose `teachers` list doesn't include admin rows) wipes every
teacher record in Supabase — including admins — since restore does a true
delete-then-insert on `teachers`, not a merge. Without this table, that would
mean nobody could log in to fix it.

**How it protects you:** `admins` has **no client-facing access at all** —
Row Level Security is enabled with zero policies for `anon` or `authenticated`,
so no code in the portal can ever read or write it directly. Three SQL
functions can see it: `get_teacher_by_email()`, `is_admin()`, and
`get_admin_activity()` (added August 2026, explicitly gates on `is_admin()`
before returning anything, and only exposes email/name/last_login — see
"Teacher & Admin Activity" below).

**To add a protected admin**, this must be done directly in Supabase SQL Editor:
```sql
insert into admins (email, first_name, last_name) values
  ('newemail@hindikineev.org', 'First', 'Last');
```

---

## Google OAuth

**Google Cloud Console:** `https://console.cloud.google.com`
**OAuth Client ID:** `403780981402-4d6k69prpesahb6911vqukrbiiji2ech.apps.googleusercontent.com`

### Authorized JavaScript Origins ✅ all registered
- `http://localhost:8080`
- `https://portal-new.hindikineev.org`
- `https://portal.hindikineev.org`

---

## Supabase Auth URL Configuration — two separate settings, easy to confuse

**Site URL** (Authentication → URL Configuration → top of page): the
*fallback* redirect destination used when nothing else matches. Currently
set to `https://portal.hindikineev.org`.

**Redirect URLs** (same page, separate list below Site URL): the actual
allow-list of destinations OAuth is permitted to send users to. Currently
contains:
- `http://localhost:8080`
- `https://portal-new.hindikineev.org`
- `https://portal.hindikineev.org`

**Why both matter:** these are genuinely separate settings. Having a domain
in Redirect URLs does *not* make it the Site URL, and vice versa. Production
login broke once (August 2026) because `portal.hindikineev.org` had only
ever been discussed as "added," but was actually never added to the Redirect
URLs list — login was silently working only because it happened to match
Site URL. If Site URL is ever changed for any reason, anything not
*explicitly* in Redirect URLs will break immediately. Always add new domains
to **both** settings, and verify by checking the actual list, not by memory.

### Adding a new domain (do both steps)
1. Google Cloud Console → APIs & Services → Credentials → the OAuth Client ID
   → add under both "Authorized JavaScript origins" and "Authorized redirect URIs"
2. Supabase Dashboard → Authentication → URL Configuration → add to
   **Redirect URLs** (click "Add URL" or the "+" control below the list)

---

## Deployment (GitHub Pages — no Git installed, use the web UI)

**Production repo:** `https://github.com/portal-sudo/HKN-Portal` → `portal.hindikineev.org`
**Dev/staging repo:** `https://github.com/portal-sudo/HKN-Portal-New` → `portal-new.hindikineev.org`

There is no Git installed on this machine — updates are done entirely through
the GitHub website, no command line needed.

### To deploy an update
1. Make changes to `index.html` locally (test at `localhost:8080` or on
   `portal-new` first)
2. Go to the target repo on GitHub
3. Click **Add file → Upload files** and drag the updated file in — uploading
   with the same filename **overwrites** the old version automatically. No
   need to delete anything first, and the `CNAME` file (which controls the
   custom domain) is untouched as long as you don't upload a file named `CNAME`
4. Commit — GitHub Pages rebuilds within 1-2 minutes (check progress under
   the repo's **Actions** tab)

### DNS (Squarespace)
- `portal` → CNAME → `portal-sudo.github.io`
- `portal-new` → CNAME → `portal-sudo.github.io`
- Both repos have their own `CNAME` file internally, which is what actually
  determines which domain each repo serves — this is separate from the
  Squarespace DNS records above, and is why file-swapping between the two
  repos never requires touching DNS at all.

### Troubleshooting a deployment that doesn't seem to show up

Two real incidents worth knowing about, both encountered in August 2026:

**1. GitHub's own build infrastructure can fail or get stuck**, independent
of anything in your commit. If a change looks correct on GitHub (open the
file directly in GitHub's web viewer and confirm your edit is actually
there) but still isn't showing live even after a hard refresh, incognito
window, and a cache-busting `?v=2` URL — check the repo's **Actions** tab.
A red X means the deployment itself failed (this happened once during a
genuine GitHub-wide outage — check `githubstatus.com` if it looks
widespread); a run stuck on "Queued" for many minutes is the same kind of
issue. The fix is usually just to wait, or to make a trivial new commit
(e.g. add/remove a blank line) to trigger a fresh deployment attempt.

**2. A page already open in a browser tab won't pick up new code just
because the deployment succeeded.** If a page's JavaScript looks unchanged
even after confirming (via GitHub's Actions tab and `[functionName].toString()`
in the console) that the new code is genuinely live, try navigating *away*
from that page and back (e.g. Dashboard → Classes) rather than just
refreshing — this forces the render function to actually run again with the
current code.

---

## Editing the FAQs

**File:** `HKN_FAQs.html` (renamed from `HKN_Parent_Guide.html` in August
2026), uploaded alongside `index.html` in the production repo. Linked from
two places in the parent portal: a prominent button on the Welcome screen
("❓ Have questions? Check our FAQs") and a smaller link on the detailed
student info page.

The file is organized in sections. Each question/answer looks like this:

```html
<div class="question">What is Hindi Ki Neev?</div>
<div class="answer">
  Hindi Ki Neev (HKN) is a community Hindi language school...
</div>
```

**To edit text:** open in VS Code, search for the text you want to change,
edit the words between the tags, save. Do not change anything inside `< >` brackets.

**To highlight a specific sentence** (e.g. the attendance policy's
unexcused-absence warning is shown in red), wrap it in
`<span style="color:#c0392b; font-weight:600;">...</span>`.

**If you ever rename this file again:** two places in `index.html` reference
it by filename (`href="./HKN_FAQs.html"`) — both the Welcome-page button and
the detailed-page link need updating, or the buttons will 404.

After editing, upload the updated file to the production repo (see Deployment above).

---

## Editing the Scoring Guide

The scoring guide is stored in Supabase (not a file). To edit:

1. Sign into the portal as admin
2. Go to **School Attributes** → **Edit Scoring Guide** tab
3. Select a class level from the dropdown
4. Edit the content using the formatting toolbar
5. Click **Save level**

Changes are immediate — no deployment needed.

---

## Homework Notes (Classes page)

Each class card on the **Classes** page has a **📝 Add Homework Note**
button, letting a teacher broadcast the same homework instructions to every
student in that specific class at once — instead of typing the same text
into each student's individual notes field one at a time.

**How it works:** the entered text gets formatted as `Homework <date>:
<text>` and appended as a new line to each enrolled student's own
per-session `notes` field — the same field parents already see under
"Notes from your teacher" in their portal. Each student gets an independent
copy from that point forward; it is a one-time broadcast, not a shared or
synced note.

**Permissions:** a teacher only sees this button on classes they actually
teach — it's not just hidden, the button doesn't render in the page at all
for another teacher's class card. Admins see it on every class card. This
reuses the exact same ownership check as the pre-existing class-level Notes
feature on the same page.

**Undo:** immediately after adding a homework note, that specific class
card shows "✓ Homework note added — Undo". Clicking it removes that exact
line from each student who received it (with a safety check — it only
removes the line if it's still each student's most recent note, so it won't
accidentally strip something added afterward). **This only covers the most
recent broadcast** — it's session-local (an in-memory JavaScript variable,
not persisted) and disappears if you navigate away from Classes or refresh
the page, even though the note itself remains correctly saved. There is no
way to undo an older broadcast or view a history of past ones — a mistake
noticed later has to be corrected manually, per student, in the Student
Detail Modal.

---

## Backup and Restore

### Manual backup (do this regularly and before any major changes)
1. Sign into portal as admin
2. Go to **Backup & Restore** in the left sidebar
3. Click **Download Backup**
4. Save the JSON file to a safe location (Google Drive recommended)

### Restore from backup
1. Sign into portal as admin
2. Go to **Backup & Restore**
3. Upload the JSON backup file
4. Click **Restore** and confirm

### What restore actually does — important to understand

Restore is a **true point-in-time snapshot**, not a merge. For `students`,
`sessions`, `teachers`, and `templates`, it deletes every existing row in
Supabase and replaces it with exactly what's in the JSON file.

**`settings` is the one exception** — it merges instead of replacing. Any
field present in the JSON overrides the current value, but any field the
JSON doesn't have keeps whatever is currently live in Supabase, rather than
reverting to a hardcoded default.

**Restoring an old JSON will remove teacher rows not in that file** — this
is expected and **safe**, since `rajiv@hindikineev.org` and
`portal@hindikineev.org` are protected separately in the `admins` table,
which restore can never touch.

**Not touched by restore, in either direction:** `scoring_guide`,
`book_inventory`, `book_replacements`, `book_teacher_copies`, `admins`. These
live in Supabase only, protected by daily snapshots, not by JSON backup/restore.

---

## Known Fixes (worth understanding, not just historical trivia)

### Parent portal showing the wrong session (fixed August 2026)
`get_public_data()` originally sorted sessions with `order by sess.year,
sess.term`. Since `term` is plain text, this only works correctly by
coincidence — two sessions sharing the same `year` value (e.g. Fall-2026
and Spring-2026, both `year = 2026`) get tie-broken alphabetically by term
name, and `'Fall'` sorts before `'Spring'` — putting the *earlier* Spring
session after the *later* Fall session in the list. The parent-facing
`getBestSession()` logic picks the *last* session a student has data for,
so this caused Active students to see Spring-2026 info instead of the
correct, current Fall-2026 info.

**Fixed by sorting on each session's actual earliest class date instead:**
```sql
order by (select min(d) from unnest(sess.class_dates) d)
```
This is robust regardless of how `year`/`term` happen to be labeled or
populated (two sessions, Winter-2026 and Spring-2027, even had `null`
term/year at the time this was found, and still sorted correctly under the
new approach).

### Supabase Site URL vs Redirect URLs (fixed August 2026)
Production login was found redirecting to `http://localhost:3000` — a
default Supabase creates for every new project. The cause: Site URL had
never been changed off that default, and `portal.hindikineev.org` was never
actually added to Redirect URLs (only assumed to have been). Both settings
are now correctly configured — see the "Supabase Auth URL Configuration"
section above for what each setting does and why both matter.

### Google sign-in failing on the new dev Supabase project ("Unable to exchange external code")
When setting up the dev project's Google OAuth, login consistently failed
with `unexpected_failure` / `Unable to exchange external code`, even though
every config item checked out correct — Client ID, Client Secret, redirect
URI (exact character match with Google Cloud Console), Site URL, Redirect
URLs, Supabase platform status. Auth Logs showed no error entry for the
failed attempts either, which was itself unusual. **Never fully root-caused**
— but creating a **brand-new, separate Google OAuth Client ID** (same Google
Cloud project, "HKN School," just a fresh client rather than the original
shared one) resolved it immediately. Best working theory: something about
the original Client ID's long history of accumulated origins/redirect URIs
across this whole project put it into a state that didn't work cleanly for
a brand-new Supabase project's callback — but this is a description of what
fixed it, not a confirmed explanation of why the original one failed. If a
future Supabase project's Google login ever fails the same way with every
config item checking out, a fresh Client ID is worth trying before spending
much more time on deeper diagnosis.

### Staff pages showing the wrong "current" session mid-year (fixed August 2026)
`SessionEngine.getUnderwaySession()` — used by the Student Directory,
Attendance Marking's default session, and the teacher-edit-permission check
in the Student Detail Modal — originally fell back to "the most recently
**started** session" whenever no session's class dates literally covered
*today*. Since Fall-2026's first class date (Sept 12) is in the future
during the summer, it was excluded from that fallback entirely, causing
Spring-2026 (already finished) to be picked as "current" instead — showing
stale class levels in the Directory, defaulting Attendance to the wrong
session, and even blocking teachers from editing their own students' current
scores/notes since the ownership check thought Fall-2026 wasn't the active
session.

**Fixed by preferring the `enrollmentOpen: true` session** as a fallback,
before falling through to "most recently started" — mirroring the same fix
already applied to `getActiveSession()` for the top banner:
```javascript
const openSess = sessions.find(s => s.enrollmentOpen);
if (openSess) return openSess;
```

### Classes page showing a confusing "unassigned" catch-all card (fixed August 2026)
Students with no teacher assigned yet (In-Process, Dropped, etc.) were all
being grouped into a single card keyed `'—|—'`, mixing together students
with completely different statuses and no way to tell them apart. Fixed by
excluding students with no teacher from the grouping entirely — they remain
fully visible everywhere else (Directory, their own record), just not on
this "class rosters" page, which now only shows real, staffed classes.

### Sessions page "Current" badge showing the wrong session (fixed August 2026)
The orange "Current" highlight on the Sessions page used
`SessionEngine.getCurrentSession()` — a much simpler, separate function from
`getActiveSession()`/`getUnderwaySession()` (both already fixed above) that
just guesses a session name from **today's calendar month** (Sep–Dec → Fall,
Jan–Feb → Winter, else → Spring), with no awareness of `enrollmentOpen` at
all. In August, this always resolves to "Spring", so Spring-2026 (already
closed) was shown as current instead of Fall-2026 (open for enrollment).
Fixed by swapping that one call site to `getActiveSession()`, matching the
pattern already used correctly everywhere else in the app. `getCurrentSession()`
itself is left as-is — it's still used safely as a last-resort fallback in a
few places, always after `getActiveSession()` is tried first.

### Session cards inconsistently sized after a card-content edit (fixed August 2026)
A partial-match edit to `renderSessionCard()` (splitting the Fees box to be
admin-only) replaced content but didn't consume the original block's closing
`</div>`, leaving it orphaned. That stray tag prematurely closed the whole
card element, throwing off nesting for everything after it — which browsers
handle by silently reflowing the rest of the page in confusing, inconsistent
ways (first card looked half-width, others full-width). A general lesson
worth remembering: when using find-and-replace to edit *part* of an HTML
block, always verify the *closing* tag is still correctly matched afterward,
not just that the new content itself is well-formed — counting opening vs.
closing tag totals across the whole function (not just the edited snippet)
catches this reliably.

### PostgREST not recognizing new tables/policies created via SQL Editor (encountered August 2026)
After creating the `teacher_presence` table and its RLS policies directly
via SQL Editor, upserts kept failing with a `42501` "row-level security
policy" error — even after the policies were repeatedly confirmed correct
via direct `pg_policies` queries. Root cause: PostgREST (Supabase's REST API
layer) maintains its own cache of table/policy structure, separate from the
database itself, and this cache doesn't always refresh automatically after
SQL Editor changes. Fixed by forcing a manual reload:
```sql
NOTIFY pgrst, 'reload schema';
```
**Worth remembering for any future new table/policy added via raw SQL:** if
something looks perfectly correct in the database (confirmed via
`pg_policies`, `information_schema`, etc.) but still fails with a confusing
auth-flavored error, try this reload early — it can save a lot of time spent
re-checking policy logic that was never actually wrong.

Separately, also worth knowing: an upsert (`INSERT ... ON CONFLICT DO
UPDATE`) requires a **SELECT** policy in addition to INSERT/UPDATE — both to
check for conflicts, and because PostgREST returns the written row by
default. A user needs to be able to `SELECT` their own row for their own
upsert to succeed, not just `INSERT`/`UPDATE` it — easy to miss since it's
not obvious from the error message alone.

---

## Teacher & Admin Activity

Admin can see, at a glance, who's currently active and when each person
last logged in — teachers on the **Dashboard** ("Teacher activity" card) and
on **School Attributes → Teachers**; admins on the Dashboard too ("Admin
activity" card, deliberately kept separate from Teacher activity rather than
merged, matching how admins are treated as a structurally distinct category
everywhere else in this schema).

**How "Active now" works:** each logged-in user's browser sends a heartbeat
(upsert to `teacher_presence`) immediately on login, then every 60 seconds
while a tab stays open. This fires for **any** logged-in user regardless of
role — so `teacher_presence` already captures admin activity too, with no
separate table or extra fetch needed; the Dashboard's admin-activity display
simply reuses the exact same `presenceMap` already fetched for teachers.
Anyone active within the last **2 minutes** shows as "🟢 Active now";
otherwise "Last seen Xm/Xh/Xd ago" (auto-scaling units, never raw minutes
past the first hour). The threshold is a single constant
(`PRESENCE_ACTIVE_THRESHOLD_MS` in `index.html`) if it ever needs adjusting.

**Closing a tab without logging out** behaves the same as a clean logout
from admin's point of view — no final "goodbye" signal is possible either
way, but the heartbeat naturally stops and the display self-corrects to
"Last seen..." within a couple minutes regardless. Considered adding an
explicit "clear presence on logout" step, but decided against it — closing
the tab (the more common real behavior, especially on mobile) already
degrades gracefully on its own, so the extra step would only help the less
common deliberate-logout case.

**Mobile note:** there's no auto-logout timer on mobile (deliberate, for a
smooth teacher experience), but this doesn't cause a stuck "always active"
reading — mobile browsers suspend JavaScript timers when a tab is
backgrounded or the screen locks, so the heartbeat naturally stops and the
display correctly goes stale within a couple minutes of someone stepping
away, even though their login session itself stays valid indefinitely.

**`last_login`** is separate from presence — set once, at the moment of
successful sign-in, via `update_own_last_login()`, which tries updating both
`teachers` and `admins` for the calling user's own row (an email only ever
matches one of the two tables, so the other update silently affects 0 rows).
Deliberately not a general "update your own row" policy on either table,
which would also let someone modify `role` or other fields on their own row.

**Reading admin activity specifically required a different approach than
teachers**, since `admins` has zero direct SELECT access by design (see
"Admin Safety Net" above) — `get_admin_activity()` is a narrow function that
explicitly checks `is_admin()` before returning anything, and only exposes
email/name/last_login, never the whole table.

---

## Accounts In Use (reference only)

| Email | Used for |
|-------|----------|
| `rajiv@hindikineev.org` | Personal admin account; portal admin login |
| `portal@hindikineev.org` | Day-to-day portal admin; also owns the **GitHub** account (`portal-sudo`) used for deployment |
| `admin@hindikineev.org` | Google Workspace admin, Squarespace domain admin |

---

## Admin Accounts (in `admins` and/or `teachers` tables)

| Name | Email | Role |
|------|-------|------|
| Rajiv Mathur | rajiv@hindikineev.org | Admin (protected in `admins`) |
| HKN Portal | portal@hindikineev.org | Admin (protected in `admins`) |

---

## Key Contacts / Resources

- **Supabase support:** `https://supabase.com/support`
- **GitHub Pages docs:** `https://docs.github.com/en/pages`
- **GitHub status (check during odd deployment issues):** `https://githubstatus.com`
- **School website:** `https://www.hindikineev.org`
- **School email:** `info@hindikineev.org`

---

## Post-Cutover Notes

- [x] Parallel deployment at `portal-new.hindikineev.org` tested and confirmed working
- [x] `admins` table verified to contain both rajiv@ and portal@
- [x] Cutover completed — `portal.hindikineev.org` running new Supabase-based system
- [x] Production login fully verified — both Site URL and Redirect URLs correctly configured
- [x] Parent portal session-selection bug found and fixed
- [x] Staff-side "current session" detection bug found and fixed (Directory,
      Attendance default, teacher edit permissions)
- [x] Classes page: teacher/level filters added, unassigned-students card removed
- [x] Homework Note bulk-broadcast feature added, with same-session Undo
- [x] Parent Guide renamed to FAQs, made prominent on the parent Welcome screen
- [x] Dashboard restructured — Sessions overview replaced with Classes overview
      (both roles); teacher-only view further trimmed (no Fees on Sessions page)
- [x] Sessions page "Current" badge bug fixed (was using calendar-month guess,
      not `enrollmentOpen`)
- [x] Separate dev Supabase project stood up for `portal-new` — genuinely
      isolated from production data now, with automatic domain-based
      switching in `index.html` (no manual file editing needed to deploy
      the same file to both repos)
- [x] Teacher & Admin Activity feature added (Dashboard cards + Teachers
      subtab) — see dedicated section above; admin activity reuses the
      teacher_presence data, with a narrow get_admin_activity() function
      for the admins table specifically
- [ ] Student photos — Storage bucket + `photo_path` column exist
      (foundation only); upload/display UI not yet built
- [ ] Old Drive/Apps Script backend — no urgency, retire whenever convenient
- [ ] Populate remaining scoring guide content (most levels still placeholder text)
