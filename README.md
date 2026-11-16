# Galla

Offline-first khata + billing app for small shops in Pakistan.
Flutter, Riverpod, go_router, Drift (SQLite), Supabase (sync only).

**Status: Parts 1 to 7 written, not yet compiled.** See "Verification" below.

## First run

You need Flutter stable (3.32 or newer) and Android SDK.

```bash
bash tool/setup.sh        # flutter create (android), pub get, build_runner,
                          # gen-l10n, flutter analyze, flutter test
flutter run               # debug: fake OTP, code 123456
```

Drift and the localisation files are generated code (`*.g.dart`,
`lib/l10n/gen/`). They are git-ignored, so run `setup.sh` (or
`dart run build_runner build --delete-conflicting-outputs` and
`flutter gen-l10n`) after every fresh clone.

With Supabase configured (needed from Part 7; optional in Part 1):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Without those values the debug build uses a fake OTP provider (any phone,
code `123456`). A release build without Supabase config refuses to run setup.

## What Part 1 contains

- Design tokens, theme, bundled Inter + Fredoka Bold (`assets/fonts`).
- Widgets: `GallaCard`, `GallaPrimaryButton`, `GallaOutlineButton`,
  `GallaChip`, `GallaNavBar`, `MoneyText`, `SyncStatusChip`, `EmptyState`
  (plus `GallaLogo`, `GallaHeader`).
- Drift database with every table of the data model, indexes (barcode, FTS5
  on item name, ledger by customer/supplier, movements by item), DAOs, a
  versioned migration strategy, derived balances.
- `writeWithOutbox`: row + outbox entry in one transaction.
- Sync skeleton: connectivity watcher, three-state chip, worker triggers
  (reconnect, resume, every 5 min) that only log push/pull.
- Auth: first-time setup (phone, OTP, shop name, PIN), PIN login that works
  offline, PIN hashed in secure storage, 5 minute auto-lock, OTP provider
  behind an interface.
- go_router with all 12 design screens (placeholder bodies in the real
  theme/layout), bottom nav, auth redirects.
- All Roman Urdu strings in `lib/l10n/app_en.arb`.
- Tests: DB schema/migration/FTS/outbox atomicity, money (en_IN), PIN hashing,
  sync status, phone parsing, auth lock, a few widgets.

In a debug build, Menu has "Debug: all screens" which lists every route.

## Part 2: Inventory, Customers, Suppliers

- Saman list (search, "Khatam hone wala" filter, show hidden), Naya Saman /
  Saman badlo (photo, barcode scan, rates, opening stock, unit, low-stock
  level), stock correction with a reason, hide / show.
- Customer and Supplier lists from Menu: add, edit (name, phone), opening
  balance, hide / show. The system Naqad customer is never listed or editable.
- Stock and balances are always derived from movements / ledgers.
- **Schema version 2** adds `stock_movements.note` (the reason text); the
  first real migration, covered by `test/migration_test.dart`.
- Photos: camera, compressed JPEG in the app's private folder (`photos/`).
- Barcode scanner page (`scanBarcode(context)`) is reusable for Part 3.
- `setup.sh` now adds the camera permission to the Android manifest.

Part 2 assumptions: a duplicate barcode opens the existing item instead of
creating a second one; opening stock is entered only when creating (later
changes go through "Stock theek karo"); phone numbers that look Pakistani are
stored as `+92...`, anything else is kept as typed; Menu Customer / Supplier
now open the new lists (the Khata tab and Supplier ka khata screen stay
placeholders until Part 4).

## Part 3: Billing

- Naya Bill: customer chip (Naqad by default), search + barcode scan, 8
  quick-pick items, "Sab dekho", cart with -/+ and tap-to-edit quantity and
  price (price change is for this bill only), discount with Rs 10/50/100
  round-off, Nakad / Udhaar, "Abhi kitne diye" for partial payment.
- Saving is one transaction: sale, lines (name and cost snapshots), negative
  stock movements, khata entry for the unpaid part, outbox rows.
- Bill done screen with WhatsApp / PDF share and Print (80 mm roll).
- Aj ki bikri (`/bills`): today's bills, detail, Return, Cancel.
- Unsaved bill survives app restarts (local `device_state`, never synced).
- **Schema version 3**: `sale_returns` gains `ledger_credit`, `cash_refund`,
  `note`; new local-only `device_state` table. `migration_test.dart` covers it.
- New packages: share_plus, pdf, printing.

Part 3 assumptions: bill numbers look like `K7M-12` (random 3 character
device prefix + running number, kept in `device_state` so two phones never
clash); a return is valued at the price charged minus the line's share of the
bill discount; a return reduces the khata only by what the customer still owes
on that bill, the rest is recorded as a cash refund; cancel reverses the net
khata effect of the bill and the stock not already returned; selling past zero
stock asks for confirmation and then allows negative stock; quick-pick shows
the most sold items of the last 30 days and fills with items A-Z when fewer
than 8 have sold; Udhaar needs a real customer (picker opens first); the Home
"Aj Ki Bikri" card is a stopgap until Part 5.

## Part 4: Khata and Purchase

- **Khata tab**: Lena card (total owed + how many customers owe), search,
  sort "Sab se zyada" / "Naye pehle", rows with "Aakhri: 3 din pehle".
- **Customer khata** (`/khata/:id`): Baqaya card, Paisay mile (with
  "Poora baqaya" shortcut, note, date), Udhaar likho, full history with a
  running balance, bills open the bill, call / WhatsApp, statement share
  (A4 PDF or WhatsApp text), edit in the menu.
- **Supplier khata** (`/supplier/:id`): Dena card, Paisay diye, Naya Purchase,
  history with purchases (items, amount paid on the spot) and payments.
- **Purchase tab**: invoice photo, supplier picker, items with quantity and
  cost (search or scan), Abhi diye, supplier balance after this purchase.
  Saving is one transaction: purchase + lines, positive stock movements,
  new `items.cost_price`, supplier ledger row for the unpaid part only.
- Purchase history (`/purchases`) and detail with a zoomable invoice photo.
- **Schema version 4**: `purchases.purchase_no`. `migration_test.dart` covers
  v1/v2/v3 to v4.
- New package: url_launcher (`tool/setup.sh` adds the Android `queries`).

Part 4 assumptions: balances are always SUM of the ledger (the history's last
running balance is that same number); the Lena total adds only customers who
owe, advances are shown on their own rows and not netted off; a customer
history lists only what touched khata (credit bills, partial bills' unpaid
part, returns, cancels, payments), not cash bills; a payment bigger than the
baqaya is kept as an advance; entries on a picked date use that day with the
current time so same-day rows keep their order; purchase numbers use the same
per-device prefix as bills (`K7M-3`); the latest purchase cost replaces the
item's cost price; a purchase paid in full writes no supplier ledger row; a
supplier whole balance on the Purchase screen = current dena + this unpaid;
the Purchase draft lives in memory only; Menu customer and supplier lists now
open the khata, edit is in its menu; statement text keeps the newest 40 rows.

## Part 5: Home dashboard and alerts

- Home matches the design: greeting with the owner's name, bell with a count
  badge, "..." to Menu, **Aj Ki Bikri** (chips Cash / Udhaar), **Aj Ka Munafa**,
  **Lena** and **Dena** cards (each opens its list), and **Khatam Hona wala
  saman** with the 3 lowest items and a Bacha chip ("..." opens the Saman list
  already filtered to low stock).
- Every number is a live Drift query (`SalesDao.watchDaySummary`, item stock,
  party balances), so Home changes the moment a bill, payment or stock move is
  saved. `dayStartProvider` re-emits at midnight and when the app resumes, so
  "today" rolls over by itself (Today's bills list uses it too).
- Bell (`/alerts`): low-stock items and a sync warning when offline with
  changes waiting.
- First-day empty state: no items yet shows **Pehla saman add karo**.
- One local notification a day at 9 am (Asia/Karachi) while anything is low
  on stock (`flutter_local_notifications` + `timezone`). `tool/setup.sh` adds
  the Android permissions, boot receiver and library desugaring it needs.

Part 5 assumptions: Aj Ki Bikri counts active bills created today in the
phone's local time (a phone set to another zone shows that zone's day); Cash is
the money paid at the counter (sum of paid amounts) and Udhaar is the unpaid
rest, so Cash + Udhaar = total; profit follows Part 0 rule 9 (bill totals after
discount minus qty x cost snapshot, cancelled bills excluded) and does **not**
net off returns made today; Lena/Dena are the sum of positive balances (same as
the Khata tab); "lowest" means least stock first, negative stock first; the
bell badge is the number of low items plus one for a sync problem, and a sync
problem means offline with pending changes (Part 7 can add real errors); the
notification repeats daily at about 9 am (inexact alarm, no special permission)
and is cancelled as soon as the app sees nothing low, so if stock is refilled
on another device it can still show once until the app is next opened; tapping
the notification just opens the app.

## Part 6: Migration from the paper copy

Menu > "Purani copy se data". Three steps: choose how, check, done.

- **Haath se likho**: keyboard-only name + baqaya lines (customers and
  suppliers). Blank lines are ignored.
- **CSV / Excel file**: .csv, .txt, .tsv, .xlsx, .ods (not old .xls: save it
  as .xlsx or .csv). Column matching is guessed from English / Roman Urdu /
  Urdu headers, or by column order when there is no header; the owner can
  change every column. Customers, suppliers and saman (items) are supported.
- **Copy ki photo (OCR)**: code is written but **switched off**
  (`FeatureFlags.ocrImport = false`), so the option is hidden and nothing is
  ever sent. `supabase/functions/ocr-ledger/index.ts` is a reference Edge
  Function that is **not deployed and not tested**; the key would live only in
  its secrets.

Every line is editable on the confirm screen before anything is saved. Lines
that are unsure (a "?", a minus, a bad phone, low OCR confidence) are amber
"Pakka nahi, check karo"; unreadable lines are red and block the button.
The whole import is ONE transaction (all rows or none), and it adds an
`import_batches` row (schema v5) so it can be undone.

Part 6 assumptions:

1. Opening balances are dated the import day, type `opening`, `refId` = the
   batch id. Customers: + means they owe us; suppliers: + means we owe them.
2. A negative amount is kept as an advance but flagged "check karo".
3. Duplicates (same name + phone already saved, or repeated in the file) start
   switched off; "Phir bhi jama karo" turns them on. A repeated barcode is an
   error (barcodes are unique).
4. Items get opening stock as an `opening` stock movement; unknown unit words
   fall back to Kg and are flagged.
5. Undo is only allowed while nothing has touched the imported rows (no later
   ledger entry, sale, purchase or stock movement). It adds reversing entries
   and archives the customers / suppliers / items; nothing is deleted. If any
   row was used, the whole undo is refused and says how many.
6. Amounts accept Urdu digits, Western and Indian commas, Rs / PKR, brackets.
7. New packages: `file_picker`, `spreadsheet_decoder`.

## Part 7: Sync, testing, release

### Sync (real, replaces the Part 1 stub)

1. In Supabase run `supabase/migrations/0001_galla_schema.sql` (tables,
   indexes, RLS, private `photos` bucket). It was generated from
   `lib/core/db/tables.dart`: read it once before running. If you change a
   table in Dart, change the SQL too.
2. Build with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
   Without them (or in the debug fake-OTP mode) there is no server session, so
   nothing is sent: the chip keeps showing "N changes baqi" and Settings says
   "Server set nahi hai ya login nahi hua".

How it works (`lib/core/sync/`):

- **Push**: outbox oldest first, 50 rows per batch, one idempotent upsert per
  table per batch. An outbox row is deleted only after the server confirmed.
  Failures bump `attempts`, then back off 5 s, 10 s, 20 s ... max 15 min.
  "Sync abhi" ignores the wait.
- **Pull**: per table, rows with `server_updated_at` at or after the saved
  cursor, in order shops, items, customers, suppliers, sales, purchases,
  ledgers, stock movements. A pulled row never overwrites a row that still has
  an unsent local change.
- **When**: on unlock, on reconnect, about 8 seconds after a new change while
  online, every 5 minutes.
- **Restore**: after the OTP on a new phone, if the server already has the
  shop, everything (including settings) is pulled, then the owner only makes a
  new PIN. A cut connection resumes from the saved cursors.
- **Photos**: uploaded before each push to the private `photos` bucket; the
  row keeps `photoPath` (this phone) and `photoUrl` (a one-year signed link).
  Local paths are never sent. Other phones show the URL.
- **Settings > Sync aur backup**: status, last sync, errors, "Sync abhi", and a
  CSV backup (one file per kind of data, UTF-8 with BOM for Excel, text cells
  starting with = + - @ are kept as text) shared through the share sheet.
- **Crash reports**: Sentry, only when built with `--dart-define=SENTRY_DSN=`
  (never in debug). Events are rebuilt from an allow-list: error type, stack,
  app version, device model and OS. Messages, breadcrumbs, user and request
  data are dropped.

Part 7 assumptions (please check):

1. Shop id = auth user id, so RLS is just `shop_id = auth.uid()`.
2. Last write wins by ARRIVAL at the server (`server_updated_at`), not by the
   phones' clocks.
3. No foreign keys and no unique bill number / barcode on the server, so one
   bad row cannot block a shop. If two offline phones make the same barcode,
   the later pulled item loses its barcode; the same bill number, the later
   bill gets `~xxxx` added. Bill prefixes are random per phone, so this is rare.
4. A row the server keeps refusing blocks the queue behind it (order matters);
   Settings shows "N changes server ne qabool nahi kiye". There is no
   automatic skipping.
5. `settings` is only pulled on restore; `import_batches.photoPath` stays on
   the phone.
6. Photo links last one year; refreshing them is not built.
7. The Supabase session is kept by `supabase_flutter`. If it ever becomes
   invalid, sync reports "login nahi hua"; there is no re-login screen yet.
8. There is no in-app "delete my account" yet. Play requires a way to request
   deletion: see `docs/release/data_safety.md`.

### Tests added

- `test/sync/`: key/date mapping, real rows phone -> server -> phone, batching,
  failure + backoff, idempotent re-push, not-signed-in, restore, pending local
  change wins, photos, **two phones billing offline (totals match, no duplicate
  bill numbers)**, and the **full offline day** (server rows give the same khata
  and stock as the phone).
- `test/backup_test.dart`, `test/crash_scrub_test.dart`, and
  `test/bill_flow_widget_test.dart` (search item, tap, Bill banao).
  The widget test drives real drift streams and is the most likely to need a
  small timing tweak on first run.

### Release (`docs/release/`, `tool/`)

- Icon and splash from the G logo (`assets/icon/`): `tool/setup.sh` now runs
  `flutter_launcher_icons` and `flutter_native_splash`.
- `tool/enable_release_signing.sh`: upload keystore + `key.properties`
  (git-ignored) + Gradle patch.
- `tool/size_check.sh`: release build (per-CPU APKs + .aab, obfuscated) and
  fails over 40 MB. Needs `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- `play_store_listing.md`, `privacy_policy.md` (draft to review),
  `data_safety.md`, `pilot_checklist.md`, `closed_testing.md`.
- Version is now `1.0.0+1` (`pubspec.yaml`, `AppInfo.version`).

**Not done and cannot be done from here:** running any build or test, the
Supabase project, Sentry project, signing key, Play Console, screenshots from a
real phone, the pilot shops, and closed testing. The "app is live on closed
testing" goal is therefore open: follow `docs/release/closed_testing.md`.

## Assumptions (Part 1)

1. **ARB locale.** Roman Urdu text lives in `app_en.arb` (locale `en`) so
   Flutter does not switch to right-to-left. Urdu script will be a separate
   `app_ur.arb` later.
2. **Shop id = Supabase account id** (a random UUID in the debug fake). This
   lets row level security use one id and a new phone restore the same shop.
3. **Naqad customer** is created at setup (not at DB creation, because the
   shop id is not known yet) with a deterministic UUID per shop, so two
   phones never create duplicates.
4. **Setup asks only for phone, OTP, shop name, PIN**, as in the brief. The
   Home greeting shows the shop name until Part 5 decides where the owner's
   name is collected (`shops.owner_name` already exists, nullable).
5. **`sale_returns`** has a header (`sale_id`, `amount`) and lines
   (`return_id`, `sale_id`, `item_id`, `qty`, `amount`).
6. **Settings** has only the fields in Part 0. Part 3 needs a per-device bill
   prefix and sequence; it will add them with a schema version 2 migration
   (the strategy and an example comment are in `app_database.dart`).
7. **No foreign key constraints** on references between tables, so Part 7 can
   apply pulled rows in any partial order. Integrity is enforced in code.
8. Locking while deep in the app sends you to Login and then Home (the
   previous screen is not restored).
9. Menu "Customer" opens the Khata tab and "Supplier" opens the Supplier
   screen placeholder until Parts 2 and 4 add the real lists.
10. PIN hash is salted, iterated SHA-256. A 4-digit PIN is a local lock, not
    strong security, and the app says so in code comments.

## Verification

The environment that wrote this code could not install Flutter (the Dart SDK
download host was blocked), so **nothing has been compiled, analysed or
run yet**. What was checked: every Dart file parses (tree-sitter), the ARB is
valid JSON, fonts were converted to TTF and bundled. Run `bash tool/setup.sh`;
if `flutter analyze` or a test fails, fix that before starting the next part.
