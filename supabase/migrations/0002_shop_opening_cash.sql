-- Accounts: cash in the drawer when the shop started using Galla (paisa).
-- Run once on the Supabase project BEFORE shipping app schema v6, otherwise
-- the shops row cannot sync.
alter table public.shops
  add column if not exists opening_cash bigint default 0 not null;
