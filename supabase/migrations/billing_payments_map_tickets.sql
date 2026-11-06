-- Record of the billing, payments, map, and repair migration already applied in Supabase.
-- Do not drop existing customer columns. Safe to re-run.

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

create table if not exists public.app_settings (
  key text primary key,
  value text,
  is_public boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value, is_public) values
  ('gcash_number', '', true),
  ('gcash_name', '', true),
  ('gcash_qr_url', '', true),
  ('payment_note', '', true)
on conflict (key) do nothing;

alter table public.app_settings enable row level security;

drop policy if exists app_settings_public_read on public.app_settings;
create policy app_settings_public_read on public.app_settings
  for select to anon, authenticated
  using (is_public = true);

drop policy if exists app_settings_admin_all on public.app_settings;
create policy app_settings_admin_all on public.app_settings
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.app_settings to anon, authenticated;
grant insert, update, delete on public.app_settings to authenticated;

-- ---------------------------------------------------------------------------
-- Customers: map coordinates
-- ---------------------------------------------------------------------------

alter table public.customers add column if not exists latitude double precision;
alter table public.customers add column if not exists longitude double precision;

-- ---------------------------------------------------------------------------
-- Invoices and payments
-- ---------------------------------------------------------------------------

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  period text not null check (period ~ '^[0-9]{4}-[0-9]{2}$'),
  amount numeric(12, 2) not null,
  due_date date,
  status text not null default 'unpaid' check (status in ('unpaid', 'pending', 'paid', 'void')),
  notes text,
  created_by text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (customer_id, period)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  customer_id uuid not null references public.customers (id) on delete cascade,
  amount numeric(12, 2) not null,
  method text not null check (method in ('gcash', 'maya', 'bank', 'cash', 'other')),
  reference_no text,
  payer_name text,
  proof_path text,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  source text not null default 'website' check (source in ('website', 'admin')),
  submitted_at timestamptz not null default now(),
  confirmed_by text,
  confirmed_at timestamptz,
  notes text
);

create index if not exists invoices_customer_idx on public.invoices (customer_id, period);
create index if not exists payments_status_idx on public.payments (status, submitted_at desc);

create or replace function public.sync_invoice_from_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'confirmed' then
    update public.invoices
      set status = 'paid', paid_at = coalesce(paid_at, now())
      where id = new.invoice_id and status <> 'void';
  elsif new.status = 'pending' then
    update public.invoices
      set status = 'pending', paid_at = null
      where id = new.invoice_id and status <> 'void';
  elsif new.status = 'rejected' then
    update public.invoices
      set status = 'unpaid', paid_at = null
      where id = new.invoice_id and status <> 'void';
  end if;
  return new;
end;
$$;

drop trigger if exists payments_sync_invoice on public.payments;
create trigger payments_sync_invoice
  after insert or update of status on public.payments
  for each row execute function public.sync_invoice_from_payment();

alter table public.invoices enable row level security;
alter table public.payments enable row level security;

drop policy if exists invoices_admin_all on public.invoices;
create policy invoices_admin_all on public.invoices
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists payments_admin_all on public.payments;
create policy payments_admin_all on public.payments
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.invoices to authenticated;
grant select, insert, update, delete on public.payments to authenticated;

-- ---------------------------------------------------------------------------
-- Anonymous bill lookup and payment submit
-- ---------------------------------------------------------------------------

create or replace function public.lookup_bill(acct text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
  masked text;
  first_bit text;
  last_bit text;
begin
  select * into cust
  from public.customers
  where account_number = btrim(coalesce(acct, ''))
  limit 1;
  if not found then
    return null;
  end if;

  first_bit := nullif(btrim(coalesce(cust.first_name, split_part(coalesce(cust.name, ''), ' ', 1))), '');
  last_bit := nullif(btrim(coalesce(cust.last_name, split_part(coalesce(cust.name, ''), ' ', 2))), '');
  masked := coalesce(first_bit, 'Customer');
  if last_bit is not null and last_bit <> '' then
    masked := masked || ' ' || left(last_bit, 1) || '.';
  end if;

  return json_build_object(
    'name', masked,
    'plan', coalesce(nullif(cust.plan_speed, ''), cust.plan),
    'invoices', coalesce((
      select json_agg(json_build_object(
        'id', i.id,
        'period', i.period,
        'amount', i.amount,
        'due_date', i.due_date,
        'status', i.status
      ) order by i.period)
      from public.invoices i
      where i.customer_id = cust.id
        and i.status in ('unpaid', 'pending')
    ), '[]'::json)
  );
end;
$$;

create or replace function public.submit_payment(
  acct text,
  p_invoice uuid,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_payer text,
  p_proof text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust_id uuid;
  inv public.invoices%rowtype;
  new_id uuid;
begin
  if p_proof is not null and btrim(p_proof) <> '' and p_proof !~ '^proofs/.+' then
    raise exception 'The payment screenshot must be stored under proofs/.';
  end if;
  if p_reference is null or btrim(p_reference) = '' then
    raise exception 'Reference number is required.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;
  if p_method is null or p_method not in ('gcash', 'maya', 'bank', 'cash', 'other') then
    raise exception 'Choose a valid payment method.';
  end if;

  select id into cust_id
  from public.customers
  where account_number = btrim(coalesce(acct, ''))
  limit 1;
  if cust_id is null then
    raise exception 'Account number was not found.';
  end if;

  select * into inv from public.invoices where id = p_invoice and customer_id = cust_id;
  if not found then
    raise exception 'That bill was not found for this account.';
  end if;
  if inv.status = 'paid' then
    raise exception 'This bill is already paid.';
  end if;
  if inv.status = 'void' then
    raise exception 'This bill is void.';
  end if;

  insert into public.payments (
    invoice_id, customer_id, amount, method, reference_no, payer_name, proof_path, status, source
  ) values (
    inv.id, cust_id, p_amount, p_method, btrim(p_reference), nullif(btrim(coalesce(p_payer, '')), ''),
    nullif(btrim(coalesce(p_proof, '')), ''), 'pending', 'website'
  )
  returning id into new_id;

  return json_build_object('ok', true, 'id', new_id);
end;
$$;

create or replace function public.generate_invoices(p_period text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count integer;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can generate invoices.';
  end if;
  if p_period is null or p_period !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'Period must look like YYYY-MM.';
  end if;

  insert into public.invoices (customer_id, period, amount, due_date, status, created_by)
  select
    c.id,
    p_period,
    coalesce(c.monthly_bill, c.price, 0),
    (to_date(p_period || '-01', 'YYYY-MM-DD') + interval '1 month' - interval '1 day')::date,
    'unpaid',
    nullif(auth.jwt() ->> 'email', '')
  from public.customers c
  where c.stage = 'active'
    and coalesce(c.monthly_bill, c.price, 0) > 0
  on conflict (customer_id, period) do nothing;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.lookup_bill(text) from public;
revoke all on function public.submit_payment(text, uuid, numeric, text, text, text, text) from public;
revoke all on function public.generate_invoices(text) from public;
grant execute on function public.lookup_bill(text) to anon, authenticated;
grant execute on function public.submit_payment(text, uuid, numeric, text, text, text, text) to anon, authenticated;
grant execute on function public.generate_invoices(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Network nodes and repair tickets
-- ---------------------------------------------------------------------------

create table if not exists public.network_nodes (
  id uuid primary key default gen_random_uuid(),
  node_type text not null check (node_type in ('OLT', 'LCP', 'NAP', 'CLOSURE', 'POLE', 'OTHER')),
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  ports integer,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.repair_tickets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  technician_id uuid references public.technicians (id) on delete set null,
  title text not null,
  description text,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  status text not null default 'pending' check (status in ('pending', 'ongoing', 'resolved')),
  created_by text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.network_nodes enable row level security;
alter table public.repair_tickets enable row level security;

drop policy if exists network_nodes_admin_all on public.network_nodes;
create policy network_nodes_admin_all on public.network_nodes
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists repair_tickets_admin_all on public.repair_tickets;
create policy repair_tickets_admin_all on public.repair_tickets
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.network_nodes to authenticated;
grant select, insert, update, delete on public.repair_tickets to authenticated;

-- ---------------------------------------------------------------------------
-- Payment proof storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists payment_proofs_anon_upload on storage.objects;
create policy payment_proofs_anon_upload on storage.objects
  for insert to anon
  with check (
    bucket_id = 'payment-proofs'
    and name ~ '^proofs/.+'
  );

drop policy if exists payment_proofs_admin_read on storage.objects;
create policy payment_proofs_admin_read on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-proofs' and public.is_admin());

drop policy if exists payment_proofs_admin_delete on storage.objects;
create policy payment_proofs_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'payment-proofs' and public.is_admin());
