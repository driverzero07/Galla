-- Galla Supabase schema (Part 7). Mirrors the local Drift tables.
-- Run once in the Supabase SQL editor (or `supabase db push`).
--
-- Design notes
--  * shop_id = the owner's auth user id (the app uses the account id as the
--    shop id), so row level security is simply `shop_id = auth.uid()`.
--  * Money is bigint paisa and quantity bigint thousandths, exactly like the
--    phone. Ids are client generated UUIDs, so pushes are idempotent upserts.
--  * No foreign keys and no unique(shop_id, barcode / bill_no): rows from
--    several offline phones arrive in any order, and one bad row must never
--    block a whole shop's sync. The phones enforce those rules.
--  * server_updated_at is set by the server on every write and is the pull
--    cursor. A later arrival wins (last write wins) for master data.
--  * No DELETE grants: the app never hard-deletes anything.

create or replace function public.galla_touch() returns trigger
language plpgsql as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end $$;

create table if not exists public.shops (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  name text not null,
  owner_name text,
  phone text not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_shops_pull on public.shops (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.shops;
create trigger galla_touch before insert or update on public.shops
  for each row execute function public.galla_touch();
alter table public.shops enable row level security;
drop policy if exists shop_owner on public.shops;
create policy shop_owner on public.shops for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.shops to authenticated;

create table if not exists public.items (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  name text not null,
  photo_path text,
  photo_url text,
  barcode text,
  unit text default 'kg' not null,
  cost_price bigint default 0 not null,
  sale_price bigint default 0 not null,
  low_stock_level bigint default 0 not null,
  is_archived boolean default false not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_items_pull on public.items (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.items;
create trigger galla_touch before insert or update on public.items
  for each row execute function public.galla_touch();
alter table public.items enable row level security;
drop policy if exists shop_owner on public.items;
create policy shop_owner on public.items for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.items to authenticated;

create table if not exists public.stock_movements (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  item_id text not null,
  qty bigint not null,
  reason text not null,
  ref_type text,
  ref_id text,
  note text,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_stock_movements_pull on public.stock_movements (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.stock_movements;
create trigger galla_touch before insert or update on public.stock_movements
  for each row execute function public.galla_touch();
alter table public.stock_movements enable row level security;
drop policy if exists shop_owner on public.stock_movements;
create policy shop_owner on public.stock_movements for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.stock_movements to authenticated;

create table if not exists public.customers (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  name text not null,
  phone text,
  is_archived boolean default false not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_customers_pull on public.customers (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.customers;
create trigger galla_touch before insert or update on public.customers
  for each row execute function public.galla_touch();
alter table public.customers enable row level security;
drop policy if exists shop_owner on public.customers;
create policy shop_owner on public.customers for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.customers to authenticated;

create table if not exists public.customer_ledger (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  customer_id text not null,
  type text not null,
  amount bigint not null,
  ref_id text,
  note text,
  date timestamptz not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_customer_ledger_pull on public.customer_ledger (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.customer_ledger;
create trigger galla_touch before insert or update on public.customer_ledger
  for each row execute function public.galla_touch();
alter table public.customer_ledger enable row level security;
drop policy if exists shop_owner on public.customer_ledger;
create policy shop_owner on public.customer_ledger for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.customer_ledger to authenticated;

create table if not exists public.suppliers (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  name text not null,
  phone text,
  is_archived boolean default false not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_suppliers_pull on public.suppliers (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.suppliers;
create trigger galla_touch before insert or update on public.suppliers
  for each row execute function public.galla_touch();
alter table public.suppliers enable row level security;
drop policy if exists shop_owner on public.suppliers;
create policy shop_owner on public.suppliers for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.suppliers to authenticated;

create table if not exists public.supplier_ledger (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  supplier_id text not null,
  type text not null,
  amount bigint not null,
  ref_id text,
  note text,
  date timestamptz not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_supplier_ledger_pull on public.supplier_ledger (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.supplier_ledger;
create trigger galla_touch before insert or update on public.supplier_ledger
  for each row execute function public.galla_touch();
alter table public.supplier_ledger enable row level security;
drop policy if exists shop_owner on public.supplier_ledger;
create policy shop_owner on public.supplier_ledger for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.supplier_ledger to authenticated;

create table if not exists public.sales (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  bill_no text not null,
  customer_id text not null,
  subtotal bigint not null,
  discount bigint default 0 not null,
  total bigint not null,
  paid_amount bigint default 0 not null,
  payment_mode text not null,
  status text default 'active' not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_sales_pull on public.sales (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.sales;
create trigger galla_touch before insert or update on public.sales
  for each row execute function public.galla_touch();
alter table public.sales enable row level security;
drop policy if exists shop_owner on public.sales;
create policy shop_owner on public.sales for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.sales to authenticated;

create table if not exists public.sale_lines (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  sale_id text not null,
  item_id text not null,
  name_snapshot text not null,
  qty bigint not null,
  unit_price bigint not null,
  cost_snapshot bigint not null,
  line_total bigint not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_sale_lines_pull on public.sale_lines (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.sale_lines;
create trigger galla_touch before insert or update on public.sale_lines
  for each row execute function public.galla_touch();
alter table public.sale_lines enable row level security;
drop policy if exists shop_owner on public.sale_lines;
create policy shop_owner on public.sale_lines for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.sale_lines to authenticated;

create table if not exists public.sale_returns (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  sale_id text not null,
  amount bigint not null,
  ledger_credit bigint default 0 not null,
  cash_refund bigint default 0 not null,
  note text,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_sale_returns_pull on public.sale_returns (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.sale_returns;
create trigger galla_touch before insert or update on public.sale_returns
  for each row execute function public.galla_touch();
alter table public.sale_returns enable row level security;
drop policy if exists shop_owner on public.sale_returns;
create policy shop_owner on public.sale_returns for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.sale_returns to authenticated;

create table if not exists public.sale_return_lines (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  return_id text not null,
  sale_id text not null,
  item_id text not null,
  qty bigint not null,
  amount bigint not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_sale_return_lines_pull on public.sale_return_lines (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.sale_return_lines;
create trigger galla_touch before insert or update on public.sale_return_lines
  for each row execute function public.galla_touch();
alter table public.sale_return_lines enable row level security;
drop policy if exists shop_owner on public.sale_return_lines;
create policy shop_owner on public.sale_return_lines for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.sale_return_lines to authenticated;

create table if not exists public.purchases (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  supplier_id text not null,
  purchase_no text default '' not null,
  total bigint not null,
  paid_amount bigint default 0 not null,
  invoice_image_path text,
  invoice_image_url text,
  status text default 'active' not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_purchases_pull on public.purchases (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.purchases;
create trigger galla_touch before insert or update on public.purchases
  for each row execute function public.galla_touch();
alter table public.purchases enable row level security;
drop policy if exists shop_owner on public.purchases;
create policy shop_owner on public.purchases for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.purchases to authenticated;

create table if not exists public.purchase_lines (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  purchase_id text not null,
  item_id text not null,
  qty bigint not null,
  unit_cost bigint not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_purchase_lines_pull on public.purchase_lines (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.purchase_lines;
create trigger galla_touch before insert or update on public.purchase_lines
  for each row execute function public.galla_touch();
alter table public.purchase_lines enable row level security;
drop policy if exists shop_owner on public.purchase_lines;
create policy shop_owner on public.purchase_lines for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.purchase_lines to authenticated;

create table if not exists public.settings (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  last_sync_at timestamptz,
  pin_lock_minutes bigint default 5 not null,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_settings_pull on public.settings (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.settings;
create trigger galla_touch before insert or update on public.settings
  for each row execute function public.galla_touch();
alter table public.settings enable row level security;
drop policy if exists shop_owner on public.settings;
create policy shop_owner on public.settings for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.settings to authenticated;

create table if not exists public.import_batches (
  id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  kind text not null,
  method text not null,
  row_count bigint not null,
  total_amount bigint default 0 not null,
  entity_ids text not null,
  photo_path text,
  undone_at timestamptz,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_import_batches_pull on public.import_batches (shop_id, server_updated_at);
drop trigger if exists galla_touch on public.import_batches;
create trigger galla_touch before insert or update on public.import_batches
  for each row execute function public.galla_touch();
alter table public.import_batches enable row level security;
drop policy if exists shop_owner on public.import_batches;
create policy shop_owner on public.import_batches for all to authenticated
  using (shop_id = auth.uid()) with check (shop_id = auth.uid());
grant select, insert, update on public.import_batches to authenticated;

-- Photos: private bucket, each owner can only touch the folder named after
-- their user id (path: <shop_id>/<file>.jpg).
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists photos_owner on storage.objects;
create policy photos_owner on storage.objects for all to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
