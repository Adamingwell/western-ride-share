# Security audit — 2026-11-14 (feature branch only)

Scope: static inspection of `docs/auth.js`, `docs/board.html`, `docs/admin.html`, migrations 006–010, and the two email Edge Functions. This is **not** a live penetration test or a verification of the current Supabase schema.

## Implemented
- **Messaging write boundary:** Migration `011_message_write_hardening.sql` revokes direct `INSERT/UPDATE/DELETE` on `ride_messages` from `anon`, `authenticated` and `PUBLIC`, leaving `send_ride_message` as the intended SECURITY DEFINER write path. Its insert trigger now validates JWT sender identity, distinct participants, ride ownership, blocks, and suspensions. Must be run in Supabase and tested before relying on it.
- **Admin note dialog:** `docs/admin.html` no longer calls `showModal()` when the notes dialog is already open.

## Confirmed from repository code
- Auth uses Supabase's public/publishable client key; no service-role key appears in the reviewed browser scripts.
- Admin RPCs check `is_site_admin()` server-side; dashboard's client check is only a UI gate.
- Safety report submission is via `report_ride_user` SECURITY DEFINER RPC, which validates the report's ride or thread relationship.
- UI uses `textContent` for member-controlled report text and message bodies.
- `member_profiles` policies restrict normal reads and updates to the owner; `009` allows legacy users to insert their own profile.

## Important unresolved risks
1. **HIGH — Email alert reliability:** The browser calls `notify-safety-report` only after the report RPC completes. Closing the tab, blocking the request, or losing network connectivity can suppress admin email even when the report is stored. A trusted server-side event/queue (database webhook or trigger to a worker, with a secret and retries) is needed. Do not describe current email alerts as guaranteed.
2. **HIGH — Actual deployed RLS not inspected:** The complete live policies and grants for `rides`, `ride_messages`, `message_read_state`, `hidden_ride_conversations`, `notification_preferences`, and `member_profiles` were not available. Run an authenticated cross-account access test and inspect `pg_policies` and `information_schema.role_table_grants`.
3. **MEDIUM — Suspensions are partial:** Existing rides remain visible, login remains possible, and old content is not removed. The UI explicitly warns of this. Decide whether active rides from suspended accounts should be hidden or disabled.
4. **MEDIUM — Email delivery retries:** `notify-safety-report` claims a report before calling Resend; a failed delivery stays marked `failed`, but repeat requests return `already_processed`. Add a restricted retry workflow with idempotency and rate limits.
5. **MEDIUM — Message email trigger:** `notify-ride-message` looks up the latest message by sender and thread rather than accepting a unique message ID; concurrent messages may cause missed alerts. Evaluate message-ID-based notification and server-side queuing.
6. **MEDIUM — Auth controls:** Email confirmation, signup restrictions, redirect allowlist, password policy, MFA for admins, and rate limits are Supabase dashboard settings not verifiable from the repository. Review them before launch.
7. **LOW — Profile name normalization:** `auth.js` and `board.html` use `/\\s+/g` instead of `/\s+/g` in the JavaScript source, so repeated whitespace is not normalized as intended. This is a data-quality issue, not an authorization bypass.

## Required deployment/test checklist
1. Run `supabase/011_message_write_hardening.sql` in the preview Supabase project. Note: preview and production sites currently share the same Supabase project, so database changes can affect live users even without merging GitHub branches. Schedule and back up accordingly.
2. With two test accounts, verify new conversation, reply, blocked messaging, suspended messaging, and attempted direct `ride_messages` INSERT/UPDATE/DELETE are denied.
3. Test a normal user cannot invoke `admin_report_list`, `admin_member_list`, `admin_set_suspension`, or read private reports/profiles belonging to another account.
4. Verify a report persists even if the email request fails; introduce server-side delivery before production launch.
5. Review production/preview environment isolation, admin MFA, audit logging, and recovery procedures.

**Deployment status:** Source-only changes. No SQL migration was executed, no Edge Function was deployed, and no production branch was modified during this audit.
