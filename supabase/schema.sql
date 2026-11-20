-- FiberBro admin schema
-- Paste this whole file into the Supabase SQL editor and run it once.
-- Safe to re-run: policies and triggers are dropped and recreated.
--
-- Access model
--   * Google sign-in is Supabase Auth. Being signed in is not enough.
--   * public.admins is the allowlist. RLS allows a row only when the JWT email is in that table.
--   * The public website may INSERT an inquiry (stage 1) and nothing else.
--   * anon cannot SELECT or UPDATE customers.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.normalize_admin_email()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.email = lower(btrim(new.email));
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  created_at timestamptz not null default now()
);

-- Depends on public.admins, so it is created after that table.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- No seed rows. Add investors from the portal after this script runs.
create table if not exists public.investors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  areas text[] not null default '{}',
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.investors add column if not exists code text;

create unique index if not exists investors_code_key on public.investors (upper(code)) where code is not null;

create table if not exists public.technicians (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mobile text,
  email text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),

  -- Pipeline. Text plus a check constraint, not a Postgres enum.
  -- Allowed values, in order: inquiry, in_progress, encoded, active.
  stage text not null default 'inquiry'
    check (stage in ('inquiry', 'in_progress', 'encoded', 'active')),
  source text not null default 'website'
    check (source in ('website', 'admin')),

  -- Website inquiry
  first_name text,
  last_name text,
  middle_initial text,
  birth_date date,
  mobile text,
  email text,
  facebook_name text,
  valid_id_type text,
  valid_id_drive_url text,
  valid_id_path text,
  plan text,
  preferred_install_date date,
  referred_by text,

  -- Master list. "Referral" is investor_id, not a free-text column.
  account_number text,
  portal_pin_hash text,
  portal_enabled boolean not null default false,
  failed_login_count integer not null default 0,
  locked_until timestamptz,
  account_status text,
  name text,
  messenger text,
  contact_number text,
  fb_account text,
  address text,
  area text,
  landmark text,
  landmark_picture_url text,
  pin_loc text,
  sub_area text,
  lp text,
  nap text,
  port text,
  pppoe text,
  latitude double precision,
  longitude double precision,
  installed_by text,
  installation_status text,
  installation_date date,
  installation_remarks text,
  plan_speed text,
  plan_split text, -- unused
  price numeric(12, 2),
  plan_status text,
  plan_type text check (plan_type is null or plan_type in ('Basic', 'Plus', 'Max')),
  investor_id uuid references public.investors (id) on delete restrict,
  due_date_number integer,
  original_due_date date,
  monthly_bill numeric(12, 2),
  current_bill numeric(12, 2),
  total_payment numeric(12, 2),
  total_balance numeric(12, 2),
  balance_status text,
  current_month_year_bill text,
  prev_month_year_bill text,
  previous_month_balance numeric(12, 2),
  previous_month_payment numeric(12, 2),
  bill_generation date,
  current_due_date date,
  bill_trigger text,
  assigned_name text,
  assigned_email text,
  payment_collection_status text,
  collection_timestamp timestamptz,
  collection_date date,
  promissory_status text,
  promissory_clearance text,
  master_collection_timestamp timestamptz,
  gcash text,
  for_disconnection boolean not null default false,
  reminder text,
  payment_mode text,
  modem_brand text,
  modem_type text,
  mac_address text,
  description text,
  modem_picture_front_url text,
  modem_picture_back_url text,
  email_address text,
  lap_nap_picture_url text,
  port_picture_url text,
  house_picture_url text,
  acknowledgement_slip_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.customers (id) on delete cascade,
  technician_id uuid references public.technicians (id) on delete restrict,
  status text not null default 'open' check (status in ('open', 'assigned', 'closed')),
  assigned_at timestamptz,
  assigned_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.customer_stage_events (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  stage text not null,
  changed_by text not null,
  changed_at timestamptz not null default now()
);

create table if not exists public.customer_change_log (
  id bigint generated always as identity primary key,
  customer_id uuid not null references public.customers (id) on delete cascade,
  action text not null check (action in ('created', 'updated')),
  field text,
  old_value text,
  new_value text,
  changed_by text not null,
  changed_at timestamptz not null default now()
);

create index if not exists customer_change_log_customer_idx
  on public.customer_change_log (customer_id, changed_at);

-- Replace an older stage check (activated / ticket_assigned) when this script is re-run.
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
      and pg_get_constraintdef(con.oid) ilike '%inquiry%'
      and pg_get_constraintdef(con.oid) ilike '%stage%'
  loop
    execute format('alter table public.customers drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.customers add constraint customers_stage_check
  check (stage in ('inquiry', 'in_progress', 'encoded', 'active'));

create index if not exists customers_stage_idx on public.customers (stage);
create index if not exists customers_area_idx on public.customers (area);
create index if not exists customers_created_idx on public.customers (created_at desc);
create index if not exists customers_investor_idx on public.customers (investor_id);
create index if not exists tickets_technician_idx on public.tickets (technician_id);
create index if not exists stage_events_customer_idx on public.customer_stage_events (customer_id, changed_at);

-- ---------------------------------------------------------------------------
-- Stage rules
-- ---------------------------------------------------------------------------

create or replace function public.stage_label(p_stage text)
returns text
language sql
immutable
as $$
  select case p_stage
    when 'inquiry' then 'Inquiry'
    when 'in_progress' then 'In Progress'
    when 'encoded' then 'Encoded'
    when 'active' then 'Active'
    else p_stage
  end;
$$;

create or replace function public.next_account_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n bigint;
begin
  perform pg_advisory_xact_lock(hashtext('fiberbro_account_number'));
  select coalesce(max(account_number::bigint), 0) + 1
    into n
  from public.customers
  where account_number ~ '^[0-9]+$';
  return n::text;
end;
$$;

create or replace function public.customers_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'anon' then
    new.source := 'website';
    new.investor_id := null;
  elsif new.source is null or new.source not in ('website', 'admin') then
    new.source := 'admin';
  end if;

  if new.investor_id is not null then
    new.stage := 'in_progress';
  else
    new.stage := 'inquiry';
  end if;

  new.email_address := coalesce(new.email_address, new.email);
  new.fb_account := coalesce(new.fb_account, new.facebook_name);

  if new.account_number is null or btrim(new.account_number) = '' then
    new.account_number := public.next_account_number();
  end if;

  new.account_status := public.stage_label(new.stage);
  return new;
end;
$$;

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

    if not (
      (old.stage = 'inquiry' and new.stage = 'in_progress')
      or (old.stage = 'in_progress' and new.stage = 'inquiry')
    ) and new_n <> old_n + 1 then
      raise exception 'Cannot move from % to %. Complete the previous stage first.', old.stage, new.stage;
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

  new.account_status := public.stage_label(new.stage);
  new.email_address := coalesce(new.email_address, new.email);
  new.fb_account := coalesce(new.fb_account, new.facebook_name);
  return new;
end;
$$;

create or replace function public.log_customer_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.customer_stage_events (customer_id, stage, changed_by)
  values (
    new.id,
    new.stage,
    coalesce(nullif(auth.jwt() ->> 'email', ''), 'website')
  );
  return new;
end;
$$;

create or replace function public.create_ticket_on_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stage = 'active' and old.stage is distinct from 'active' then
    insert into public.tickets (customer_id, status)
    select new.id, 'open'
    where not exists (
      select 1 from public.tickets where customer_id = new.id
    );
  end if;
  return new;
end;
$$;

create or replace function public.guard_ticket_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cust_stage text;
begin
  if new.technician_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.technician_id is not distinct from old.technician_id then
    return new;
  end if;

  select stage into cust_stage from public.customers where id = new.customer_id;
  if cust_stage is distinct from 'active' then
    raise exception 'A technician can be assigned only when the customer is active.';
  end if;

  new.status := 'assigned';
  new.assigned_at := coalesce(new.assigned_at, now());
  if new.assigned_by is null or btrim(new.assigned_by) = '' then
    new.assigned_by := nullif(auth.jwt() ->> 'email', '');
  end if;
  return new;
end;
$$;

create or replace function public.advance_stage_when_ticket_assigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Ticket assignment no longer changes the customer stage.
  return new;
end;
$$;

drop trigger if exists admins_normalize_email on public.admins;
create trigger admins_normalize_email
  before insert or update on public.admins
  for each row execute function public.normalize_admin_email();

drop trigger if exists investors_set_updated_at on public.investors;
create trigger investors_set_updated_at
  before update on public.investors
  for each row execute function public.set_updated_at();

drop trigger if exists technicians_set_updated_at on public.technicians;
create trigger technicians_set_updated_at
  before update on public.technicians
  for each row execute function public.set_updated_at();

create or replace function public.fill_plan_details()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  speed text;
  normalized text;
begin
  if new.plan_speed is null or btrim(new.plan_speed) = '' then
    if new.plan is not null and btrim(new.plan) <> '' then
      speed := btrim((regexp_match(new.plan, '^[[:space:]]*([0-9]+[[:space:]]*(?:–|-)[[:space:]]*[0-9]+[[:space:]]*Mbps)'))[1]);
      if speed is not null then
        new.plan_speed := regexp_replace(
          regexp_replace(speed, '[[:space:]]*(?:–|-)[[:space:]]*', '–'),
          '[[:space:]]+',
          ' ',
          'g'
        );
      end if;
    end if;
  end if;

  normalized := btrim(coalesce(new.plan_speed, ''));
  normalized := regexp_replace(
    regexp_replace(normalized, '[[:space:]]*(?:–|-)[[:space:]]*', '–'),
    '[[:space:]]+',
    ' ',
    'g'
  );

  -- Known speeds always own price and plan type.
  if normalized = '75–150 Mbps' then
    new.price := 1000;
    new.plan_type := 'Basic';
  elsif normalized = '150–200 Mbps' then
    new.price := 1200;
    new.plan_type := 'Plus';
  elsif normalized = '200–300 Mbps' then
    new.price := 1400;
    new.plan_type := 'Max';
  end if;

  return new;
end;
$$;

drop trigger if exists customers_fill_plan_details on public.customers;
create trigger customers_fill_plan_details
  before insert or update on public.customers
  for each row execute function public.fill_plan_details();

drop trigger if exists customers_set_updated_at on public.customers;
create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

drop trigger if exists customers_before_insert on public.customers;
create trigger customers_before_insert
  before insert on public.customers
  for each row execute function public.customers_before_insert();

drop trigger if exists customers_enforce_stage on public.customers;
create trigger customers_enforce_stage
  before update on public.customers
  for each row execute function public.enforce_customer_stage();

drop trigger if exists customers_log_insert on public.customers;
create trigger customers_log_insert
  after insert on public.customers
  for each row execute function public.log_customer_insert();

create or replace function public.log_customer_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor text;
  col text;
  old_json jsonb;
  new_json jsonb;
begin
  actor := coalesce(nullif(auth.jwt() ->> 'email', ''), 'website');

  if tg_op = 'INSERT' then
    insert into public.customer_change_log (customer_id, action, changed_by)
    values (new.id, 'created', actor);
    return new;
  end if;

  old_json := to_jsonb(old);
  new_json := to_jsonb(new);
  for col in select jsonb_object_keys(new_json)
  loop
    if col in ('created_at', 'updated_at', 'portal_pin_hash', 'failed_login_count', 'locked_until') then
      continue;
    end if;
    if (old_json -> col) is distinct from (new_json -> col) then
      insert into public.customer_change_log (
        customer_id, action, field, old_value, new_value, changed_by
      ) values (
        new.id,
        'updated',
        col,
        old_json ->> col,
        new_json ->> col,
        actor
      );
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists customers_change_log on public.customers;
create trigger customers_change_log
  after insert or update on public.customers
  for each row execute function public.log_customer_changes();

drop trigger if exists customers_ticket_on_activation on public.customers;
create trigger customers_ticket_on_activation
  after update on public.customers
  for each row execute function public.create_ticket_on_activation();

drop trigger if exists tickets_guard_assignment on public.tickets;
create trigger tickets_guard_assignment
  before insert or update on public.tickets
  for each row execute function public.guard_ticket_assignment();

drop trigger if exists tickets_advance_stage on public.tickets;
create trigger tickets_advance_stage
  after insert or update on public.tickets
  for each row execute function public.advance_stage_when_ticket_assigned();

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;

revoke all on public.admins, public.investors, public.technicians,
  public.customers, public.tickets, public.customer_stage_events, public.customer_change_log
  from anon, authenticated;

grant select, insert, update, delete on public.admins to authenticated;
grant select, insert, update, delete on public.investors to authenticated;
grant select, insert, update, delete on public.technicians to authenticated;
grant select, insert, update, delete on public.customers to authenticated;
grant select, insert, update on public.tickets to authenticated;
grant select on public.customer_stage_events to authenticated;
grant select on public.customer_change_log to authenticated;

-- Website: inquiry columns only. Stage and source are forced by the insert trigger.
grant insert (
  first_name,
  last_name,
  middle_initial,
  birth_date,
  mobile,
  contact_number,
  email,
  facebook_name,
  address,
  landmark,
  valid_id_type,
  valid_id_path,
  plan,
  plan_split,
  price,
  preferred_install_date,
  referred_by,
  name,
  source
) on public.customers to anon;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.admins enable row level security;
alter table public.investors enable row level security;
alter table public.technicians enable row level security;
alter table public.customers enable row level security;
alter table public.tickets enable row level security;
alter table public.customer_stage_events enable row level security;
alter table public.customer_change_log enable row level security;

drop policy if exists admins_all on public.admins;
create policy admins_all on public.admins
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists investors_all on public.investors;
create policy investors_all on public.investors
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists technicians_all on public.technicians;
create policy technicians_all on public.technicians
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists customers_admin_all on public.customers;
create policy customers_admin_all on public.customers
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists customers_anon_insert on public.customers;
create policy customers_anon_insert on public.customers
  for insert to anon
  with check (
    stage = 'inquiry'
    and source = 'website'
    and investor_id is null
    and account_number ~ '^[0-9]+$'
    and valid_id_drive_url is null
    and (valid_id_path is null or valid_id_path ~ '^inquiries/[A-Za-z0-9._-]+$')
    and char_length(coalesce(name, '')) <= 300
    and char_length(coalesce(address, '')) <= 2000
    and char_length(coalesce(landmark, '')) <= 1000
    and char_length(coalesce(mobile, '')) <= 30
  );

drop policy if exists tickets_admin_select on public.tickets;
create policy tickets_admin_select on public.tickets
  for select to authenticated
  using (public.is_admin());

drop policy if exists tickets_admin_insert on public.tickets;
create policy tickets_admin_insert on public.tickets
  for insert to authenticated
  with check (
    public.is_admin()
    and exists (
      select 1 from public.customers c
      where c.id = customer_id
        and c.stage = 'active'
    )
  );

drop policy if exists tickets_admin_update on public.tickets;
create policy tickets_admin_update on public.tickets
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists stage_events_admin_select on public.customer_stage_events;
create policy stage_events_admin_select on public.customer_stage_events
  for select to authenticated
  using (public.is_admin());

drop policy if exists customer_change_log_admin_select on public.customer_change_log;
create policy customer_change_log_admin_select on public.customer_change_log
  for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Private valid-ID photos. anon can upload only into inquiries/.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('valid-ids', 'valid-ids', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.customers add column if not exists valid_id_path text;
alter table public.customers add column if not exists plan_split text;
comment on column public.customers.plan_split is 'unused';
alter table public.customers add column if not exists plan_type text;
alter table public.customers drop constraint if exists customers_plan_type_check;
alter table public.customers add constraint customers_plan_type_check
  check (plan_type is null or plan_type in ('Basic', 'Plus', 'Max'));

drop policy if exists valid_ids_anon_upload on storage.objects;
create policy valid_ids_anon_upload on storage.objects
  for insert to anon
  with check (
    bucket_id = 'valid-ids'
    and name ~ '^inquiries/[A-Za-z0-9._-]+$'
  );

drop policy if exists valid_ids_admin_read on storage.objects;
create policy valid_ids_admin_read on storage.objects
  for select to authenticated
  using (bucket_id = 'valid-ids' and public.is_admin());

drop policy if exists valid_ids_admin_write on storage.objects;
create policy valid_ids_admin_write on storage.objects
  for all to authenticated
  using (bucket_id = 'valid-ids' and public.is_admin())
  with check (bucket_id = 'valid-ids' and public.is_admin());

-- ---------------------------------------------------------------------------
-- Seed. admins gets the owner. investors is intentionally left with zero rows.
-- Stage values live in the customers.stage check constraint, not an enum.
-- ---------------------------------------------------------------------------

insert into public.admins (email)
values ('fiberbropayatas@gmail.com')
on conflict (email) do nothing;

alter table public.customers add column if not exists latitude double precision;
alter table public.customers add column if not exists longitude double precision;

-- Billing, payments, the network map, and repair tickets are recorded in
-- supabase/migrations/billing_payments_map_tickets.sql (already applied).

-- Customer portal (login PIN, sessions, repair requests). See supabase/migrations/customer_portal.sql.
-- Additive customer portal. Do not drop tables, columns, or lookup_bill/submit_payment.
-- Safe to re-run. Does not update existing customer rows except through the new admin RPC.

create extension if not exists pgcrypto with schema extensions;

alter table public.customers add column if not exists portal_pin_hash text;
alter table public.customers add column if not exists portal_enabled boolean not null default false;
alter table public.customers add column if not exists failed_login_count integer not null default 0;
alter table public.customers add column if not exists locked_until timestamptz;

-- Keep PIN hashes and lock counters out of the customer change history.
create or replace function public.log_customer_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor text;
  col text;
  old_json jsonb;
  new_json jsonb;
begin
  actor := coalesce(nullif(auth.jwt() ->> 'email', ''), 'website');

  if tg_op = 'INSERT' then
    insert into public.customer_change_log (customer_id, action, changed_by)
    values (new.id, 'created', actor);
    return new;
  end if;

  old_json := to_jsonb(old);
  new_json := to_jsonb(new);
  for col in select jsonb_object_keys(new_json)
  loop
    if col in ('created_at', 'updated_at', 'portal_pin_hash', 'failed_login_count', 'locked_until') then
      continue;
    end if;
    if (old_json -> col) is distinct from (new_json -> col) then
      insert into public.customer_change_log (
        customer_id, action, field, old_value, new_value, changed_by
      ) values (
        new.id,
        'updated',
        col,
        old_json ->> col,
        new_json ->> col,
        actor
      );
    end if;
  end loop;
  return new;
end;
$$;

create table if not exists public.portal_sessions (
  token text primary key default encode(extensions.gen_random_bytes(32), 'hex'),
  customer_id uuid not null references public.customers (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days')
);

create index if not exists portal_sessions_customer_idx
  on public.portal_sessions (customer_id, expires_at);

alter table public.portal_sessions enable row level security;

revoke all on table public.portal_sessions from public, anon, authenticated;

create or replace function public.portal_customer(p_token text)
returns public.customers
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
begin
  if p_token is null or btrim(p_token) = '' then
    raise exception 'Your login expired. Please sign in again.';
  end if;

  select c.* into cust
  from public.portal_sessions s
  join public.customers c on c.id = s.customer_id
  where s.token = btrim(p_token)
    and s.expires_at > now();

  if not found then
    raise exception 'Your login expired. Please sign in again.';
  end if;
  return cust;
end;
$$;

create or replace function public.portal_login(account text, pin text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
  new_token text;
  generic text := 'Hindi magawang mag-login. Pakitingnan ang account number at PIN.';
  pin_ok boolean := false;
begin
  if account is null or btrim(account) = '' or pin is null or btrim(pin) = '' then
    raise exception '%', generic;
  end if;

  select * into cust
  from public.customers
  where account_number = btrim(account)
  order by created_at
  limit 1;

  if not found then
    raise exception '%', generic;
  end if;

  if cust.locked_until is not null and cust.locked_until > now() then
    raise exception '%', generic;
  end if;

  if cust.portal_enabled is true and cust.portal_pin_hash is not null and pin ~ '^[0-9]{4,8}$' then
    pin_ok := cust.portal_pin_hash = extensions.crypt(btrim(pin), cust.portal_pin_hash);
  end if;

  if not pin_ok then
    if cust.portal_pin_hash is not null then
      update public.customers
      set failed_login_count = case when failed_login_count + 1 >= 5 then 0 else failed_login_count + 1 end,
          locked_until = case when failed_login_count + 1 >= 5 then now() + interval '15 minutes' else null end
      where id = cust.id;
    end if;
    raise exception '%', generic;
  end if;

  update public.customers
  set failed_login_count = 0,
      locked_until = null
  where id = cust.id;

  delete from public.portal_sessions
  where customer_id = cust.id
    and expires_at <= now();

  insert into public.portal_sessions (customer_id)
  values (cust.id)
  returning token into new_token;

  return json_build_object('ok', true, 'token', new_token);
end;
$$;

create or replace function public.portal_logout(token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_token text := btrim(coalesce(token, ''));
begin
  delete from public.portal_sessions where portal_sessions.token = clean_token;
  return json_build_object('ok', true);
end;
$$;

create or replace function public.portal_me(token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
begin
  cust := public.portal_customer(token);
  return json_build_object(
    'account', json_build_object(
      'account_number', cust.account_number,
      'name', coalesce(nullif(btrim(cust.name), ''), btrim(concat_ws(' ', cust.first_name, cust.last_name))),
      'plan', coalesce(nullif(cust.plan_speed, ''), cust.plan),
      'address', cust.address,
      'area', cust.area,
      'mobile', coalesce(nullif(cust.mobile, ''), cust.contact_number)
    ),
    'invoices', coalesce((
      select json_agg(json_build_object(
        'id', i.id,
        'period', i.period,
        'amount', i.amount,
        'due_date', i.due_date,
        'status', i.status
      ) order by i.period desc)
      from public.invoices i
      where i.customer_id = cust.id
    ), '[]'::json),
    'payments', coalesce((
      select json_agg(json_build_object(
        'id', p.id,
        'invoice_id', p.invoice_id,
        'amount', p.amount,
        'method', p.method,
        'reference_no', p.reference_no,
        'status', p.status,
        'submitted_at', p.submitted_at
      ) order by p.submitted_at desc)
      from public.payments p
      where p.customer_id = cust.id
    ), '[]'::json),
    'tickets', coalesce((
      select json_agg(json_build_object(
        'id', t.id,
        'title', t.title,
        'description', t.description,
        'priority', t.priority,
        'status', t.status,
        'created_at', t.created_at
      ) order by t.created_at desc)
      from public.repair_tickets t
      where t.customer_id = cust.id
    ), '[]'::json)
  );
end;
$$;

create or replace function public.portal_submit_ticket(
  token text,
  category text,
  description text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
  new_id uuid;
  clean_category text := btrim(coalesce(category, ''));
  clean_description text := btrim(coalesce(description, ''));
begin
  cust := public.portal_customer(token);
  if clean_category = '' or char_length(clean_category) > 80 then
    raise exception 'Pumili ng uri ng problema.';
  end if;
  if clean_description = '' or char_length(clean_description) > 2000 then
    raise exception 'Ilagay ang detalye ng problema.';
  end if;

  insert into public.repair_tickets (customer_id, title, description, priority, status, created_by)
  values (cust.id, clean_category, clean_description, 'normal', 'pending', 'portal')
  returning id into new_id;

  return json_build_object('ok', true, 'id', new_id);
end;
$$;

create or replace function public.portal_submit_payment(
  token text,
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
  cust public.customers%rowtype;
begin
  cust := public.portal_customer(token);
  if cust.account_number is null or btrim(cust.account_number) = '' then
    raise exception 'This account has no account number yet.';
  end if;
  return public.submit_payment(
    cust.account_number,
    p_invoice,
    p_amount,
    p_method,
    p_reference,
    p_payer,
    p_proof
  );
end;
$$;

create or replace function public.admin_set_portal_pin(
  customer_id uuid,
  pin text,
  p_enabled boolean default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_pin text := nullif(btrim(coalesce(pin, '')), '');
  target_id uuid := customer_id;
  updated_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can set a portal PIN.';
  end if;

  if clean_pin is not null and clean_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits.';
  end if;

  if clean_pin is null and p_enabled is null then
    raise exception 'Enter a PIN or choose whether the portal is enabled.';
  end if;

  if clean_pin is not null then
    update public.customers
    set portal_pin_hash = extensions.crypt(clean_pin, extensions.gen_salt('bf')),
        failed_login_count = 0,
        locked_until = null,
        portal_enabled = coalesce(p_enabled, true)
    where id = target_id
    returning id into updated_id;
  else
    update public.customers
    set portal_enabled = p_enabled
    where id = target_id
    returning id into updated_id;
  end if;

  if updated_id is null then
    raise exception 'Customer was not found.';
  end if;

  if clean_pin is not null then
    delete from public.portal_sessions where portal_sessions.customer_id = target_id;
  end if;

  return json_build_object('ok', true);
end;
$$;

revoke all on function public.portal_customer(text) from public;
revoke all on function public.portal_login(text, text) from public;
revoke all on function public.portal_logout(text) from public;
revoke all on function public.portal_me(text) from public;
revoke all on function public.portal_submit_ticket(text, text, text) from public;
revoke all on function public.portal_submit_payment(text, uuid, numeric, text, text, text, text) from public;
revoke all on function public.admin_set_portal_pin(uuid, text, boolean) from public;

grant execute on function public.portal_login(text, text) to anon, authenticated;
grant execute on function public.portal_logout(text) to anon, authenticated;
grant execute on function public.portal_me(text) to anon, authenticated;
grant execute on function public.portal_submit_ticket(text, text, text) to anon, authenticated;
grant execute on function public.portal_submit_payment(text, uuid, numeric, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_set_portal_pin(uuid, text, boolean) to authenticated;

revoke all on function public.portal_customer(text) from anon, authenticated;

-- Finance, billing grace, wallet credit, and portal proof images.
-- supabase/migrations/20261119_finance_billing.sql
-- Finance, billing grace, wallet credit, and portal proof images.
-- Idempotent. Does not drop tables, columns, or customer rows.
--
-- Payment screenshots from the customer portal are stored in
-- public.payment_proof_files (base64 text), written only by
-- portal_submit_proof() after it checks the portal session token.
-- The table has no anon policies. Admins read one row at a time
-- through RLS (public.is_admin()). The anon key cannot list other
-- customers' images. Older proofs that used storage path proofs/
-- still work through payment-proofs signed URLs.
--
-- customers.wallet_credit starts at 0 for existing rows (column default).
-- A trigger refreshes it the next time a payment status changes:
-- greatest(confirmed payments − non-void invoices, 0).
-- The transaction history screen does not rely on that cache; it
-- computes the running balance from bills and confirmed payments.
--
-- Total Installation in Finance counts customers whose installation_date
-- is in the selected month, times app_settings.installation_fee (default 1000).
-- Grace period is app_settings.grace_days (default 3): days after due_date
-- that are still "grace" rather than overdue.

insert into public.app_settings (key, value, is_public) values
  ('grace_days', '3', false),
  ('installation_fee', '1000', false)
on conflict (key) do nothing;

alter table public.customers add column if not exists wallet_credit numeric(12, 2) not null default 0;
alter table public.payments add column if not exists reject_reason text;

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in (
    'Gas', 'Meals', 'Materials', 'Maintenance', 'Office Supplies',
    'Transportation', 'Repairs', 'Others'
  )),
  amount numeric(12, 2) not null check (amount >= 0),
  expense_date date not null default current_date,
  remarks text,
  receipt_path text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_by text,
  created_at timestamptz not null default now(),
  approved_by text,
  approved_at timestamptz
);

create index if not exists expenses_status_date_idx
  on public.expenses (status, expense_date desc);

create table if not exists public.payment_proof_files (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete cascade,
  customer_id uuid not null references public.customers (id) on delete cascade,
  content_type text not null,
  image_base64 text not null,
  created_at timestamptz not null default now()
);

create index if not exists payment_proof_files_payment_idx
  on public.payment_proof_files (payment_id);

alter table public.expenses enable row level security;
alter table public.payment_proof_files enable row level security;

revoke all on table public.expenses from public, anon;
revoke all on table public.payment_proof_files from public, anon, authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
grant select on public.payment_proof_files to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'expenses' and policyname = 'expenses_admin_all'
  ) then
    create policy expenses_admin_all on public.expenses
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'payment_proof_files' and policyname = 'payment_proof_files_admin_read'
  ) then
    create policy payment_proof_files_admin_read on public.payment_proof_files
      for select to authenticated
      using (public.is_admin());
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'expense-receipts',
  'expense-receipts',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'expense_receipts_admin_read'
  ) then
    create policy expense_receipts_admin_read on storage.objects
      for select to authenticated
      using (bucket_id = 'expense-receipts' and public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'expense_receipts_admin_insert'
  ) then
    create policy expense_receipts_admin_insert on storage.objects
      for insert to authenticated
      with check (bucket_id = 'expense-receipts' and public.is_admin() and name ~ '^receipts/.+');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'expense_receipts_admin_delete'
  ) then
    create policy expense_receipts_admin_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'expense-receipts' and public.is_admin());
  end if;
end $$;

create or replace function public.refresh_wallet_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(new.customer_id, old.customer_id);
  paid numeric;
  billed numeric;
begin
  if cid is null then
    return coalesce(new, old);
  end if;
  select coalesce(sum(amount), 0) into paid
  from public.payments
  where customer_id = cid and status = 'confirmed';
  select coalesce(sum(amount), 0) into billed
  from public.invoices
  where customer_id = cid and status <> 'void';
  update public.customers
  set wallet_credit = greatest(paid - billed, 0)
  where id = cid;
  return coalesce(new, old);
end;
$$;

drop trigger if exists payments_refresh_wallet on public.payments;
create trigger payments_refresh_wallet
  after insert or update of status, amount or delete on public.payments
  for each row execute function public.refresh_wallet_credit();

create or replace function public.log_customer_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor text;
  col text;
  old_json jsonb;
  new_json jsonb;
begin
  actor := coalesce(nullif(auth.jwt() ->> 'email', ''), 'website');
  if tg_op = 'INSERT' then
    insert into public.customer_change_log (customer_id, action, changed_by)
    values (new.id, 'created', actor);
    return new;
  end if;
  old_json := to_jsonb(old);
  new_json := to_jsonb(new);
  for col in select jsonb_object_keys(new_json)
  loop
    if col in ('created_at', 'updated_at', 'portal_pin_hash', 'failed_login_count', 'locked_until', 'wallet_credit') then
      continue;
    end if;
    if (old_json -> col) is distinct from (new_json -> col) then
      insert into public.customer_change_log (
        customer_id, action, field, old_value, new_value, changed_by
      ) values (
        new.id, 'updated', col, old_json ->> col, new_json ->> col, actor
      );
    end if;
  end loop;
  return new;
end;
$$;

create or replace function public.portal_me(token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
begin
  cust := public.portal_customer(token);
  return json_build_object(
    'account', json_build_object(
      'account_number', cust.account_number,
      'name', coalesce(nullif(btrim(cust.name), ''), btrim(concat_ws(' ', cust.first_name, cust.last_name))),
      'plan', coalesce(nullif(cust.plan_speed, ''), cust.plan),
      'address', cust.address,
      'area', cust.area,
      'mobile', coalesce(nullif(cust.mobile, ''), cust.contact_number),
      'wallet_credit', coalesce(cust.wallet_credit, 0)
    ),
    'invoices', coalesce((
      select json_agg(json_build_object(
        'id', i.id,
        'period', i.period,
        'amount', i.amount,
        'due_date', i.due_date,
        'status', i.status,
        'created_at', i.created_at
      ) order by i.period desc)
      from public.invoices i
      where i.customer_id = cust.id
    ), '[]'::json),
    'payments', coalesce((
      select json_agg(json_build_object(
        'id', p.id,
        'invoice_id', p.invoice_id,
        'amount', p.amount,
        'method', p.method,
        'reference_no', p.reference_no,
        'status', p.status,
        'submitted_at', p.submitted_at,
        'confirmed_at', p.confirmed_at,
        'reject_reason', p.reject_reason
      ) order by p.submitted_at desc)
      from public.payments p
      where p.customer_id = cust.id
    ), '[]'::json),
    'tickets', coalesce((
      select json_agg(json_build_object(
        'id', t.id,
        'title', t.title,
        'description', t.description,
        'priority', t.priority,
        'status', t.status,
        'created_at', t.created_at
      ) order by t.created_at desc)
      from public.repair_tickets t
      where t.customer_id = cust.id
    ), '[]'::json)
  );
end;
$$;

create or replace function public.portal_submit_proof(
  token text,
  p_invoice uuid,
  p_amount numeric,
  p_method text,
  p_reference text,
  p_payer text,
  p_image_base64 text,
  p_mime text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
  inv public.invoices%rowtype;
  new_id uuid;
  clean text;
  raw bytea;
  mime text := lower(btrim(coalesce(p_mime, '')));
begin
  cust := public.portal_customer(token);
  if p_reference is null or btrim(p_reference) = '' then
    raise exception 'Reference number is required.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;
  if p_method is null or p_method not in ('gcash', 'maya', 'bank', 'cash', 'other') then
    raise exception 'Choose a valid payment method.';
  end if;
  if mime not in ('image/jpeg', 'image/png', 'image/webp') then
    raise exception 'The screenshot must be a JPEG, PNG, or WebP image.';
  end if;
  if p_image_base64 is null or btrim(p_image_base64) = '' then
    raise exception 'A payment screenshot is required.';
  end if;

  clean := regexp_replace(p_image_base64, '^data:image/[a-zA-Z0-9.+-]+;base64,', '');
  clean := regexp_replace(clean, '\s', '', 'g');
  begin
    raw := decode(clean, 'base64');
  exception when others then
    raise exception 'The screenshot could not be read.';
  end;
  if octet_length(raw) > 2097152 then
    raise exception 'The screenshot must be 2 MB or smaller.';
  end if;

  select * into inv from public.invoices where id = p_invoice and customer_id = cust.id;
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
    invoice_id, customer_id, amount, method, reference_no, payer_name, status, source
  ) values (
    inv.id, cust.id, p_amount, p_method, btrim(p_reference),
    nullif(btrim(coalesce(p_payer, '')), ''), 'pending', 'website'
  )
  returning id into new_id;

  insert into public.payment_proof_files (payment_id, customer_id, content_type, image_base64)
  values (new_id, cust.id, mime, clean);

  return json_build_object('ok', true, 'id', new_id);
end;
$$;

revoke all on function public.refresh_wallet_credit() from public;
revoke all on function public.portal_me(text) from public;
revoke all on function public.portal_submit_proof(text, uuid, numeric, text, text, text, text, text) from public;
grant execute on function public.portal_me(text) to anon, authenticated;
grant execute on function public.portal_submit_proof(text, uuid, numeric, text, text, text, text, text) to anon, authenticated;

-- Network map. supabase/migrations/20261120_network_map.sql
-- Network map: LP points, NAP boxes, customer links, and area polygons.
-- Idempotent. Does not delete rows or overwrite customers.lp / customers.nap / customers.port.

create table if not exists public.distribution_points (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  area text,
  sub_area text,
  port_capacity integer,
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);

create unique index if not exists distribution_points_code_uidx
  on public.distribution_points (upper(code));

create table if not exists public.nap_boxes (
  id uuid primary key default gen_random_uuid(),
  lp_id uuid references public.distribution_points (id) on delete set null,
  code text not null,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  area text,
  sub_area text,
  port_capacity integer,
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);

create unique index if not exists nap_boxes_code_uidx
  on public.nap_boxes (upper(code));

create index if not exists nap_boxes_lp_idx on public.nap_boxes (lp_id);

create table if not exists public.area_polygons (
  id uuid primary key default gen_random_uuid(),
  area_name text not null,
  path jsonb not null,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.customers add column if not exists lp_id uuid references public.distribution_points (id) on delete set null;
alter table public.customers add column if not exists nap_id uuid references public.nap_boxes (id) on delete set null;

create index if not exists customers_nap_id_idx on public.customers (nap_id);
create index if not exists customers_lp_id_idx on public.customers (lp_id);

alter table public.distribution_points enable row level security;
alter table public.nap_boxes enable row level security;
alter table public.area_polygons enable row level security;

revoke all on table public.distribution_points from public, anon;
revoke all on table public.nap_boxes from public, anon;
revoke all on table public.area_polygons from public, anon;
grant select, insert, update, delete on public.distribution_points to authenticated;
grant select, insert, update, delete on public.nap_boxes to authenticated;
grant select, insert, update, delete on public.area_polygons to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'distribution_points' and policyname = 'distribution_points_admin_all'
  ) then
    create policy distribution_points_admin_all on public.distribution_points
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'nap_boxes' and policyname = 'nap_boxes_admin_all'
  ) then
    create policy nap_boxes_admin_all on public.nap_boxes
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'area_polygons' and policyname = 'area_polygons_admin_all'
  ) then
    create policy area_polygons_admin_all on public.area_polygons
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'network-photos',
  'network-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_read'
  ) then
    create policy network_photos_admin_read on storage.objects
      for select to authenticated
      using (bucket_id = 'network-photos' and public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_insert'
  ) then
    create policy network_photos_admin_insert on storage.objects
      for insert to authenticated
      with check (bucket_id = 'network-photos' and public.is_admin() and name ~ '^assets/.+');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_delete'
  ) then
    create policy network_photos_admin_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'network-photos' and public.is_admin());
  end if;
end $$;

-- Used NAP ports are not stored. Count customers.nap_id in the admin map.
-- customers.lp and customers.nap text fields stay as entered.
