# Western Ride Share — Prelaunch verification (2026-11-14)

Scope: `feature/ride-comfort-preferences` and the shared Supabase project. Production GitHub `main` was not modified.

## Verified by database inspection / simulated role
- `public.rides` and `public.ride_messages` have suspension enforcement triggers.
- Ordinary-member simulated session: `is_site_admin() = false`, 0 private member profiles visible, safety reports inaccessible, direct `ride_messages` INSERT privilege absent.
- Admin list RPC rejects a simulated non-admin invocation.
- Safety-report scheduler `western-ride-share-safety-alerts` is active at `*/5 * * * *`.
- Existing safety email delivery records: 6 sent; worker previously returned HTTP 200 with 5 newly accepted, 0 failed.
- No public tables were observed with RLS disabled.
- Feature-branch auth/reset pages have 12-character new-password validation and recovery-link gating.

## Still requiring real browser/user testing
1. Sign up and confirm email with a new test account.
2. Request a password reset; follow the email link; set a 12+ character password; verify old password fails and new password signs in.
3. With two accounts, create and filter rides; verify owners and non-owners see intended data.
4. Start and reply to a message; confirm only participants see thread and email notification works.
5. Block another member and verify new messaging is denied.
6. Submit a safety report; verify the admin sees it and the email is received; verify reporting is not dependent on keeping browser open.
7. Sign in as ordinary member and attempt admin URL and RPC; confirm denied.
8. With a dedicated disposable account, suspend it; verify new rides/messages are blocked and unsuspension restores ability. Avoid testing suspension against a real user.
9. Check mobile layouts, keyboard navigation, logout and recovery errors.

## Open issues / caveats
- Supabase leaked-password detection is unavailable on the Free plan.
- Supabase advisor flags privileged SECURITY DEFINER RPCs; these require continued scrutiny and must retain explicit authorization checks.
- Existing suspensions prevent new activity, not necessarily login or visibility of previously posted content.
- A database job's `succeeded` status only means its SQL ran; verify HTTP and provider delivery separately.
- The scheduled worker currently processes up to 100 reports from the last seven days per run; review queue behavior and retry policy under heavier traffic.
- A previously sent report email is not proof of inbox delivery.
- This document is not an external penetration test or a completed end-to-end test.
