# Manual checklist for 5 to 10 pilot shops

Do this on the shop owner's own phone, with the owner doing the tapping.
Time it with a stopwatch. Install the closed-testing build first.

## Per shop

| # | Check | Target | Result |
| --- | --- | --- | --- |
| 1 | Install, log in with the OTP, make a PIN: first real bill saved | **under 1 minute from opening the app on the Home screen** (setup itself excluded) | |
| 2 | Bill with one item, cash: taps counted from Home | **3 taps** (Bill, item, Bill banao) | |
| 3 | Bill on udhaar to an existing customer | picks customer once, saves | |
| 4 | Enter the owner's real paper khata for 10 customers with "Haath se likho" | every balance matches the paper copy | |
| 5 | Open Khata: the total udhaar equals the paper total | exact match | |
| 6 | Add 5 items with stock, sell 2: stock shown is correct | exact match | |
| 7 | Receive a payment from a customer: balance drops by that amount | exact | |
| 8 | Switch on airplane mode, make 3 bills, switch off: chip goes from "N changes baqi" to "Sab save hai" | within 1 minute of net | |
| 9 | Settings > Sync abhi works; last sync time updates | yes | |
| 10 | Settings > CSV backup opens the share sheet; file opens in Excel/Sheets with Urdu names intact | yes | |
| 11 | Log in on a second phone (or reinstall): all customers, stock and bills are back and match | exact match | |
| 12 | Receipt shared on WhatsApp reads correctly | yes | |
| 13 | Low-stock warning appears at the owner's level | yes | |
| 14 | App feels fast on their phone (scroll item list, open Home) | no lag | |
| 15 | Any crash or confusing screen | none; note screen + what they tried | |

## Record for each shop

Phone model and Android version, RAM, first-bill time, taps, any mismatch
between app and paper (write the numbers), and the owner's words about what
was confusing. Send crash reports' timestamps if any.

## Go / no-go for production

All shops pass 2, 4, 5, 8 and 11 with exact matches, no crash in 7 days of
real use, and the size check under 40 MB.
