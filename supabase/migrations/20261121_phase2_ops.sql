-- Phase 2 operations: staff, service tickets, materials, modems, installation.
-- Idempotent. Does not drop tables, columns, or customer rows.
--
-- public.tickets stays the one-row-per-customer install assignment.
-- Service tickets (repair, installation, pullout, and the rest) are
-- public.ops_tickets so that unique customer_id is left alone.
--
-- Apply this file in the Supabase SQL editor. Do not run it from the site.

-- ---------------------------------------------------------------------------
-- search_path on the phase 1 helpers
-- ---------------------------------------------------------------------------

create or replace function public.normalize_gcash_ref(p_ref text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(regexp_replace(coalesce(p_ref, ''), '\D', '', 'g'), '');
$$;

create or replace function public.collection_cutoff(p_date date)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_date is null then null
    when extract(day from p_date) <= 15 then to_char(p_date, 'YYYY-MM') || ' 1-15'
    else to_char(p_date, 'YYYY-MM') || ' 16-end'
  end;
$$;

create or replace function public.clamp_due_date(p_year integer, p_month integer, p_day integer)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  last_day integer;
  use_day integer;
begin
  last_day := extract(day from (make_date(p_year, p_month, 1) + interval '1 month - 1 day'))::integer;
  use_day := least(greatest(coalesce(p_day, 1), 1), last_day);
  return make_date(p_year, p_month, use_day);
end;
$$;

-- Keep Newly Installed / Reconnected / FREE when an admin or the
-- installation RPC sets them. Other saves still follow the stage label.
-- fiberbro.allow_stage_jump lets complete_installation move a new client
-- to Active in one step after the investor is set.
create or replace function public.enforce_customer_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_n int;
  new_n int;
begin
  if new.stage is not distinct from old.stage then
    if old.stage = 'inquiry' and new.investor_id is not null then
      new.stage := 'in_progress';
    elsif old.stage = 'in_progress' and new.investor_id is null then
      new.stage := 'inquiry';
    end if;
  end if;

  if new.stage is distinct from old.stage then
    old_n := case old.stage
      when 'inquiry' then 1
      when 'in_progress' then 2
      when 'encoded' then 3
      when 'active' then 4
      else 0
    end;
    new_n := case new.stage
      when 'inquiry' then 1
      when 'in_progress' then 2
      when 'encoded' then 3
      when 'active' then 4
      else 0
    end;

    if coalesce(current_setting('fiberbro.allow_stage_jump', true), '') is distinct from '1' then
      if not (
        (old.stage = 'inquiry' and new.stage = 'in_progress')
        or (old.stage = 'in_progress' and new.stage = 'inquiry')
      ) and new_n <> old_n + 1 then
        raise exception 'Cannot move from % to %. Complete the previous stage first.', old.stage, new.stage;
      end if;
    end if;

    if new.stage = 'encoded' and new.investor_id is null then
      raise exception 'Assign an investor before marking this customer encoded in MikroTik.';
    end if;
    if new.stage = 'active' and new.investor_id is null then
      raise exception 'Assign an investor before marking this customer active.';
    end if;

    insert into public.customer_stage_events (customer_id, stage, changed_by)
    values (
      new.id,
      new.stage,
      coalesce(nullif(auth.jwt() ->> 'email', ''), 'system')
    );
  end if;

  if new.account_status is null
     or new.account_status not in ('Newly Installed', 'Reconnected', 'FREE') then
    new.account_status := public.stage_label(new.stage);
  end if;
  new.email_address := coalesce(new.email_address, new.email);
  new.fb_account := coalesce(new.fb_account, new.facebook_name);
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer intake columns. Existing rows stay as they are.
-- ---------------------------------------------------------------------------

alter table public.customers add column if not exists service_location text;
alter table public.customers add column if not exists referral_source text;
alter table public.customers add column if not exists referral_type text;
alter table public.customers add column if not exists referral_name text;
alter table public.customers add column if not exists privacy_consent boolean not null default false;
alter table public.customers add column if not exists modem_serial text;

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'customers'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%service_location%'
  loop
    execute format('alter table public.customers drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.customers add constraint customers_service_location_check
  check (
    service_location is null
    or service_location in ('Payatas', 'Maligaya', 'Pampanga')
  );

-- Installation invoices can share a month with the regular bill.
alter table public.invoices add column if not exists invoice_kind text not null default 'monthly';

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'invoices'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%invoice_kind%'
  loop
    execute format('alter table public.invoices drop constraint %I', r.conname);
  end loop;
  for r in
    select con.conname, pg_get_constraintdef(con.oid) as def
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'invoices'
      and con.contype = 'u'
  loop
    if r.def ilike '%customer_id%' and r.def ilike '%period%' and r.def not ilike '%invoice_kind%' then
      execute format('alter table public.invoices drop constraint %I', r.conname);
    end if;
  end loop;
end $$;

alter table public.invoices add constraint invoices_kind_check
  check (invoice_kind in ('monthly', 'installation'));

create unique index if not exists invoices_customer_period_kind_uidx
  on public.invoices (customer_id, period, invoice_kind);

-- Expenses keep Gas/Meals/… and also accept Operational and Personal.
alter table public.expenses add column if not exists account_code text;
alter table public.expenses add column if not exists scope text;
alter table public.expenses add column if not exists auto boolean not null default false;

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'expenses'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%Gas%'
  loop
    execute format('alter table public.expenses drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.expenses add constraint expenses_category_check
  check (category in (
    'Gas', 'Meals', 'Materials', 'Maintenance', 'Office Supplies',
    'Transportation', 'Repairs', 'Others', 'Operational', 'Personal'
  ));

-- ---------------------------------------------------------------------------
-- Staff
-- ---------------------------------------------------------------------------

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  name text not null,
  role text not null check (role in ('tech', 'admin', 'payroll_admin', 'investor')),
  active boolean not null default true,
  duty_status text not null default 'Available' check (duty_status in ('Available', 'On job', 'Off')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists staff_email_uidx on public.staff (lower(email));

create or replace function public.staff_normalize()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.email := lower(btrim(new.email));
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists staff_normalize on public.staff;
create trigger staff_normalize
  before insert or update of email on public.staff
  for each row execute function public.staff_normalize();

create or replace function public.is_tech()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and role = 'tech'
      and active
  );
$$;

create or replace function public.current_staff_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.staff
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and active
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Tickets, notes, materials, prices
-- ---------------------------------------------------------------------------

create table if not exists public.ops_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_no text not null,
  ticket_type text not null check (ticket_type in ('REP', 'INSTALLATION', 'PUL', 'CHP', 'MOD', 'REL', 'REW')),
  customer_id uuid references public.customers (id) on delete set null,
  issue text,
  status text not null default 'Open' check (status in ('Open', 'Assigned', 'In Progress', 'Closed - Resolved')),
  created_by text,
  assigned_to uuid references public.staff (id) on delete set null,
  helpers uuid[] not null default '{}',
  notes text,
  materials text,
  resolved_at timestamptz,
  resolved_by text,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ops_tickets_no_uidx on public.ops_tickets (ticket_no);
create index if not exists ops_tickets_assigned_idx on public.ops_tickets (assigned_to, status);
create index if not exists ops_tickets_customer_idx on public.ops_tickets (customer_id);

alter table public.expenses add column if not exists ticket_id uuid references public.ops_tickets (id) on delete set null;
create index if not exists expenses_ticket_idx on public.expenses (ticket_id);

create table if not exists public.ticket_notes (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.ops_tickets (id) on delete cascade,
  body text not null,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists ticket_notes_ticket_idx on public.ticket_notes (ticket_id, created_at);

create table if not exists public.material_prices (
  item text primary key,
  unit_cost numeric(12, 2),
  updated_at timestamptz not null default now()
);

insert into public.material_prices (item, unit_cost) values
  ('SC Connector', 28),
  ('Changed Modem', null),
  ('Rewiring', null),
  ('Changed power adaptor', null)
on conflict (item) do nothing;

create table if not exists public.ticket_materials (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.ops_tickets (id) on delete cascade,
  item text not null check (item in (
    'SC Connector', 'Changed Modem', 'Rewiring', 'Changed power adaptor', 'other'
  )),
  qty numeric(12, 2) not null default 1 check (qty > 0),
  unit_cost numeric(12, 2),
  created_at timestamptz not null default now()
);

create index if not exists ticket_materials_ticket_idx on public.ticket_materials (ticket_id);

create table if not exists public.ticket_photos (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.ops_tickets (id) on delete cascade,
  path text not null,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists ticket_photos_ticket_idx on public.ticket_photos (ticket_id);

insert into public.app_settings (key, value, is_public) values
  ('ticket_issues', E'No internet\nSlow connection\nLOS red light\nModem no power\nIntermittent\nChange plan\nPullout\nOthers', false)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Modems
-- ---------------------------------------------------------------------------

create table if not exists public.modems (
  id uuid primary key default gen_random_uuid(),
  serial text not null,
  mac text,
  brand text not null check (brand in ('IOT', 'SKYWORTH', 'HUAWEI', 'ZTE', 'FIBER HOME')),
  modem_type text not null check (modem_type in ('GPON', 'GPON 5V5', 'GPON 1V5', 'XPON', 'EPON')),
  condition text not null default '100% Working' check (condition in ('100% Working', 'Faulty')),
  availability text not null default 'Available' check (availability in ('Available', 'In Used')),
  customer_id uuid references public.customers (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists modems_serial_uidx on public.modems (lower(serial));

create table if not exists public.modem_pullouts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  modem_id uuid references public.modems (id) on delete set null,
  pull_type text not null check (pull_type in ('Disconnection', 'Changed Modem')),
  return_fee numeric(12, 2) not null default 0 check (return_fee in (0, 290, 300)),
  pulled_on date not null default current_date,
  pulled_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.modem_log (
  id uuid primary key default gen_random_uuid(),
  modem_id uuid not null references public.modems (id) on delete cascade,
  action text not null,
  customer_id uuid references public.customers (id) on delete set null,
  note text,
  actor text,
  created_at timestamptz not null default now()
);

create index if not exists modem_log_modem_idx on public.modem_log (modem_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Ticket helpers
-- ---------------------------------------------------------------------------

create or replace function public.ops_actor()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(auth.jwt() ->> 'email', ''), 'system');
$$;

create or replace function public.account_code_for(p_customer uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(upper(btrim(i.code)), ''),
    nullif(substring(upper(coalesce(c.account_number, '')) from 'FBRO([A-Z]{2})'), ''),
    nullif(substring(upper(coalesce(c.account_number, '')) from '^([A-Z]+)'), ''),
    'XX'
  )
  from public.customers c
  left join public.investors i on i.id = c.investor_id
  where c.id = p_customer;
$$;

create or replace function public.ticket_visible_to_caller(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1
    from public.ops_tickets t
    where t.id = p_ticket
      and public.is_tech()
      and (
        t.assigned_to = public.current_staff_id()
        or t.helpers @> array[public.current_staff_id()]
      )
  );
$$;

create or replace function public.ops_tickets_before()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.ticket_no is null or btrim(new.ticket_no) = '' then
      new.ticket_no := new.ticket_type || upper(substring(encode(extensions.gen_random_bytes(4), 'hex') from 1 for 7));
    end if;
    if new.created_by is null then
      new.created_by := public.ops_actor();
    end if;
  else
    if public.is_tech() and not public.is_admin() then
      new.assigned_to := old.assigned_to;
      new.helpers := old.helpers;
      new.customer_id := old.customer_id;
      new.ticket_no := old.ticket_no;
      new.ticket_type := old.ticket_type;
      new.created_by := old.created_by;
    end if;
  end if;

  if new.assigned_to is not null and new.status = 'Open' then
    new.status := 'Assigned';
  end if;
  if new.status = 'Closed - Resolved' and (tg_op = 'INSERT' or old.status is distinct from 'Closed - Resolved') then
    new.resolved_at := coalesce(new.resolved_at, now());
    new.resolved_by := coalesce(nullif(new.resolved_by, ''), public.ops_actor());
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ops_tickets_before on public.ops_tickets;
create trigger ops_tickets_before
  before insert or update on public.ops_tickets
  for each row execute function public.ops_tickets_before();

create or replace function public.post_ticket_expenses(p_ticket uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  tix public.ops_tickets%rowtype;
  mat record;
  price numeric;
  code text;
  made integer := 0;
begin
  select * into tix from public.ops_tickets where id = p_ticket;
  if tix.id is null or tix.status is distinct from 'Closed - Resolved' then
    return 0;
  end if;
  code := public.account_code_for(tix.customer_id);
  for mat in
    select * from public.ticket_materials
    where ticket_id = tix.id
      and item in ('SC Connector', 'Changed Modem', 'Rewiring', 'Changed power adaptor')
  loop
    price := mat.unit_cost;
    if price is null then
      select unit_cost into price from public.material_prices where item = mat.item;
    end if;
    if price is null then
      continue;
    end if;
    if exists (
      select 1 from public.expenses
      where ticket_id = tix.id and scope = mat.item and auto
    ) then
      continue;
    end if;
    insert into public.expenses (
      category, amount, expense_date, remarks, status, created_by,
      account_code, scope, ticket_id, auto
    ) values (
      'Operational',
      round(mat.qty * price, 2),
      current_date,
      'Auto from ' || tix.ticket_no || ' · ' || mat.item,
      'pending',
      public.ops_actor(),
      code,
      mat.item,
      tix.id,
      true
    );
    made := made + 1;
  end loop;
  return made;
end;
$$;

create or replace function public.ops_tickets_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'Closed - Resolved' and (tg_op = 'INSERT' or old.status is distinct from 'Closed - Resolved') then
    perform public.post_ticket_expenses(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists ops_tickets_after on public.ops_tickets;
create trigger ops_tickets_after
  after insert or update of status on public.ops_tickets
  for each row execute function public.ops_tickets_after();

create or replace function public.modems_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.serial := btrim(new.serial);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists modems_touch on public.modems;
create trigger modems_touch
  before insert or update of serial on public.modems
  for each row execute function public.modems_touch();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.intake_new_client(
  p_name text,
  p_mobile text,
  p_location text,
  p_referral_source text,
  p_referral_type text,
  p_referral_name text,
  p_consent boolean,
  p_investor uuid,
  p_plan text,
  p_address text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust uuid;
  tix uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can encode a new client.';
  end if;
  if coalesce(p_consent, false) is not true then
    raise exception 'Data privacy consent is required.';
  end if;
  if p_location is not null and p_location not in ('Payatas', 'Maligaya', 'Pampanga') then
    raise exception 'Location must be Payatas, Maligaya, or Pampanga.';
  end if;
  insert into public.customers (
    name, mobile, contact_number, source, investor_id, plan, address,
    service_location, referral_source, referral_type, referral_name, privacy_consent
  ) values (
    nullif(btrim(p_name), ''),
    nullif(btrim(p_mobile), ''),
    nullif(btrim(p_mobile), ''),
    'admin',
    p_investor,
    nullif(btrim(p_plan), ''),
    nullif(btrim(p_address), ''),
    nullif(btrim(p_location), ''),
    nullif(btrim(p_referral_source), ''),
    nullif(btrim(p_referral_type), ''),
    nullif(btrim(p_referral_name), ''),
    true
  )
  returning id into cust;

  insert into public.ops_tickets (ticket_type, customer_id, issue, status, created_by)
  values ('INSTALLATION', cust, 'New installation', 'Open', public.ops_actor())
  returning id into tix;

  return json_build_object('ok', true, 'customer_id', cust, 'ticket_id', tix);
end;
$$;

create or replace function public.resolve_ops_ticket(p_ticket uuid, p_resolution text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  made integer;
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot close this ticket.';
  end if;
  update public.ops_tickets
  set status = 'Closed - Resolved',
      resolution = coalesce(nullif(btrim(p_resolution), ''), resolution)
  where id = p_ticket;
  made := public.post_ticket_expenses(p_ticket);
  return json_build_object('ok', true, 'expenses', made);
end;
$$;

create or replace function public.complete_installation(
  p_ticket uuid,
  p_lp text,
  p_nap text,
  p_port text,
  p_modem_serial text,
  p_pay_method text,
  p_pay_amount numeric,
  p_pay_ref text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  tix public.ops_tickets%rowtype;
  cust public.customers%rowtype;
  pppoe text;
  digits text;
  fee numeric;
  method text;
  inv uuid;
  period text;
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot complete this installation.';
  end if;
  select * into tix from public.ops_tickets where id = p_ticket;
  if tix.id is null then
    raise exception 'Ticket not found.';
  end if;
  if tix.ticket_type is distinct from 'INSTALLATION' then
    raise exception 'This ticket is not an installation.';
  end if;
  if tix.customer_id is null then
    raise exception 'Assign a customer first.';
  end if;
  if tix.status = 'Closed - Resolved' then
    return json_build_object('ok', true, 'already', true, 'customer_id', tix.customer_id);
  end if;
  select * into cust from public.customers where id = tix.customer_id;
  if cust.investor_id is null then
    raise exception 'Assign an investor before completing the installation.';
  end if;

  if nullif(btrim(cust.pppoe), '') is not null then
    pppoe := btrim(cust.pppoe);
  else
    digits := nullif(right(regexp_replace(coalesce(cust.account_number, ''), '\D', '', 'g'), 6), '');
    if digits is not null then
      pppoe := 'fb' || digits;
    else
      pppoe := 'fb' || substring(encode(extensions.gen_random_bytes(3), 'hex') from 1 for 6);
    end if;
  end if;

  perform set_config('fiberbro.allow_stage_jump', '1', true);
  update public.customers
  set stage = 'active',
      account_status = 'Newly Installed',
      pppoe = pppoe,
      lp = coalesce(nullif(btrim(p_lp), ''), lp),
      nap = coalesce(nullif(btrim(p_nap), ''), nap),
      port = coalesce(nullif(btrim(p_port), ''), port),
      modem_serial = coalesce(nullif(btrim(p_modem_serial), ''), modem_serial),
      installation_date = coalesce(installation_date, current_date),
      installation_status = 'Done',
      installed_by = public.ops_actor()
  where id = cust.id;

  if nullif(btrim(p_modem_serial), '') is not null then
    update public.modems
    set customer_id = cust.id,
        availability = 'In Used'
    where lower(serial) = lower(btrim(p_modem_serial));
    insert into public.modem_log (modem_id, action, customer_id, note, actor)
    select id, 'Assigned', cust.id, 'Installation ' || tix.ticket_no, public.ops_actor()
    from public.modems
    where lower(serial) = lower(btrim(p_modem_serial));
  end if;

  method := lower(btrim(coalesce(p_pay_method, '')));
  if method = 'gcash' then
    method := 'gcash';
  elsif method = 'cash' then
    method := 'cash';
  else
    method := '';
  end if;
  fee := p_pay_amount;
  if coalesce(fee, 0) <= 0 then
    select nullif(value, '')::numeric into fee
    from public.app_settings where key = 'installation_fee';
  end if;
  if method <> '' and coalesce(fee, 0) > 0 then
    period := to_char(current_date, 'YYYY-MM');
    insert into public.invoices (customer_id, period, amount, due_date, status, notes, created_by, invoice_kind)
    values (cust.id, period, fee, current_date, 'unpaid', 'Installation fee', public.ops_actor(), 'installation')
    on conflict (customer_id, period, invoice_kind) do update
      set amount = excluded.amount
    returning id into inv;
    insert into public.payments (
      invoice_id, customer_id, amount, method, reference_no, status, source, notes
    ) values (
      inv, cust.id, fee, method, nullif(btrim(p_pay_ref), ''), 'confirmed', 'admin', 'Installation fee'
    );
  end if;

  update public.ops_tickets
  set status = 'Closed - Resolved',
      resolution = coalesce(resolution, 'Installed')
  where id = tix.id;

  return json_build_object('ok', true, 'customer_id', cust.id, 'pppoe', pppoe, 'amount', fee);
end;
$$;

create or replace function public.tech_my_work()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := public.current_staff_id();
begin
  if not (public.is_admin() or public.is_tech()) then
    raise exception 'Only a tech or an admin can open this list.';
  end if;
  return json_build_object(
    'duty_status', (select duty_status from public.staff where id = me),
    'staff_id', me,
    'tickets', coalesce((
      select json_agg(json_build_object(
        'id', t.id,
        'ticket_no', t.ticket_no,
        'ticket_type', t.ticket_type,
        'issue', t.issue,
        'status', t.status,
        'notes', t.notes,
        'resolution', t.resolution,
        'customer_id', t.customer_id,
        'customer_name', c.name,
        'account_number', c.account_number,
        'address', c.address,
        'area', c.area,
        'mobile', coalesce(c.mobile, c.contact_number),
        'lp', c.lp,
        'nap', c.nap,
        'port', c.port,
        'materials', coalesce((
          select json_agg(json_build_object('id', m.id, 'item', m.item, 'qty', m.qty, 'unit_cost', m.unit_cost))
          from public.ticket_materials m where m.ticket_id = t.id
        ), '[]'::json),
        'notes_log', coalesce((
          select json_agg(json_build_object('id', n.id, 'body', n.body, 'created_by', n.created_by, 'created_at', n.created_at) order by n.created_at)
          from public.ticket_notes n where n.ticket_id = t.id
        ), '[]'::json),
        'photos', coalesce((
          select json_agg(json_build_object('id', p.id, 'path', p.path))
          from public.ticket_photos p where p.ticket_id = t.id
        ), '[]'::json)
      ) order by t.created_at desc)
      from public.ops_tickets t
      left join public.customers c on c.id = t.customer_id
      where public.is_admin()
         or t.assigned_to = me
         or t.helpers @> array[me]
    ), '[]'::json)
  );
end;
$$;

create or replace function public.tech_set_duty(p_status text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_tech() then
    raise exception 'Only a tech can set duty status.';
  end if;
  if p_status not in ('Available', 'On job', 'Off') then
    raise exception 'Status must be Available, On job, or Off.';
  end if;
  update public.staff set duty_status = p_status where id = public.current_staff_id();
  return json_build_object('ok', true, 'duty_status', p_status);
end;
$$;

create or replace function public.tech_add_note(p_ticket uuid, p_body text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot add a note on this ticket.';
  end if;
  if nullif(btrim(p_body), '') is null then
    raise exception 'Write a note first.';
  end if;
  insert into public.ticket_notes (ticket_id, body, created_by)
  values (p_ticket, btrim(p_body), public.ops_actor());
  return json_build_object('ok', true);
end;
$$;

create or replace function public.tech_add_material(p_ticket uuid, p_item text, p_qty numeric)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  price numeric;
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot add materials on this ticket.';
  end if;
  if p_item not in ('SC Connector', 'Changed Modem', 'Rewiring', 'Changed power adaptor', 'other') then
    raise exception 'Unknown material.';
  end if;
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'Quantity must be more than zero.';
  end if;
  select unit_cost into price from public.material_prices where item = p_item;
  insert into public.ticket_materials (ticket_id, item, qty, unit_cost)
  values (p_ticket, p_item, p_qty, price);
  return json_build_object('ok', true);
end;
$$;

create or replace function public.tech_set_status(p_ticket uuid, p_status text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot update this ticket.';
  end if;
  if p_status not in ('Open', 'Assigned', 'In Progress', 'Closed - Resolved') then
    raise exception 'Unknown status.';
  end if;
  update public.ops_tickets set status = p_status where id = p_ticket;
  return json_build_object('ok', true);
end;
$$;

create or replace function public.modem_pullout(
  p_modem uuid,
  p_customer uuid,
  p_type text,
  p_fee numeric,
  p_date date
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can record a pullout.';
  end if;
  if p_type not in ('Disconnection', 'Changed Modem') then
    raise exception 'Type must be Disconnection or Changed Modem.';
  end if;
  if coalesce(p_fee, 0) not in (0, 290, 300) then
    raise exception 'Return fee must be 0, 290, or 300.';
  end if;
  insert into public.modem_pullouts (customer_id, modem_id, pull_type, return_fee, pulled_on, pulled_by)
  values (p_customer, p_modem, p_type, coalesce(p_fee, 0), coalesce(p_date, current_date), public.ops_actor());
  update public.modems
  set customer_id = null,
      availability = 'Available'
  where id = p_modem;
  insert into public.modem_log (modem_id, action, customer_id, note, actor)
  values (p_modem, p_type, p_customer, 'Return fee ' || coalesce(p_fee, 0)::text, public.ops_actor());
  return json_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS. Admins manage everything. Techs see and update only their tickets.
-- ---------------------------------------------------------------------------

alter table public.staff enable row level security;
alter table public.ops_tickets enable row level security;
alter table public.ticket_notes enable row level security;
alter table public.ticket_materials enable row level security;
alter table public.ticket_photos enable row level security;
alter table public.material_prices enable row level security;
alter table public.modems enable row level security;
alter table public.modem_pullouts enable row level security;
alter table public.modem_log enable row level security;

revoke all on table public.staff from public, anon;
revoke all on table public.ops_tickets from public, anon;
revoke all on table public.ticket_notes from public, anon;
revoke all on table public.ticket_materials from public, anon;
revoke all on table public.ticket_photos from public, anon;
revoke all on table public.material_prices from public, anon;
revoke all on table public.modems from public, anon;
revoke all on table public.modem_pullouts from public, anon;
revoke all on table public.modem_log from public, anon;

grant select, insert, update, delete on public.staff to authenticated;
grant select, insert, update, delete on public.ops_tickets to authenticated;
grant select, insert, update, delete on public.ticket_notes to authenticated;
grant select, insert, update, delete on public.ticket_materials to authenticated;
grant select, insert, update, delete on public.ticket_photos to authenticated;
grant select, insert, update, delete on public.material_prices to authenticated;
grant select, insert, update, delete on public.modems to authenticated;
grant select, insert, update, delete on public.modem_pullouts to authenticated;
grant select, insert, update, delete on public.modem_log to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'staff' and policyname = 'staff_admin_all') then
    create policy staff_admin_all on public.staff for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'staff' and policyname = 'staff_tech_self') then
    create policy staff_tech_self on public.staff for select to authenticated
      using (public.is_tech() and id = public.current_staff_id());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_tickets' and policyname = 'ops_tickets_admin_all') then
    create policy ops_tickets_admin_all on public.ops_tickets for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_tickets' and policyname = 'ops_tickets_tech_select') then
    create policy ops_tickets_tech_select on public.ops_tickets for select to authenticated
      using (
        public.is_tech() and (
          assigned_to = public.current_staff_id()
          or helpers @> array[public.current_staff_id()]
        )
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_tickets' and policyname = 'ops_tickets_tech_update') then
    create policy ops_tickets_tech_update on public.ops_tickets for update to authenticated
      using (
        public.is_tech() and (
          assigned_to = public.current_staff_id()
          or helpers @> array[public.current_staff_id()]
        )
      )
      with check (
        public.is_tech() and (
          assigned_to = public.current_staff_id()
          or helpers @> array[public.current_staff_id()]
        )
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_notes' and policyname = 'ticket_notes_admin_all') then
    create policy ticket_notes_admin_all on public.ticket_notes for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_notes' and policyname = 'ticket_notes_tech_select') then
    create policy ticket_notes_tech_select on public.ticket_notes for select to authenticated
      using (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_notes' and policyname = 'ticket_notes_tech_insert') then
    create policy ticket_notes_tech_insert on public.ticket_notes for insert to authenticated
      with check (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_materials' and policyname = 'ticket_materials_admin_all') then
    create policy ticket_materials_admin_all on public.ticket_materials for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_materials' and policyname = 'ticket_materials_tech_select') then
    create policy ticket_materials_tech_select on public.ticket_materials for select to authenticated
      using (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_materials' and policyname = 'ticket_materials_tech_insert') then
    create policy ticket_materials_tech_insert on public.ticket_materials for insert to authenticated
      with check (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_photos' and policyname = 'ticket_photos_admin_all') then
    create policy ticket_photos_admin_all on public.ticket_photos for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_photos' and policyname = 'ticket_photos_tech_select') then
    create policy ticket_photos_tech_select on public.ticket_photos for select to authenticated
      using (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ticket_photos' and policyname = 'ticket_photos_tech_insert') then
    create policy ticket_photos_tech_insert on public.ticket_photos for insert to authenticated
      with check (public.ticket_visible_to_caller(ticket_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'material_prices' and policyname = 'material_prices_admin_all') then
    create policy material_prices_admin_all on public.material_prices for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modems' and policyname = 'modems_admin_all') then
    create policy modems_admin_all on public.modems for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modem_pullouts' and policyname = 'modem_pullouts_admin_all') then
    create policy modem_pullouts_admin_all on public.modem_pullouts for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modem_log' and policyname = 'modem_log_admin_all') then
    create policy modem_log_admin_all on public.modem_log for all to authenticated
      using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ticket-photos',
  'ticket-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'ticket_photos_admin_read'
  ) then
    create policy ticket_photos_admin_read on storage.objects
      for select to authenticated
      using (bucket_id = 'ticket-photos' and public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'ticket_photos_admin_insert'
  ) then
    create policy ticket_photos_admin_insert on storage.objects
      for insert to authenticated
      with check (bucket_id = 'ticket-photos' and public.is_admin() and name ~ '^tickets/.+');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'ticket_photos_admin_delete'
  ) then
    create policy ticket_photos_admin_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'ticket-photos' and public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'ticket_photos_tech_read'
  ) then
    create policy ticket_photos_tech_read on storage.objects
      for select to authenticated
      using (
        bucket_id = 'ticket-photos'
        and public.is_tech()
        and name ~ '^tickets/[0-9a-fA-F-]{36}/'
        and public.ticket_visible_to_caller(substring(name from 'tickets/([0-9a-fA-F-]{36})')::uuid)
      );
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'ticket_photos_tech_insert'
  ) then
    create policy ticket_photos_tech_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'ticket-photos'
        and public.is_tech()
        and name ~ '^tickets/[0-9a-fA-F-]{36}/.+'
        and public.ticket_visible_to_caller(substring(name from 'tickets/([0-9a-fA-F-]{36})')::uuid)
      );
  end if;
end $$;

-- Supabase grants execute on new public functions to anon and authenticated.
revoke execute on function
  public.normalize_gcash_ref(text),
  public.collection_cutoff(date),
  public.clamp_due_date(integer, integer, integer),
  public.staff_normalize(),
  public.current_staff_id(),
  public.ops_actor(),
  public.account_code_for(uuid),
  public.ticket_visible_to_caller(uuid),
  public.ops_tickets_before(),
  public.ops_tickets_after(),
  public.post_ticket_expenses(uuid),
  public.modems_touch()
  from public, anon, authenticated;

revoke execute on function
  public.is_tech(),
  public.intake_new_client(text, text, text, text, text, text, boolean, uuid, text, text),
  public.resolve_ops_ticket(uuid, text),
  public.complete_installation(uuid, text, text, text, text, text, numeric, text),
  public.tech_my_work(),
  public.tech_set_duty(text),
  public.tech_add_note(uuid, text),
  public.tech_add_material(uuid, text, numeric),
  public.tech_set_status(uuid, text),
  public.modem_pullout(uuid, uuid, text, numeric, date)
  from public, anon;

grant execute on function public.is_tech() to authenticated;
grant execute on function public.current_staff_id() to authenticated;
grant execute on function public.ticket_visible_to_caller(uuid) to authenticated;
grant execute on function public.intake_new_client(text, text, text, text, text, text, boolean, uuid, text, text) to authenticated;
grant execute on function public.resolve_ops_ticket(uuid, text) to authenticated;
grant execute on function public.complete_installation(uuid, text, text, text, text, text, numeric, text) to authenticated;
grant execute on function public.tech_my_work() to authenticated;
grant execute on function public.tech_set_duty(text) to authenticated;
grant execute on function public.tech_add_note(uuid, text) to authenticated;
grant execute on function public.tech_add_material(uuid, text, numeric) to authenticated;
grant execute on function public.tech_set_status(uuid, text) to authenticated;
grant execute on function public.modem_pullout(uuid, uuid, text, numeric, date) to authenticated;
