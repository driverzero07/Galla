# Galla Privacy Policy

*Draft for the owner to review (ideally with a lawyer) and publish at a
public URL before the Play Store submission. Fill in the `<...>` parts.*

Last updated: `<date>`

Galla ("the app") is a khata and billing app for small shops. This policy
explains what the app stores and why.

## Who is responsible

`<Your name / company>`, `<address>`, `<support email>`.

## What the app stores

**On your phone (always):** everything you enter: shop name, customers and
suppliers (names, phone numbers), items, stock, bills, purchases, khata
entries, and photos of items and purchase bills. Your PIN is stored only as a
one-way hash in the phone's secure storage; we never receive it.

**On our server (when you are online, for backup and a new phone):**

- Your **phone number** (used to log you in with a one-time code).
- Your **shop data**: the same records listed above, including the names and
  phone numbers of your customers and suppliers that you typed in, and the
  photos you took.

Customer and supplier details belong to you. We use them only to give you
your backup and to restore it on a new phone. We do not look at them, sell
them, or use them for advertising.

## What the app does NOT collect

No location, no contacts, no microphone, no advertising ID, no analytics or
ad trackers. The camera is used only when you take an item photo, a purchase
bill photo or scan a barcode.

## Crash reports

If the app crashes, a report with the error type, the app version, and the
phone model and Android version can be sent to our crash-reporting service
(Sentry). Reports are cleaned on the phone first: no customer names, amounts,
phone numbers or messages are included.

## Who processes data for us

- **Supabase**: hosting, database, photo storage and phone login.
- **An SMS provider** used by Supabase to send the login code.
- **Sentry**: crash reports (see above).

Data is protected in transit (HTTPS). Each shop can only read its own rows
(row level security).

## How long we keep it, and deleting it

We keep your shop data while your account exists. To delete your account and
all server data, email `<support email>` from the registered phone's contact
details or use `<deletion page URL>`; we delete it within `<30>` days. Data on
your phone is removed by uninstalling the app or clearing its storage. You
can export everything as CSV from Settings at any time.

## Children

Galla is a business tool and is not meant for children under 18.

## Changes and contact

We will update this page when the app changes what it stores. Questions:
`<support email>`.
