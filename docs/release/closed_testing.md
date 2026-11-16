# Release steps: closed testing, then production

Everything below needs the owner's accounts; none of it can be done from the
code alone.

## One-time setup

1. `bash tool/setup.sh` (icon, splash, checks). All tests must pass.
2. Supabase: create the project, enable Phone auth (with an SMS provider),
   run `supabase/migrations/0001_galla_schema.sql` in the SQL editor, then
   keep the project URL and anon key for the build (see README). Check in the Table editor that RLS is ON for every table.
3. Sentry: create a project, copy the DSN.
4. `bash tool/enable_release_signing.sh` (creates the upload key; back up
   `android/upload-keystore.jks` and its password somewhere safe).
5. Publish the privacy policy URL (`privacy_policy.md`).

## Build

```
SUPABASE_URL=... SUPABASE_ANON_KEY=... SENTRY_DSN=... PRIVACY_URL=... \
  bash tool/size_check.sh
```

Uploads `build/app/outputs/bundle/release/app-release.aab`; the script fails
if any per-CPU APK is over 40 MB. Bump `version:` in `pubspec.yaml` (and
`AppInfo.version`) for every upload; the number after `+` must increase.

## Play Console

1. Create the app "Galla". Fill the listing from `play_store_listing.md`.
2. Fill App content: privacy policy, Data safety (`data_safety.md`),
   content rating, target audience, ads = none.
3. Testing > Closed testing > create track "pilot": add the pilot shops'
   Google account emails as testers, upload the .aab, roll out.
   (New personal developer accounts must have 12+ testers opted in for 14
   days before production access is granted; organisation accounts do not.)
4. Run `pilot_checklist.md` with 5 to 10 shops. Fix, re-upload, repeat.
5. When the go / no-go in the checklist is met: Production > Create release
   with the same .aab (staged rollout 10%, then 50%, then 100%, watching
   Sentry and Play Console's Android vitals).

## After release

- Keep `build/symbols` for each version (needed to read obfuscated crash
  stack traces).
- Keep the Supabase project on a paid plan with daily backups before real
  shops depend on it.
