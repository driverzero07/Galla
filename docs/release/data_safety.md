# Play Console: Data safety form (answers to enter)

Play Console > App content > Data safety. These answers match
`privacy_policy.md`. Re-check them if the app starts collecting anything new.

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes
(HTTPS).
**Do you provide a way for users to request that their data is deleted?**
Yes: needs the deletion URL / email in the privacy policy (see blocker below).

| Data type | Collected | Shared | Purpose | Optional? |
| --- | --- | --- | --- | --- |
| Phone number (Personal info) | Yes | No | App functionality (login), Account management | No |
| Name (shop name, customer and supplier names the owner types) | Yes | No | App functionality (backup and restore) | No |
| Other info: phone numbers of customers/suppliers typed by the owner | Yes | No | App functionality (backup and restore) | Yes |
| Financial info: user payment info | **No** (the app stores amounts owed in the shop's own records; it takes no card or bank details) | No | n/a | n/a |
| Photos (item and purchase-bill photos) | Yes | No | App functionality | Yes |
| Crash logs / Diagnostics | Yes | No | Analytics (app stability) | No |
| Location, contacts, audio, files, calendar, web history, health | **No** | n/a | n/a | n/a |

"Shared" is **No** everywhere: Supabase and Sentry act as service providers
processing data on our behalf, which Play does not count as sharing.

**Data is processed ephemerally?** No (stored for the account lifetime).

## Release blockers to resolve before production

1. Publish the privacy policy at a public URL and enter it in the listing.
2. Play requires an **account deletion** option and a **web URL** for
   deletion requests for apps that create accounts. The app has no in-app
   delete-account button yet: either add one (Part 8) or provide a web form /
   email process and enter its URL in the Data safety form.
3. Create the Sentry project and pass `SENTRY_DSN` at build time (crash
   reporting is off without it).
