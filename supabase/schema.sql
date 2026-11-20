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

-- Phase 1 payments. supabase/migrations/20261120_phase1_payments.sql
-- Phase 1 payments: GCash refs, virtual logbook, auto-match, bill numbers.
-- Idempotent. Does not delete customer rows or existing account numbers.
--
-- Auto-match: AFTER INSERT/UPDATE triggers on virtual_logbook and gcash_refs
-- call auto_match_logbook(). A screenshot can match a ref encoded later, and
-- a ref can match a screenshot that arrived first. Match is ref + amount + date
-- against one unused, non-duplicate GCash ref. The payment is applied to the
-- oldest open bill. Partial payments leave the bill pending (remaining balance).
-- A full payment marks it paid. Extra money stays in wallet_credit via the
-- existing refresh trigger (confirmed payments minus non-void invoices).
--
-- Bills: generate_upcoming_bills() creates a monthly invoice when today is
-- within 10 days before the customer's due date (due day 29–31 clamps to the
-- last day of the month). It requires an admin. The dashboard calls it once
-- per day. pg_cron, when installed, calls generate_upcoming_bills_job()
-- because a cron session has no admin JWT. Period stays YYYY-MM. period_label
-- is Mon_YYYY (Nov_2026). bill_number is FBROPAY-BILL plus 10 digits.
-- previous_balance is a snapshot of older open bills, not added into amount.
--
-- New account numbers (blank only) use app_settings.account_number_format,
-- default FBRO{CODE2}{SEQ7}, e.g. FBROAL0000001. Existing numbers are kept.

insert into public.app_settings (key, value, is_public) values
  ('account_number_format', 'FBRO{CODE2}{SEQ7}', false)
on conflict (key) do nothing;

-- customers.due_date_number is the existing due day of month. Do not add due_day.
update public.customers
set due_date_number = extract(day from installation_date)::integer
where due_date_number is null
  and installation_date is not null;

alter table public.invoices add column if not exists bill_number text;
alter table public.invoices add column if not exists period_label text;
alter table public.invoices add column if not exists previous_balance numeric(12, 2) not null default 0;

create unique index if not exists invoices_bill_number_uidx
  on public.invoices (bill_number)
  where bill_number is not null;

alter table public.payments add column if not exists cutoff text;

create table if not exists public.gcash_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.gcash_accounts (name) values
  ('Alvin'), ('Jacky'), ('Jollibee'), ('Vincent')
on conflict (name) do nothing;

create table if not exists public.gcash_refs (
  id uuid primary key default gen_random_uuid(),
  gcash_account_id uuid references public.gcash_accounts (id) on delete set null,
  ref_number text not null,
  txn_date date not null,
  amount numeric(12, 2) not null,
  status text not null default 'unmatched' check (status in ('unmatched', 'matched', 'processed')),
  duplicate_flag boolean not null default false,
  payment_id uuid references public.payments (id) on delete set null,
  encoded_by text,
  created_at timestamptz not null default now()
);

create unique index if not exists gcash_refs_live_ref_uidx
  on public.gcash_refs (ref_number)
  where duplicate_flag = false;

create index if not exists gcash_refs_account_date_idx
  on public.gcash_refs (gcash_account_id, txn_date desc);

create table if not exists public.virtual_logbook (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  payment_id uuid references public.payments (id) on delete set null,
  gcash_ref_id uuid references public.gcash_refs (id) on delete set null,
  collection_date date,
  investor_account text,
  entry_type text not null default 'Collection',
  client_name text,
  fb_account text,
  mode text not null default 'gcash',
  amount numeric(12, 2),
  gcash_ref text,
  remarks text,
  period_label text,
  image_base64 text,
  content_type text,
  unique_code text,
  status text not null default 'unmatched' check (status in ('unmatched', 'processed')),
  match_reason text,
  logged_by text,
  source text not null default 'admin' check (source in ('admin', 'portal')),
  cutoff text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists virtual_logbook_status_idx
  on public.virtual_logbook (status, created_at desc);
create index if not exists virtual_logbook_ref_idx
  on public.virtual_logbook (gcash_ref);

alter table public.gcash_accounts enable row level security;
alter table public.gcash_refs enable row level security;
alter table public.virtual_logbook enable row level security;

revoke all on table public.gcash_accounts from public, anon;
revoke all on table public.gcash_refs from public, anon;
revoke all on table public.virtual_logbook from public, anon;
grant select, insert, update, delete on public.gcash_accounts to authenticated;
grant select, insert, update, delete on public.gcash_refs to authenticated;
grant select, insert, update, delete on public.virtual_logbook to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'gcash_accounts' and policyname = 'gcash_accounts_admin_all'
  ) then
    create policy gcash_accounts_admin_all on public.gcash_accounts
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'gcash_refs' and policyname = 'gcash_refs_admin_all'
  ) then
    create policy gcash_refs_admin_all on public.gcash_refs
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'virtual_logbook' and policyname = 'virtual_logbook_admin_all'
  ) then
    create policy virtual_logbook_admin_all on public.virtual_logbook
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

create or replace function public.normalize_gcash_ref(p_ref text)
returns text
language sql
immutable
as $$
  select nullif(regexp_replace(coalesce(p_ref, ''), '\D', '', 'g'), '');
$$;

create or replace function public.collection_cutoff(p_date date)
returns text
language sql
immutable
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

create or replace function public.next_fiberbro_account(p_investor uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  fmt text;
  code text;
  base text;
  n bigint;
begin
  select value into fmt from public.app_settings where key = 'account_number_format';
  fmt := coalesce(nullif(btrim(fmt), ''), 'FBRO{CODE2}{SEQ7}');
  select upper(left(regexp_replace(coalesce(i.code, i.name, 'XX'), '[^A-Za-z]', '', 'g'), 2))
    into code
  from public.investors i
  where i.id = p_investor;
  if code is null or code = '' then
    code := 'XX';
  elsif length(code) = 1 then
    code := code || 'X';
  end if;
  base := replace(replace(fmt, '{CODE2}', code), '{SEQ7}', '');
  perform pg_advisory_xact_lock(hashtext('fiberbro_acct_' || base));
  select coalesce(max(substring(account_number from length(base) + 1)::bigint), 0) + 1
    into n
  from public.customers
  where account_number like base || '%'
    and substring(account_number from length(base) + 1) ~ '^[0-9]+$';
  return base || lpad(n::text, 7, '0');
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

  new.email_address := coalesce(nullif(btrim(new.email_address), ''), nullif(btrim(new.email), ''));
  new.fb_account := coalesce(nullif(btrim(new.fb_account), ''), nullif(btrim(new.facebook_name), ''));

  if new.account_number is null or btrim(new.account_number) = '' then
    new.account_number := public.next_fiberbro_account(new.investor_id);
  end if;

  if new.due_date_number is null and new.installation_date is not null then
    new.due_date_number := extract(day from new.installation_date)::integer;
  end if;

  new.account_status := public.stage_label(new.stage);
  return new;
end;
$$;

create or replace function public.customers_fill_due_day()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.due_date_number is null and new.installation_date is not null then
    new.due_date_number := extract(day from new.installation_date)::integer;
  end if;
  return new;
end;
$$;

drop trigger if exists customers_fill_due_day on public.customers;
create trigger customers_fill_due_day
  before insert or update of installation_date, due_date_number on public.customers
  for each row execute function public.customers_fill_due_day();

create or replace function public.apply_invoice_payment_state(p_invoice uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bill_amount numeric;
  bill_status text;
  paid_sum numeric;
  waiting boolean;
begin
  if p_invoice is null then
    return;
  end if;
  select amount, status into bill_amount, bill_status
  from public.invoices where id = p_invoice;
  if bill_status = 'void' or bill_amount is null then
    return;
  end if;
  select coalesce(sum(amount), 0) into paid_sum
  from public.payments
  where invoice_id = p_invoice and status = 'confirmed';
  select exists (
    select 1 from public.payments
    where invoice_id = p_invoice and status = 'pending'
  ) into waiting;
  if paid_sum + 0.009 >= bill_amount then
    update public.invoices
      set status = 'paid', paid_at = coalesce(paid_at, now())
      where id = p_invoice;
  elsif paid_sum > 0 or waiting then
    update public.invoices
      set status = 'pending', paid_at = null
      where id = p_invoice;
  else
    update public.invoices
      set status = 'unpaid', paid_at = null
      where id = p_invoice;
  end if;
end;
$$;

-- The deployed payments_sync_invoice trigger is BEFORE the row is visible.
-- Summing payments from the table in that trigger misses the row being saved.
-- Stamp confirmation on BEFORE, then recompute the bill AFTER the row is stored.
create or replace function public.stamp_payment_confirmation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then
    if new.confirmed_at is null then
      new.confirmed_at := now();
    end if;
    if new.confirmed_by is null or btrim(new.confirmed_by) = '' then
      new.confirmed_by := coalesce(nullif(auth.jwt() ->> 'email', ''), 'system');
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.sync_invoice_from_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.apply_invoice_payment_state(old.invoice_id);
    return old;
  end if;
  perform public.apply_invoice_payment_state(new.invoice_id);
  if tg_op = 'UPDATE' and old.invoice_id is distinct from new.invoice_id then
    perform public.apply_invoice_payment_state(old.invoice_id);
  end if;
  return new;
end;
$$;

drop trigger if exists payments_stamp_confirmation on public.payments;
create trigger payments_stamp_confirmation
  before insert or update of status on public.payments
  for each row execute function public.stamp_payment_confirmation();

drop trigger if exists payments_sync_invoice on public.payments;
create trigger payments_sync_invoice
  after insert or update of status, amount, invoice_id on public.payments
  for each row execute function public.sync_invoice_from_payment();

create or replace function public.next_bill_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n bigint;
begin
  perform pg_advisory_xact_lock(hashtext('fiberbro_bill_number'));
  select coalesce(max(substring(bill_number from '([0-9]+)$')::bigint), 0) + 1
    into n
  from public.invoices
  where bill_number ~ '^FBROPAY-BILL[0-9]+$';
  return 'FBROPAY-BILL' || lpad(n::text, 10, '0');
end;
$$;

create or replace function public.generate_upcoming_bills_job()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cust record;
  step integer;
  due_on date;
  period_key text;
  label text;
  prev_bal numeric;
  inserted_count integer := 0;
  fee numeric;
begin
  for cust in
    select c.id, c.due_date_number, c.installation_date, c.monthly_bill, c.price
    from public.customers c
    where c.stage = 'active'
  loop
    for step in 0..1 loop
      due_on := public.clamp_due_date(
        extract(year from (current_date + make_interval(months => step)))::integer,
        extract(month from (current_date + make_interval(months => step)))::integer,
        coalesce(cust.due_date_number, extract(day from cust.installation_date)::integer, 1)
      );
      if current_date < due_on - 10 or current_date > due_on + 5 then
        continue;
      end if;
      period_key := to_char(due_on, 'YYYY-MM');
      label := to_char(due_on, 'Mon_YYYY');
      if exists (
        select 1 from public.invoices i
        where i.customer_id = cust.id and i.period = period_key
      ) then
        continue;
      end if;
      fee := coalesce(cust.monthly_bill, cust.price, 0);
      if fee <= 0 then
        continue;
      end if;
      select coalesce(sum(greatest(i.amount - coalesce(paid.total, 0), 0)), 0)
        into prev_bal
      from public.invoices i
      left join (
        select invoice_id, sum(amount) as total
        from public.payments
        where status = 'confirmed'
        group by invoice_id
      ) paid on paid.invoice_id = i.id
      where i.customer_id = cust.id
        and i.status in ('unpaid', 'pending')
        and i.period < period_key;
      insert into public.invoices (
        customer_id, period, period_label, bill_number, amount, previous_balance,
        due_date, status, created_by
      ) values (
        cust.id, period_key, label, public.next_bill_number(), fee, prev_bal,
        due_on, 'unpaid', 'auto'
      );
      inserted_count := inserted_count + 1;
    end loop;
  end loop;
  return inserted_count;
end;
$$;

create or replace function public.generate_upcoming_bills()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can generate bills.';
  end if;
  return public.generate_upcoming_bills_job();
end;
$$;

create or replace function public.auto_match_logbook(p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  rowlog public.virtual_logbook%rowtype;
  refrow public.gcash_refs%rowtype;
  norm text;
  reason text := 'Ref not found';
  open_invoice uuid;
  remaining numeric;
  pay_id uuid;
  cust_name text;
  already uuid;
begin
  select * into rowlog from public.virtual_logbook where id = p_id for update;
  if not found then
    return 'missing';
  end if;
  if rowlog.status = 'processed' then
    return 'processed';
  end if;

  norm := public.normalize_gcash_ref(rowlog.gcash_ref);
  if norm is null then
    update public.virtual_logbook set match_reason = 'Ref not found', status = 'unmatched' where id = p_id;
    return 'Ref not found';
  end if;

  select l.id into already
  from public.virtual_logbook l
  where l.id <> p_id
    and l.status = 'processed'
    and public.normalize_gcash_ref(l.gcash_ref) = norm
  limit 1;
  if already is not null then
    update public.virtual_logbook set match_reason = 'Duplicate ref', status = 'unmatched' where id = p_id;
    return 'Duplicate ref';
  end if;

  select * into refrow
  from public.gcash_refs r
  where r.ref_number = norm
    and r.duplicate_flag = false
    and r.status in ('unmatched', 'matched')
    and r.payment_id is null
  order by r.created_at
  limit 1
  for update;

  if not found then
    if exists (
      select 1 from public.gcash_refs r
      where r.ref_number = norm and (r.duplicate_flag or r.status = 'processed' or r.payment_id is not null)
    ) then
      reason := 'Duplicate ref';
    else
      reason := 'Ref not found';
    end if;
    update public.virtual_logbook set match_reason = reason, status = 'unmatched', gcash_ref = norm where id = p_id;
    return reason;
  end if;

  if round(refrow.amount, 2) <> round(coalesce(rowlog.amount, -1), 2) then
    update public.virtual_logbook set match_reason = 'Amount not matched', status = 'unmatched', gcash_ref = norm where id = p_id;
    return 'Amount not matched';
  end if;
  if rowlog.collection_date is null or refrow.txn_date <> rowlog.collection_date then
    update public.virtual_logbook set match_reason = 'Date not matched', status = 'unmatched', gcash_ref = norm where id = p_id;
    return 'Date not matched';
  end if;

  if rowlog.customer_id is null and rowlog.client_name is not null then
    update public.virtual_logbook l
    set customer_id = (
      select c.id from public.customers c
      where lower(btrim(c.name)) = lower(btrim(rowlog.client_name))
      order by c.created_at
      limit 1
    )
    where l.id = p_id
      and l.customer_id is null;
    select * into rowlog from public.virtual_logbook where id = p_id;
  end if;

  if rowlog.customer_id is null then
    update public.virtual_logbook set match_reason = 'Ref not found', status = 'unmatched', gcash_ref = norm where id = p_id;
    return 'Ref not found';
  end if;

  select i.id, i.amount - coalesce((
    select sum(p.amount) from public.payments p
    where p.invoice_id = i.id and p.status = 'confirmed'
  ), 0)
  into open_invoice, remaining
  from public.invoices i
  where i.customer_id = rowlog.customer_id
    and i.status in ('unpaid', 'pending')
  order by i.due_date nulls last, i.period
  limit 1;

  if open_invoice is null or remaining <= 0 then
    update public.virtual_logbook set match_reason = 'No open bill', status = 'unmatched', gcash_ref = norm where id = p_id;
    return 'No open bill';
  end if;

  if rowlog.payment_id is not null then
    update public.payments
    set status = 'confirmed',
        confirmed_by = coalesce(confirmed_by, 'auto-match'),
        confirmed_at = coalesce(confirmed_at, now()),
        cutoff = public.collection_cutoff(rowlog.collection_date),
        reference_no = norm,
        amount = rowlog.amount,
        invoice_id = open_invoice
    where id = rowlog.payment_id
    returning id into pay_id;
  else
    insert into public.payments (
      invoice_id, customer_id, amount, method, reference_no, status, source,
      confirmed_by, confirmed_at, cutoff
    ) values (
      open_invoice, rowlog.customer_id, rowlog.amount, coalesce(nullif(rowlog.mode, ''), 'gcash'),
      norm, 'confirmed', case when rowlog.source = 'portal' then 'website' else 'admin' end,
      'auto-match', now(), public.collection_cutoff(rowlog.collection_date)
    )
    returning id into pay_id;
  end if;

  update public.gcash_refs
  set status = 'processed', payment_id = pay_id
  where id = refrow.id;

  select name into cust_name from public.customers where id = rowlog.customer_id;
  update public.virtual_logbook
  set status = 'processed',
      match_reason = null,
      payment_id = pay_id,
      gcash_ref_id = refrow.id,
      gcash_ref = norm,
      processed_at = now(),
      cutoff = public.collection_cutoff(collection_date),
      client_name = coalesce(client_name, cust_name),
      unique_code = coalesce(unique_code, to_char(collection_date, 'YYYYMMDD') || '-' || coalesce(client_name, '') || '-' || coalesce(mode, '') || '-' || amount::text || '-' || norm || '-' || coalesce(public.collection_cutoff(collection_date), ''))
  where id = p_id;

  return 'processed';
end;
$$;

create or replace function public.trg_auto_match_logbook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'processed' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.gcash_ref is not distinct from old.gcash_ref
     and new.amount is not distinct from old.amount
     and new.collection_date is not distinct from old.collection_date
     and new.customer_id is not distinct from old.customer_id
     and new.status is not distinct from old.status then
    return new;
  end if;
  perform public.auto_match_logbook(new.id);
  return new;
end;
$$;

create or replace function public.trg_auto_match_gcash_ref()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  log_id uuid;
begin
  if new.duplicate_flag or new.status = 'processed' or new.payment_id is not null then
    return new;
  end if;
  for log_id in
    select l.id
    from public.virtual_logbook l
    where l.status <> 'processed'
      and public.normalize_gcash_ref(l.gcash_ref) = new.ref_number
  loop
    perform public.auto_match_logbook(log_id);
  end loop;
  return new;
end;
$$;

create or replace function public.virtual_logbook_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.gcash_ref is not null then
    new.gcash_ref := public.normalize_gcash_ref(new.gcash_ref);
  end if;
  if new.cutoff is null then
    new.cutoff := public.collection_cutoff(coalesce(new.collection_date, current_date));
  end if;
  return new;
end;
$$;

drop trigger if exists virtual_logbook_fill on public.virtual_logbook;
create trigger virtual_logbook_fill
  before insert or update of gcash_ref, collection_date, cutoff on public.virtual_logbook
  for each row execute function public.virtual_logbook_fill();

drop trigger if exists virtual_logbook_auto_match on public.virtual_logbook;
create trigger virtual_logbook_auto_match
  after insert or update of gcash_ref, amount, collection_date, customer_id, status
  on public.virtual_logbook
  for each row execute function public.trg_auto_match_logbook();

drop trigger if exists gcash_refs_auto_match on public.gcash_refs;
create trigger gcash_refs_auto_match
  after insert or update of ref_number, amount, txn_date, status, duplicate_flag
  on public.gcash_refs
  for each row execute function public.trg_auto_match_gcash_ref();

create or replace function public.trg_logbook_from_proof()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pay public.payments%rowtype;
  cust_name text;
  fb text;
  investor_code text;
  new_id uuid;
begin
  select * into pay from public.payments where id = new.payment_id;
  if not found then
    return new;
  end if;
  if exists (select 1 from public.virtual_logbook where payment_id = pay.id) then
    return new;
  end if;
  select c.name, c.fb_account, i.code
    into cust_name, fb, investor_code
  from public.customers c
  left join public.investors i on i.id = c.investor_id
  where c.id = pay.customer_id;

  insert into public.virtual_logbook (
    customer_id, payment_id, collection_date, investor_account, entry_type,
    client_name, fb_account, mode, amount, gcash_ref, source, logged_by,
    status, cutoff, image_base64, content_type, unique_code
  ) values (
    pay.customer_id,
    pay.id,
    (pay.submitted_at at time zone 'Asia/Manila')::date,
    investor_code,
    'Collection',
    cust_name,
    fb,
    pay.method,
    pay.amount,
    public.normalize_gcash_ref(pay.reference_no),
    'portal',
    'portal',
    'unmatched',
    public.collection_cutoff((pay.submitted_at at time zone 'Asia/Manila')::date),
    new.image_base64,
    new.content_type,
    to_char((pay.submitted_at at time zone 'Asia/Manila')::date, 'YYYYMMDD')
      || '-' || coalesce(cust_name, '') || '-' || coalesce(pay.method, '')
      || '-' || pay.amount::text || '-' || coalesce(public.normalize_gcash_ref(pay.reference_no), '')
  )
  returning id into new_id;

  perform public.auto_match_logbook(new_id);
  return new;
end;
$$;

drop trigger if exists payment_proof_files_to_logbook on public.payment_proof_files;
create trigger payment_proof_files_to_logbook
  after insert on public.payment_proof_files
  for each row execute function public.trg_logbook_from_proof();

create or replace function public.add_gcash_refs(p_account uuid, p_lines text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_line text;
  cleaned text;
  norm text;
  txn date;
  amt numeric;
  inserted_count integer := 0;
  duplicate_count integer := 0;
  skipped_count integer := 0;
  actor text := nullif(auth.jwt() ->> 'email', '');
begin
  if not public.is_admin() then
    raise exception 'Only an admin can encode GCash refs.';
  end if;
  foreach raw_line in array regexp_split_to_array(coalesce(p_lines, ''), E'\\r?\\n')
  loop
    if btrim(raw_line) = '' then
      continue;
    end if;
    txn := substring(raw_line from '(\d{4}-\d{2}-\d{2})')::date;
    if txn is null then
      begin
        txn := to_date(substring(raw_line from '([A-Za-z]{3}\s+\d{1,2},\s+\d{4})'), 'Mon DD, YYYY');
      exception when others then
        txn := null;
      end;
    end if;
    cleaned := regexp_replace(raw_line, '\d{4}-\d{2}-\d{2}', ' ', 'g');
    cleaned := regexp_replace(cleaned, '[A-Za-z]{3}\s+\d{1,2},\s+\d{4}', ' ', 'g');
    cleaned := replace(cleaned, ',', '');
    amt := substring(cleaned from '(\d+\.\d{2})\s*$')::numeric;
    if amt is not null then
      cleaned := regexp_replace(cleaned, '\d+\.\d{2}\s*$', ' ');
    else
      amt := substring(cleaned from '(\d+)\s*$')::numeric;
      if amt is not null then
        cleaned := regexp_replace(cleaned, '\d+\s*$', ' ');
      end if;
    end if;
    norm := public.normalize_gcash_ref(cleaned);
    if txn is null or norm is null or amt is null then
      skipped_count := skipped_count + 1;
      continue;
    end if;
    if exists (
      select 1 from public.gcash_refs
      where ref_number = norm and duplicate_flag = false
    ) then
      insert into public.gcash_refs (gcash_account_id, ref_number, txn_date, amount, duplicate_flag, encoded_by, status)
      values (p_account, norm, txn, amt, true, actor, 'unmatched');
      duplicate_count := duplicate_count + 1;
    else
      insert into public.gcash_refs (gcash_account_id, ref_number, txn_date, amount, duplicate_flag, encoded_by)
      values (p_account, norm, txn, amt, false, actor);
      inserted_count := inserted_count + 1;
    end if;
  end loop;
  return json_build_object('ok', true, 'inserted', inserted_count, 'duplicates', duplicate_count, 'skipped', skipped_count);
end;
$$;

create or replace function public.manual_process_logbook(p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  rowlog public.virtual_logbook%rowtype;
  open_invoice uuid;
  pay_id uuid;
  norm text;
  ref_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can override a logbook row.';
  end if;
  select * into rowlog from public.virtual_logbook where id = p_id for update;
  if not found then
    raise exception 'Logbook row was not found.';
  end if;
  if rowlog.customer_id is null then
    raise exception 'Choose the customer before processing.';
  end if;
  if rowlog.amount is null or rowlog.amount <= 0 then
    raise exception 'Amount is required.';
  end if;
  norm := public.normalize_gcash_ref(rowlog.gcash_ref);
  select i.id into open_invoice
  from public.invoices i
  where i.customer_id = rowlog.customer_id
    and i.status in ('unpaid', 'pending')
  order by i.due_date nulls last, i.period
  limit 1;
  if open_invoice is null then
    raise exception 'That customer has no open bill.';
  end if;
  if rowlog.payment_id is not null then
    update public.payments
    set status = 'confirmed', confirmed_by = nullif(auth.jwt() ->> 'email', ''),
        confirmed_at = now(), amount = rowlog.amount, reference_no = coalesce(norm, reference_no),
        invoice_id = open_invoice, cutoff = public.collection_cutoff(coalesce(rowlog.collection_date, current_date))
    where id = rowlog.payment_id
    returning id into pay_id;
  else
    insert into public.payments (
      invoice_id, customer_id, amount, method, reference_no, status, source, confirmed_by, confirmed_at, cutoff
    ) values (
      open_invoice, rowlog.customer_id, rowlog.amount, coalesce(nullif(rowlog.mode, ''), 'gcash'),
      norm, 'confirmed', 'admin', nullif(auth.jwt() ->> 'email', ''), now(),
      public.collection_cutoff(coalesce(rowlog.collection_date, current_date))
    ) returning id into pay_id;
  end if;
  select id into ref_id from public.gcash_refs
  where ref_number = norm and duplicate_flag = false and payment_id is null
  limit 1;
  if ref_id is not null then
    update public.gcash_refs set status = 'processed', payment_id = pay_id where id = ref_id;
  end if;
  update public.virtual_logbook
  set status = 'processed', match_reason = 'Manual override', payment_id = pay_id,
      gcash_ref_id = ref_id, processed_at = now(),
      cutoff = public.collection_cutoff(coalesce(collection_date, current_date))
  where id = p_id;
  return json_build_object('ok', true, 'id', pay_id);
end;
$$;

create or replace function public.portal_receipt(token text, p_logbook uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  cust public.customers%rowtype;
  rowlog public.virtual_logbook%rowtype;
  bill_amount numeric;
  paid_sum numeric;
begin
  cust := public.portal_customer(token);
  select * into rowlog from public.virtual_logbook
  where id = p_logbook and customer_id = cust.id and status = 'processed';
  if not found then
    raise exception 'Receipt was not found.';
  end if;
  select i.amount into bill_amount
  from public.payments p
  join public.invoices i on i.id = p.invoice_id
  where p.id = rowlog.payment_id;
  select coalesce(sum(amount), 0) into paid_sum
  from public.payments
  where invoice_id = (
    select invoice_id from public.payments where id = rowlog.payment_id
  ) and status = 'confirmed';
  return json_build_object(
    'ok', true,
    'name', coalesce(rowlog.client_name, cust.name),
    'account_number', cust.account_number,
    'date', rowlog.collection_date,
    'reference', rowlog.gcash_ref,
    'month', rowlog.period_label,
    'amount', rowlog.amount,
    'balance', coalesce(bill_amount, 0) - coalesce(paid_sum, 0),
    'cutoff', rowlog.cutoff,
    'image_base64', rowlog.image_base64,
    'content_type', coalesce(rowlog.content_type, 'image/jpeg')
  );
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
      'wallet_credit', coalesce(cust.wallet_credit, 0),
      'due_date_number', cust.due_date_number
    ),
    'invoices', coalesce((
      select json_agg(json_build_object(
        'id', i.id,
        'period', i.period,
        'period_label', i.period_label,
        'bill_number', i.bill_number,
        'amount', i.amount,
        'previous_balance', i.previous_balance,
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
        'reject_reason', p.reject_reason,
        'cutoff', p.cutoff
      ) order by p.submitted_at desc)
      from public.payments p
      where p.customer_id = cust.id
    ), '[]'::json),
    'receipts', coalesce((
      select json_agg(json_build_object(
        'id', l.id,
        'date', l.collection_date,
        'reference', l.gcash_ref,
        'amount', l.amount,
        'month', l.period_label,
        'cutoff', l.cutoff,
        'status', l.status
      ) order by l.processed_at desc)
      from public.virtual_logbook l
      where l.customer_id = cust.id and l.status = 'processed'
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

revoke all on function public.normalize_gcash_ref(text) from public;
revoke all on function public.collection_cutoff(date) from public;
revoke all on function public.clamp_due_date(integer, integer, integer) from public;
revoke all on function public.next_fiberbro_account(uuid) from public;
revoke all on function public.next_bill_number() from public;
revoke all on function public.apply_invoice_payment_state(uuid) from public;
revoke all on function public.stamp_payment_confirmation() from public;
revoke all on function public.generate_upcoming_bills_job() from public;
revoke all on function public.generate_upcoming_bills() from public;
revoke all on function public.auto_match_logbook(uuid) from public;
revoke all on function public.add_gcash_refs(uuid, text) from public;
revoke all on function public.manual_process_logbook(uuid) from public;
revoke all on function public.portal_receipt(text, uuid) from public;
revoke all on function public.portal_me(text) from public;

grant execute on function public.generate_upcoming_bills() to authenticated;
grant execute on function public.add_gcash_refs(uuid, text) to authenticated;
grant execute on function public.manual_process_logbook(uuid) to authenticated;
grant execute on function public.portal_receipt(text, uuid) to anon, authenticated;
grant execute on function public.portal_me(text) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('fiberbro_generate_bills');
    exception when others then
      null;
    end;
    perform cron.schedule(
      'fiberbro_generate_bills',
      '15 16 * * *',
      'select public.generate_upcoming_bills_job()'
    );
  end if;
exception when others then
  null;
end $$;

-- Supabase grants execute on new public functions to anon and authenticated.
-- revoke from public does not remove those direct grants.
revoke execute on function public.generate_upcoming_bills_job(), public.auto_match_logbook(uuid),
  public.apply_invoice_payment_state(uuid), public.next_bill_number(), public.next_fiberbro_account(uuid)
  from public, anon, authenticated;
revoke execute on function public.generate_upcoming_bills(), public.add_gcash_refs(uuid, text),
  public.manual_process_logbook(uuid) from public, anon;
revoke execute on function
  public.customers_before_insert(),
  public.customers_fill_due_day(),
  public.stamp_payment_confirmation(),
  public.sync_invoice_from_payment(),
  public.trg_auto_match_logbook(),
  public.trg_auto_match_gcash_ref(),
  public.virtual_logbook_fill(),
  public.trg_logbook_from_proof(),
  public.normalize_gcash_ref(text),
  public.collection_cutoff(date),
  public.clamp_due_date(integer, integer, integer)
  from public, anon, authenticated;

-- Phase 2 operations. supabase/migrations/20261121_phase2_ops.sql
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

    if new.stage = 'in_progress' and new.investor_id is null then
      raise exception 'Assign an investor before marking this customer in progress.';
    end if;
    if new.stage = 'inquiry' and old.stage is distinct from 'inquiry' and new.investor_id is not null then
      raise exception 'Clear the investor before moving this customer back to inquiry.';
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
  new.email_address := coalesce(nullif(btrim(new.email_address), ''), nullif(btrim(new.email), ''));
  new.fb_account := coalesce(nullif(btrim(new.fb_account), ''), nullif(btrim(new.facebook_name), ''));
  return new;
end;
$$;

-- Keep the phase 1 blank-to-null email and Facebook fallback.
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

  new.email_address := coalesce(nullif(btrim(new.email_address), ''), nullif(btrim(new.email), ''));
  new.fb_account := coalesce(nullif(btrim(new.fb_account), ''), nullif(btrim(new.facebook_name), ''));

  if new.account_number is null or btrim(new.account_number) = '' then
    new.account_number := public.next_fiberbro_account(new.investor_id);
  end if;

  if new.due_date_number is null and new.installation_date is not null then
    new.due_date_number := extract(day from new.installation_date)::integer;
  end if;

  new.account_status := public.stage_label(new.stage);
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

-- An installation invoice must not block the monthly bill for the same period.
create or replace function public.generate_upcoming_bills_job()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cust record;
  v_step integer;
  v_due_on date;
  v_period_key text;
  v_label text;
  v_prev_bal numeric;
  v_inserted integer := 0;
  v_fee numeric;
begin
  for v_cust in
    select c.id, c.due_date_number, c.installation_date, c.monthly_bill, c.price
    from public.customers c
    where c.stage = 'active'
  loop
    for v_step in 0..1 loop
      v_due_on := public.clamp_due_date(
        extract(year from (current_date + make_interval(months => v_step)))::integer,
        extract(month from (current_date + make_interval(months => v_step)))::integer,
        coalesce(v_cust.due_date_number, extract(day from v_cust.installation_date)::integer, 1)
      );
      if current_date < v_due_on - 10 or current_date > v_due_on + 5 then
        continue;
      end if;
      v_period_key := to_char(v_due_on, 'YYYY-MM');
      v_label := to_char(v_due_on, 'Mon_YYYY');
      if exists (
        select 1 from public.invoices i
        where i.customer_id = v_cust.id
          and i.period = v_period_key
          and i.invoice_kind = 'monthly'
      ) then
        continue;
      end if;
      v_fee := coalesce(v_cust.monthly_bill, v_cust.price, 0);
      if v_fee <= 0 then
        continue;
      end if;
      select coalesce(sum(greatest(i.amount - coalesce(paid.total, 0), 0)), 0)
        into v_prev_bal
      from public.invoices i
      left join (
        select p.invoice_id, sum(p.amount) as total
        from public.payments p
        where p.status = 'confirmed'
        group by p.invoice_id
      ) paid on paid.invoice_id = i.id
      where i.customer_id = v_cust.id
        and i.invoice_kind = 'monthly'
        and i.status in ('unpaid', 'pending')
        and i.period < v_period_key;
      insert into public.invoices (
        customer_id, period, period_label, bill_number, amount, previous_balance,
        due_date, status, created_by, invoice_kind
      ) values (
        v_cust.id, v_period_key, v_label, public.next_bill_number(), v_fee, v_prev_bal,
        v_due_on, 'unpaid', 'auto', 'monthly'
      );
      v_inserted := v_inserted + 1;
    end loop;
  end loop;
  return v_inserted;
end;
$$;

-- Expenses keep Gas/Meals/… and also accept Operational and Personal.
alter table public.expenses add column if not exists account_code text;
alter table public.expenses add column if not exists scope text;
alter table public.expenses add column if not exists auto boolean not null default false;
alter table public.expenses alter column status set default 'approved';

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

-- One mapper for ticket expenses and later commission reports.
-- Investor code wins. Otherwise the PPPoE prefix before the first hyphen.
-- MAL and AL are excluded. A and an exact A prefix map to ALVIN.
create or replace function public.customer_account_code(p_customer uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_investor_code text;
  v_pppoe text;
  v_token text;
  v_mapped text;
begin
  select upper(btrim(i.code)), upper(btrim(c.pppoe))
    into v_investor_code, v_pppoe
  from public.customers c
  left join public.investors i on i.id = c.investor_id
  where c.id = p_customer;

  v_token := nullif(v_investor_code, '');
  if v_token is null and v_pppoe is not null then
    v_token := nullif(split_part(v_pppoe, '-', 1), '');
  end if;
  if v_token is null or v_token in ('MAL', 'AL') then
    return null;
  end if;

  v_mapped := case v_token
    when 'A' then 'ALVIN'
    when 'J' then 'JOLLI'
    when 'AJ' then 'AINA'
    when 'AA' then 'AA'
    when 'NELSONANN' then 'NELSON'
    when 'HADJ' then 'HADJ'
    when 'NELSONHADJ' then 'LOKAL'
    when 'LOKAL' then 'LOKAL'
    when 'LOKAL(NELSONHADJ)' then 'LOKAL'
    else v_token
  end;

  if v_mapped in ('MAL', 'AL') then
    return null;
  end if;
  if v_mapped in (
    'AA', 'AINA', 'ALVIN', 'ANN', 'CHES', 'FB', 'HADJ', 'JACQ', 'JOLLI',
    'LOKAL', 'NELSON', 'NOVA', 'NOVAANN', 'NOVAREY', 'OSCAR', 'REY'
  ) then
    return v_mapped;
  end if;
  return null;
end;
$$;

create or replace function public.account_code_for(p_customer uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.customer_account_code(p_customer);
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
  v_tix public.ops_tickets%rowtype;
  v_mat record;
  v_price numeric;
  v_code text;
  v_made integer := 0;
begin
  select * into v_tix from public.ops_tickets where id = p_ticket;
  if v_tix.id is null or v_tix.status is distinct from 'Closed - Resolved' then
    return 0;
  end if;
  v_code := public.customer_account_code(v_tix.customer_id);
  for v_mat in
    select m.* from public.ticket_materials m
    where m.ticket_id = v_tix.id
      and m.item in ('SC Connector', 'Changed Modem', 'Rewiring', 'Changed power adaptor')
  loop
    v_price := v_mat.unit_cost;
    if v_price is null then
      select mp.unit_cost into v_price from public.material_prices mp where mp.item = v_mat.item;
    end if;
    if v_price is null then
      continue;
    end if;
    if exists (
      select 1 from public.expenses e
      where e.ticket_id = v_tix.id and e.scope = v_mat.item and e.auto
    ) then
      continue;
    end if;
    insert into public.expenses (
      category, amount, expense_date, remarks, status, created_by,
      account_code, scope, ticket_id, auto
    ) values (
      'Operational',
      round(v_mat.qty * v_price, 2),
      current_date,
      'Auto from ' || v_tix.ticket_no || ' · ' || v_mat.item,
      'approved',
      public.ops_actor(),
      v_code,
      v_mat.item,
      v_tix.id,
      true
    );
    v_made := v_made + 1;
  end loop;
  return v_made;
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
  v_made integer;
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot close this ticket.';
  end if;
  update public.ops_tickets t
  set status = 'Closed - Resolved',
      resolution = coalesce(nullif(btrim(p_resolution), ''), t.resolution)
  where t.id = p_ticket;
  v_made := public.post_ticket_expenses(p_ticket);
  return json_build_object('ok', true, 'expenses', v_made);
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
  v_tix public.ops_tickets%rowtype;
  v_cust public.customers%rowtype;
  v_pppoe text;
  v_digits text;
  v_fee numeric;
  v_method text;
  v_inv uuid;
  v_period text;
begin
  if not public.ticket_visible_to_caller(p_ticket) then
    raise exception 'You cannot complete this installation.';
  end if;
  select * into v_tix from public.ops_tickets where id = p_ticket;
  if v_tix.id is null then
    raise exception 'Ticket not found.';
  end if;
  if v_tix.ticket_type is distinct from 'INSTALLATION' then
    raise exception 'This ticket is not an installation.';
  end if;
  if v_tix.customer_id is null then
    raise exception 'Assign a customer first.';
  end if;
  if v_tix.status = 'Closed - Resolved' then
    return json_build_object('ok', true, 'already', true, 'customer_id', v_tix.customer_id);
  end if;
  select * into v_cust from public.customers where id = v_tix.customer_id;
  if v_cust.investor_id is null then
    raise exception 'Assign an investor before completing the installation.';
  end if;

  if nullif(btrim(v_cust.pppoe), '') is not null then
    v_pppoe := btrim(v_cust.pppoe);
  else
    v_digits := nullif(right(regexp_replace(coalesce(v_cust.account_number, ''), '\D', '', 'g'), 6), '');
    if v_digits is not null then
      v_pppoe := 'fb' || v_digits;
    else
      v_pppoe := 'fb' || substring(encode(extensions.gen_random_bytes(3), 'hex') from 1 for 6);
    end if;
  end if;

  perform set_config('fiberbro.allow_stage_jump', '1', true);
  update public.customers
  set stage = 'active',
      account_status = 'Newly Installed',
      pppoe = v_pppoe,
      lp = coalesce(nullif(btrim(p_lp), ''), lp),
      nap = coalesce(nullif(btrim(p_nap), ''), nap),
      port = coalesce(nullif(btrim(p_port), ''), port),
      modem_serial = coalesce(nullif(btrim(p_modem_serial), ''), modem_serial),
      installation_date = coalesce(installation_date, current_date),
      installation_status = 'Done',
      installed_by = public.ops_actor()
  where id = v_cust.id;

  if nullif(btrim(p_modem_serial), '') is not null then
    update public.modems m
    set customer_id = v_cust.id,
        availability = 'In Used'
    where lower(m.serial) = lower(btrim(p_modem_serial));
    insert into public.modem_log (modem_id, action, customer_id, note, actor)
    select m.id, 'Assigned', v_cust.id, 'Installation ' || v_tix.ticket_no, public.ops_actor()
    from public.modems m
    where lower(m.serial) = lower(btrim(p_modem_serial));
  end if;

  v_method := lower(btrim(coalesce(p_pay_method, '')));
  if v_method not in ('gcash', 'cash') then
    v_method := '';
  end if;
  v_fee := p_pay_amount;
  if coalesce(v_fee, 0) <= 0 then
    select nullif(s.value, '')::numeric into v_fee
    from public.app_settings s
    where s.key = 'installation_fee';
  end if;
  if v_method <> '' and coalesce(v_fee, 0) > 0 then
    v_period := to_char(current_date, 'YYYY-MM');
    insert into public.invoices (customer_id, period, amount, due_date, status, notes, created_by, invoice_kind)
    values (v_cust.id, v_period, v_fee, current_date, 'unpaid', 'Installation fee', public.ops_actor(), 'installation')
    on conflict (customer_id, period, invoice_kind) do update
      set amount = excluded.amount
    returning id into v_inv;
    insert into public.payments (
      invoice_id, customer_id, amount, method, reference_no, status, source, notes
    ) values (
      v_inv, v_cust.id, v_fee, v_method, nullif(btrim(p_pay_ref), ''), 'confirmed', 'admin', 'Installation fee'
    );
  end if;

  update public.ops_tickets
  set status = 'Closed - Resolved',
      resolution = coalesce(resolution, 'Installed')
  where id = v_tix.id;

  return json_build_object('ok', true, 'customer_id', v_cust.id, 'pppoe', v_pppoe, 'amount', v_fee);
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
  public.customer_account_code(uuid),
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

-- Phase 3 payroll. supabase/migrations/20261122_phase3_payroll.sql
-- Phase 3 payroll, attendance, and the office kiosk.
-- Idempotent. Does not drop customer rows or customer columns.
-- Apply after phase 1. If phase 2 already created public.staff, this file
-- leaves that table in place.
-- Account codes MAL and AL are not used here.
--
-- Kiosk selfies are stored in attendance_photos (no anon read) because the
-- office phone has a device token, not a user login. The private bucket
-- attendance-photos is for payroll uploads of the same proof.

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

alter table public.staff enable row level security;
revoke all on table public.staff from public, anon;
grant select, insert, update, delete on public.staff to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'staff' and policyname = 'staff_admin_all'
  ) then
    create policy staff_admin_all on public.staff
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

create or replace function public.is_payroll()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1
    from public.staff
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and role in ('payroll_admin', 'admin')
      and active
  );
$$;

create or replace function public.payroll_actor()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(auth.jwt() ->> 'email', ''), 'system');
$$;

-- Late math. Times are already Asia/Manila clock times.
-- 0-14 minutes late is free. Each full 15 minutes is ₱30.
-- 120 minutes or more is a half day and the late penalty is not charged.
create or replace function public.payroll_day_effect(p_shift time, p_clock time, p_rest boolean)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  mins integer;
  half boolean;
  penalty numeric;
begin
  if p_clock is null or p_shift is null then
    return jsonb_build_object('late_minutes', 0, 'half_day', false, 'late_penalty', 0);
  end if;
  mins := greatest(0, floor(extract(epoch from (p_clock - p_shift)) / 60))::integer;
  half := mins >= 120 and not coalesce(p_rest, false);
  if half or coalesce(p_rest, false) then
    penalty := 0;
  else
    penalty := (mins / 15) * 30;
  end if;
  return jsonb_build_object('late_minutes', mins, 'half_day', half, 'late_penalty', penalty);
end;
$$;

create or replace function public.payroll_cutoff(p_date date)
returns table (cutoff_start date, cutoff_end date)
language plpgsql
immutable
set search_path = public
as $$
declare
  month_end date;
begin
  month_end := (date_trunc('month', p_date)::date + interval '1 month - 1 day')::date;
  if extract(day from p_date) <= 15 then
    cutoff_start := date_trunc('month', p_date)::date;
    cutoff_end := date_trunc('month', p_date)::date + 14;
  else
    cutoff_start := date_trunc('month', p_date)::date + 15;
    cutoff_end := month_end;
  end if;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Employees and attendance
-- ---------------------------------------------------------------------------

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references public.staff (id) on delete set null,
  name text not null,
  position text,
  rate_type text not null default 'regular' check (rate_type in ('regular', 'fixed')),
  monthly_rate numeric(12, 2) not null default 0 check (monthly_rate >= 0),
  shift_start time not null default time '09:00',
  shift_end time not null default time '18:00',
  rest_day smallint not null default 0 check (rest_day between 0 and 6),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.employee_faces (
  employee_id uuid primary key references public.employees (id) on delete cascade,
  descriptor numeric[] not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.kiosk_devices (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  token_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_punches (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  work_date date not null,
  punch_type text not null check (punch_type in ('clock_in', 'lunch_out', 'lunch_in', 'clock_out')),
  punched_at timestamptz not null default now(),
  source text not null check (source in ('face', 'manual')),
  device_id uuid references public.kiosk_devices (id) on delete set null,
  reason text,
  entered_by text,
  created_at timestamptz not null default now(),
  unique (employee_id, work_date, punch_type)
);

create index if not exists attendance_punches_day_idx
  on public.attendance_punches (employee_id, work_date);

create table if not exists public.attendance_photos (
  id uuid primary key default gen_random_uuid(),
  punch_id uuid not null references public.attendance_punches (id) on delete cascade,
  content_type text not null default 'image/jpeg',
  image_base64 text not null,
  created_at timestamptz not null default now()
);

create index if not exists attendance_photos_punch_idx on public.attendance_photos (punch_id);

create table if not exists public.attendance_days (
  employee_id uuid not null references public.employees (id) on delete cascade,
  work_date date not null,
  half_day boolean not null default false,
  half_reason text,
  rest_day_work boolean not null default false,
  ot_hours numeric(8, 2) not null default 0 check (ot_hours >= 0),
  ot_status text not null default 'pending' check (ot_status in ('pending', 'approved', 'rejected')),
  primary key (employee_id, work_date)
);

create or replace function public.attendance_flag_rest_day()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rest smallint;
begin
  if new.punch_type is distinct from 'clock_in' then
    return new;
  end if;
  select e.rest_day into v_rest from public.employees e where e.id = new.employee_id;
  if v_rest is not null and extract(dow from new.work_date)::integer = v_rest then
    insert into public.attendance_days (employee_id, work_date, rest_day_work)
    values (new.employee_id, new.work_date, true)
    on conflict (employee_id, work_date) do update
      set rest_day_work = true;
  end if;
  return new;
end;
$$;

drop trigger if exists attendance_punches_rest_day on public.attendance_punches;
create trigger attendance_punches_rest_day
  after insert on public.attendance_punches
  for each row execute function public.attendance_flag_rest_day();

create table if not exists public.attendance_audit (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references public.employees (id) on delete set null,
  punch_id uuid,
  action text not null,
  reason text,
  actor text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.cash_advances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  amount numeric(12, 2) not null check (amount >= 0),
  advance_date date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.incentives (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  amount numeric(12, 2) not null check (amount >= 0),
  incentive_date date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.payroll_gas (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  amount numeric(12, 2) not null check (amount >= 0),
  gas_date date not null default current_date,
  deduct boolean not null default false,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.violations (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  amount numeric(12, 2) not null check (amount >= 0),
  violation_date date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  cutoff_start date not null,
  cutoff_end date not null,
  status text not null default 'draft' check (status in ('draft', 'locked')),
  created_by text,
  created_at timestamptz not null default now(),
  locked_by text,
  locked_at timestamptz,
  unique (cutoff_start, cutoff_end)
);

create table if not exists public.payslips (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.payroll_runs (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  rate_type text not null,
  monthly_rate numeric(12, 2) not null,
  daily_rate numeric(12, 2) not null,
  days_present integer not null,
  half_days integer not null,
  ot_hours numeric(8, 2) not null,
  ot_pay numeric(12, 2) not null,
  incentives numeric(12, 2) not null,
  earnings numeric(12, 2) not null,
  late_penalty numeric(12, 2) not null,
  cash_advance numeric(12, 2) not null,
  other_deductions numeric(12, 2) not null,
  net_pay numeric(12, 2) not null,
  detail jsonb not null default '{}'::jsonb,
  unique (run_id, employee_id)
);

-- ---------------------------------------------------------------------------
-- Pay math used by the run and by the rollback test
-- ---------------------------------------------------------------------------

create or replace function public.payroll_earnings(
  p_rate_type text,
  p_monthly numeric,
  p_days integer,
  p_half integer,
  p_ot_hours numeric,
  p_incentives numeric
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  daily numeric := round(coalesce(p_monthly, 0) / 26, 2);
  ot_pay numeric := round((daily / 8) * coalesce(p_ot_hours, 0), 2);
  base numeric;
begin
  if p_rate_type = 'fixed' then
    base := round(coalesce(p_monthly, 0) / 2, 2);
  else
    base := round(daily * (coalesce(p_days, 0) - (0.5 * coalesce(p_half, 0))), 2);
  end if;
  return jsonb_build_object(
    'daily_rate', daily,
    'ot_pay', ot_pay,
    'earnings', round(base + ot_pay + coalesce(p_incentives, 0), 2)
  );
end;
$$;

create or replace function public.build_payroll(p_start date, p_end date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_emp record;
  v_day date;
  v_effect jsonb;
  v_pay jsonb;
  v_days integer;
  v_half_days integer;
  v_late numeric;
  v_ot numeric;
  v_incentive numeric;
  v_cash numeric;
  v_other numeric;
  v_earnings numeric;
  v_net numeric;
  v_made integer := 0;
  v_detail jsonb;
  v_clock timestamptz;
  v_manual_half boolean;
  v_rest boolean;
  v_clock_time time;
  v_day_half boolean;
  v_day_penalty numeric;
  v_present boolean;
  v_rest_work boolean;
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can build a payroll.';
  end if;
  if p_end < p_start then
    raise exception 'Cut-off end is before the start.';
  end if;
  if exists (
    select 1 from public.payroll_runs
    where cutoff_start = p_start and cutoff_end = p_end and status = 'locked'
  ) then
    raise exception 'This cut-off is locked.';
  end if;

  insert into public.payroll_runs (cutoff_start, cutoff_end, status, created_by)
  values (p_start, p_end, 'draft', public.payroll_actor())
  on conflict (cutoff_start, cutoff_end) do update
    set created_by = excluded.created_by
  returning id into v_run_id;

  delete from public.payslips p where p.run_id = v_run_id;

  for v_emp in select e.* from public.employees e where e.active order by e.name loop
    v_days := 0;
    v_half_days := 0;
    v_late := 0;
    v_detail := '[]'::jsonb;
    for v_day in
      select d::date
      from generate_series(p_start, p_end, interval '1 day') as d
    loop
      v_clock := null;
      v_manual_half := false;
      v_rest_work := false;
      select ap.punched_at into v_clock
      from public.attendance_punches ap
      where ap.employee_id = v_emp.id and ap.work_date = v_day and ap.punch_type = 'clock_in';
      select ad.half_day, ad.rest_day_work into v_manual_half, v_rest_work
      from public.attendance_days ad
      where ad.employee_id = v_emp.id and ad.work_date = v_day;
      v_rest := extract(dow from v_day)::integer = v_emp.rest_day;
      v_rest_work := coalesce(v_rest_work, false) or (v_rest and v_clock is not null);
      v_present := v_clock is not null or coalesce(v_manual_half, false);
      if not v_present then
        continue;
      end if;
      v_days := v_days + 1;
      v_clock_time := (v_clock at time zone 'Asia/Manila')::time;
      v_effect := public.payroll_day_effect(v_emp.shift_start, v_clock_time, v_rest);
      v_day_half := coalesce(v_manual_half, false) or coalesce((v_effect ->> 'half_day')::boolean, false);
      if v_day_half then
        v_half_days := v_half_days + 1;
        v_day_penalty := 0;
      else
        v_day_penalty := coalesce((v_effect ->> 'late_penalty')::numeric, 0);
      end if;
      v_late := v_late + v_day_penalty;
      v_detail := v_detail || jsonb_build_array(jsonb_build_object(
        'date', v_day,
        'late_minutes', coalesce((v_effect ->> 'late_minutes')::integer, 0),
        'half_day', v_day_half,
        'late_penalty', v_day_penalty,
        'rest_day_work', v_rest_work
      ));
    end loop;

    select coalesce(sum(ad.ot_hours), 0) into v_ot
    from public.attendance_days ad
    where ad.employee_id = v_emp.id and ad.work_date between p_start and p_end and ad.ot_status = 'approved';
    select coalesce(sum(i.amount), 0) into v_incentive
    from public.incentives i
    where i.employee_id = v_emp.id and i.incentive_date between p_start and p_end;
    select coalesce(sum(ca.amount), 0) into v_cash
    from public.cash_advances ca
    where ca.employee_id = v_emp.id and ca.advance_date between p_start and p_end;
    select coalesce(sum(x.amount), 0) into v_other
    from (
      select v.amount from public.violations v
      where v.employee_id = v_emp.id and v.violation_date between p_start and p_end
      union all
      select g.amount from public.payroll_gas g
      where g.employee_id = v_emp.id and g.gas_date between p_start and p_end and g.deduct
    ) x;

    -- Fixed staff still pay the late penalty below. Their base is monthly/2.
    v_pay := public.payroll_earnings(v_emp.rate_type, v_emp.monthly_rate, v_days, v_half_days, v_ot, v_incentive);
    v_earnings := (v_pay ->> 'earnings')::numeric;
    v_net := round(v_earnings - v_late - v_cash - v_other, 2);
    insert into public.payslips (
      run_id, employee_id, rate_type, monthly_rate, daily_rate, days_present, half_days,
      ot_hours, ot_pay, incentives, earnings, late_penalty, cash_advance, other_deductions, net_pay, detail
    ) values (
      v_run_id, v_emp.id, v_emp.rate_type, v_emp.monthly_rate, (v_pay ->> 'daily_rate')::numeric,
      v_days, v_half_days, v_ot, (v_pay ->> 'ot_pay')::numeric, v_incentive,
      v_earnings, v_late, v_cash, v_other, v_net, v_detail
    );
    v_made := v_made + 1;
  end loop;

  return json_build_object('ok', true, 'run_id', v_run_id, 'payslips', v_made);
end;
$$;

create or replace function public.lock_payroll(p_run uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can lock a payroll.';
  end if;
  update public.payroll_runs r
  set status = 'locked', locked_by = public.payroll_actor(), locked_at = now()
  where r.id = p_run and r.status = 'draft';
  return json_build_object('ok', true);
end;
$$;

create or replace function public.unlock_payroll(p_run uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can unlock a payroll.';
  end if;
  update public.payroll_runs r
  set status = 'draft', locked_by = null, locked_at = null
  where r.id = p_run and r.status = 'locked';
  return json_build_object('ok', true);
end;
$$;

create or replace function public.save_employee(
  p_id uuid,
  p_name text,
  p_position text,
  p_rate_type text,
  p_monthly numeric,
  p_shift_start time,
  p_shift_end time,
  p_rest smallint,
  p_staff uuid,
  p_active boolean
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can save an employee.';
  end if;
  if p_rate_type not in ('regular', 'fixed') then
    raise exception 'Rate type must be regular or fixed.';
  end if;
  if p_id is null then
    insert into public.employees (name, position, rate_type, monthly_rate, shift_start, shift_end, rest_day, staff_id, active)
    values (btrim(p_name), nullif(btrim(p_position), ''), p_rate_type, coalesce(p_monthly, 0),
      coalesce(p_shift_start, time '09:00'), coalesce(p_shift_end, time '18:00'), coalesce(p_rest, 0), p_staff, coalesce(p_active, true))
    returning id into v_new_id;
  else
    update public.employees e
    set name = btrim(p_name),
        position = nullif(btrim(p_position), ''),
        rate_type = p_rate_type,
        monthly_rate = coalesce(p_monthly, 0),
        shift_start = coalesce(p_shift_start, time '09:00'),
        shift_end = coalesce(p_shift_end, time '18:00'),
        rest_day = coalesce(p_rest, 0),
        staff_id = p_staff,
        active = coalesce(p_active, true)
    where e.id = p_id
    returning e.id into v_new_id;
  end if;
  return json_build_object('ok', true, 'id', v_new_id);
end;
$$;

create or replace function public.enroll_employee_face(p_employee uuid, p_descriptor numeric[])
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can enroll a face.';
  end if;
  if p_descriptor is null or cardinality(p_descriptor) <> 128 then
    raise exception 'Face descriptor must be 128 numbers.';
  end if;
  insert into public.employee_faces (employee_id, descriptor)
  values (p_employee, p_descriptor)
  on conflict (employee_id) do update
    set descriptor = excluded.descriptor, updated_at = now();
  return json_build_object('ok', true);
end;
$$;

create or replace function public.register_kiosk_device(p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_token text := encode(extensions.gen_random_bytes(24), 'hex');
  token_hash text := encode(extensions.digest(raw_token, 'sha256'), 'hex');
  new_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can register the kiosk phone.';
  end if;
  insert into public.kiosk_devices (name, token_hash)
  values (coalesce(nullif(btrim(p_name), ''), 'Office phone'), token_hash)
  returning id into new_id;
  return json_build_object('ok', true, 'id', new_id, 'token', raw_token);
end;
$$;

create or replace function public.kiosk_device_id(p_token text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  found uuid;
begin
  select id into found
  from public.kiosk_devices
  where active
    and token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  return found;
end;
$$;

create or replace function public.kiosk_roster(p_token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.kiosk_device_id(p_token) is null then
    raise exception 'This phone is not the registered kiosk.';
  end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', e.id,
      'name', e.name,
      'descriptor', f.descriptor
    ) order by e.name)
    from public.employees e
    join public.employee_faces f on f.employee_id = e.id
    where e.active
  ), '[]'::json);
end;
$$;

create or replace function public.kiosk_punch(
  p_token text,
  p_employee uuid,
  p_type text,
  p_selfie text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  device uuid := public.kiosk_device_id(p_token);
  today date := (now() at time zone 'Asia/Manila')::date;
  kind text := p_type;
  punch uuid;
begin
  if device is null then
    raise exception 'This phone is not the registered kiosk.';
  end if;
  if nullif(btrim(p_selfie), '') is null or length(p_selfie) < 100 then
    raise exception 'A selfie is required.';
  end if;
  if not exists (select 1 from public.employees where id = p_employee and active) then
    raise exception 'Employee not found.';
  end if;
  if kind is null or kind = '' or kind = 'next' then
    select slot into kind
    from (values (1, 'clock_in'), (2, 'lunch_out'), (3, 'lunch_in'), (4, 'clock_out')) as slots(n, slot)
    where not exists (
      select 1 from public.attendance_punches
      where employee_id = p_employee and work_date = today and punch_type = slot
    )
    order by n
    limit 1;
  end if;
  if kind not in ('clock_in', 'lunch_out', 'lunch_in', 'clock_out') then
    raise exception 'Unknown punch.';
  end if;
  if exists (
    select 1 from public.attendance_punches
    where employee_id = p_employee and work_date = today and punch_type = kind
  ) then
    raise exception 'That punch is already recorded for today.';
  end if;
  insert into public.attendance_punches (employee_id, work_date, punch_type, punched_at, source, device_id, entered_by)
  values (p_employee, today, kind, now(), 'face', device, 'kiosk')
  returning id into punch;
  insert into public.attendance_photos (punch_id, content_type, image_base64)
  values (punch, 'image/jpeg', p_selfie);
  return json_build_object('ok', true, 'punch_id', punch, 'punch_type', kind, 'work_date', today);
end;
$$;

create or replace function public.manual_attendance(
  p_employee uuid,
  p_date date,
  p_type text,
  p_at timestamptz,
  p_reason text,
  p_selfie text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  punch uuid;
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can encode attendance by hand.';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A reason is required for a manual entry.';
  end if;
  if p_type not in ('clock_in', 'lunch_out', 'lunch_in', 'clock_out') then
    raise exception 'Unknown punch.';
  end if;
  insert into public.attendance_punches (employee_id, work_date, punch_type, punched_at, source, reason, entered_by)
  values (p_employee, p_date, p_type, coalesce(p_at, now()), 'manual', btrim(p_reason), public.payroll_actor())
  on conflict (employee_id, work_date, punch_type) do update
    set punched_at = excluded.punched_at,
        source = 'manual',
        reason = excluded.reason,
        entered_by = excluded.entered_by
  returning id into punch;
  if nullif(btrim(p_selfie), '') is not null then
    insert into public.attendance_photos (punch_id, content_type, image_base64)
    values (punch, 'image/jpeg', p_selfie);
  end if;
  insert into public.attendance_audit (employee_id, punch_id, action, reason, actor)
  values (p_employee, punch, 'manual_' || p_type, btrim(p_reason), public.payroll_actor());
  return json_build_object('ok', true, 'punch_id', punch);
end;
$$;

create or replace function public.save_attendance_day(
  p_employee uuid,
  p_date date,
  p_half boolean,
  p_half_reason text,
  p_ot_hours numeric,
  p_approve boolean
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ot_status text := 'pending';
  v_old_hours numeric;
  v_old_status text;
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can update the day.';
  end if;
  if coalesce(p_approve, false) and not public.is_admin() then
    raise exception 'Only an admin can approve overtime.';
  end if;
  v_old_hours := null;
  v_old_status := null;
  select ad.ot_hours, ad.ot_status into v_old_hours, v_old_status
  from public.attendance_days ad
  where ad.employee_id = p_employee and ad.work_date = p_date;
  if public.is_admin() and coalesce(p_approve, false) then
    v_ot_status := 'approved';
  elsif not public.is_admin() and (
    v_old_status = 'approved'
    or v_old_hours is distinct from coalesce(p_ot_hours, 0)
  ) then
    v_ot_status := 'pending';
  elsif coalesce(p_ot_hours, 0) = 0 then
    v_ot_status := 'pending';
  elsif v_old_status is not null then
    v_ot_status := v_old_status;
  end if;
  insert into public.attendance_days (employee_id, work_date, half_day, half_reason, ot_hours, ot_status)
  values (p_employee, p_date, coalesce(p_half, false), nullif(btrim(p_half_reason), ''), coalesce(p_ot_hours, 0), v_ot_status)
  on conflict (employee_id, work_date) do update
    set half_day = excluded.half_day,
        half_reason = excluded.half_reason,
        ot_hours = excluded.ot_hours,
        ot_status = excluded.ot_status;
  insert into public.attendance_audit (employee_id, action, reason, actor, detail)
  values (p_employee, 'day_update', nullif(btrim(p_half_reason), ''), public.payroll_actor(),
    jsonb_build_object('date', p_date, 'half_day', coalesce(p_half, false), 'ot_hours', coalesce(p_ot_hours, 0), 'approved', coalesce(p_approve, false)));
  return json_build_object('ok', true);
end;
$$;

create or replace function public.add_payroll_adjustment(
  p_kind text,
  p_employee uuid,
  p_amount numeric,
  p_date date,
  p_note text,
  p_deduct boolean
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can encode this.';
  end if;
  if coalesce(p_amount, 0) < 0 then
    raise exception 'Amount cannot be negative.';
  end if;
  if p_kind = 'cash_advance' then
    insert into public.cash_advances (employee_id, amount, advance_date, note, created_by)
    values (p_employee, p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.payroll_actor());
  elsif p_kind = 'incentive' then
    insert into public.incentives (employee_id, amount, incentive_date, note, created_by)
    values (p_employee, p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.payroll_actor());
  elsif p_kind = 'gas' then
    insert into public.payroll_gas (employee_id, amount, gas_date, deduct, note, created_by)
    values (p_employee, p_amount, coalesce(p_date, current_date), coalesce(p_deduct, false), nullif(btrim(p_note), ''), public.payroll_actor());
  elsif p_kind = 'violation' then
    insert into public.violations (employee_id, amount, violation_date, note, created_by)
    values (p_employee, p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.payroll_actor());
  else
    raise exception 'Unknown adjustment.';
  end if;
  return json_build_object('ok', true);
end;
$$;

create or replace function public.employee_id_for_caller()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select e.id
  from public.employees e
  join public.staff s on s.id = e.staff_id
  where lower(s.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and s.active
    and e.active
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- Payroll admins can read the run, punches, days, and kiosk list.
-- They cannot write those tables directly. Writes go through RPCs.
-- An employee linked to staff can read only their own DTR and payslips.
-- ---------------------------------------------------------------------------

alter table public.employees enable row level security;
alter table public.employee_faces enable row level security;
alter table public.kiosk_devices enable row level security;
alter table public.attendance_punches enable row level security;
alter table public.attendance_photos enable row level security;
alter table public.attendance_days enable row level security;
alter table public.attendance_audit enable row level security;
alter table public.cash_advances enable row level security;
alter table public.incentives enable row level security;
alter table public.payroll_gas enable row level security;
alter table public.violations enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payslips enable row level security;

revoke all on table public.employees from public, anon;
revoke all on table public.employee_faces from public, anon;
revoke all on table public.kiosk_devices from public, anon;
revoke all on table public.attendance_punches from public, anon;
revoke all on table public.attendance_photos from public, anon;
revoke all on table public.attendance_days from public, anon;
revoke all on table public.attendance_audit from public, anon;
revoke all on table public.cash_advances from public, anon;
revoke all on table public.incentives from public, anon;
revoke all on table public.payroll_gas from public, anon;
revoke all on table public.violations from public, anon;
revoke all on table public.payroll_runs from public, anon;
revoke all on table public.payslips from public, anon;

grant select, insert, update, delete on public.employees to authenticated;
grant select, insert, update, delete on public.employee_faces to authenticated;
grant select, insert, update, delete on public.kiosk_devices to authenticated;
grant select, insert, update, delete on public.attendance_punches to authenticated;
grant select on public.attendance_photos to authenticated;
grant select, insert, update, delete on public.attendance_days to authenticated;
grant select on public.attendance_audit to authenticated;
grant select, insert, update, delete on public.cash_advances to authenticated;
grant select, insert, update, delete on public.incentives to authenticated;
grant select, insert, update, delete on public.payroll_gas to authenticated;
grant select, insert, update, delete on public.violations to authenticated;
grant select, insert, update, delete on public.payroll_runs to authenticated;
grant select on public.payslips to authenticated;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'employees', 'employee_faces',
    'cash_advances', 'incentives', 'payroll_gas', 'violations'
  ]
  loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = tbl and policyname = tbl || '_payroll_all'
    ) then
      execute format(
        'create policy %I on public.%I for all to authenticated using (public.is_payroll()) with check (public.is_payroll())',
        tbl || '_payroll_all', tbl
      );
    end if;
  end loop;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_photos' and policyname = 'attendance_photos_payroll_read') then
    create policy attendance_photos_payroll_read on public.attendance_photos
      for select to authenticated using (public.is_payroll());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_audit' and policyname = 'attendance_audit_payroll_read') then
    create policy attendance_audit_payroll_read on public.attendance_audit
      for select to authenticated using (public.is_payroll());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'payslips' and policyname = 'payslips_payroll_read') then
    create policy payslips_payroll_read on public.payslips
      for select to authenticated using (public.is_payroll() or employee_id = public.employee_id_for_caller());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'employees' and policyname = 'employees_self_read') then
    create policy employees_self_read on public.employees
      for select to authenticated using (id = public.employee_id_for_caller());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_punches' and policyname = 'attendance_punches_read') then
    create policy attendance_punches_read on public.attendance_punches
      for select to authenticated using (public.is_payroll() or employee_id = public.employee_id_for_caller());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_days' and policyname = 'attendance_days_read') then
    create policy attendance_days_read on public.attendance_days
      for select to authenticated using (public.is_payroll() or employee_id = public.employee_id_for_caller());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_photos' and policyname = 'attendance_photos_self_read') then
    create policy attendance_photos_self_read on public.attendance_photos
      for select to authenticated using (
        exists (
          select 1 from public.attendance_punches ap
          where ap.id = punch_id and ap.employee_id = public.employee_id_for_caller()
        )
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'payroll_runs' and policyname = 'payroll_runs_read') then
    create policy payroll_runs_read on public.payroll_runs
      for select to authenticated using (
        public.is_payroll()
        or exists (
          select 1 from public.payslips ps
          where ps.run_id = payroll_runs.id and ps.employee_id = public.employee_id_for_caller()
        )
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'kiosk_devices' and policyname = 'kiosk_devices_read') then
    create policy kiosk_devices_read on public.kiosk_devices
      for select to authenticated using (public.is_payroll());
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attendance-photos',
  'attendance-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'attendance_photos_payroll_read'
  ) then
    create policy attendance_photos_payroll_read on storage.objects
      for select to authenticated
      using (bucket_id = 'attendance-photos' and public.is_payroll());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'attendance_photos_payroll_insert'
  ) then
    create policy attendance_photos_payroll_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'attendance-photos'
        and public.is_payroll()
        and name ~ '^manual/.+'
      );
  end if;
end $$;

revoke execute on function
  public.payroll_actor(),
  public.employee_id_for_caller(),
  public.attendance_flag_rest_day(),
  public.kiosk_device_id(text),
  public.payroll_day_effect(time, time, boolean),
  public.payroll_cutoff(date),
  public.payroll_earnings(text, numeric, integer, integer, numeric, numeric)
  from public, anon, authenticated;

revoke execute on function
  public.is_payroll(),
  public.build_payroll(date, date),
  public.lock_payroll(uuid),
  public.unlock_payroll(uuid),
  public.save_employee(uuid, text, text, text, numeric, time, time, smallint, uuid, boolean),
  public.enroll_employee_face(uuid, numeric[]),
  public.register_kiosk_device(text),
  public.kiosk_roster(text),
  public.kiosk_punch(text, uuid, text, text),
  public.manual_attendance(uuid, date, text, timestamptz, text, text),
  public.save_attendance_day(uuid, date, boolean, text, numeric, boolean),
  public.add_payroll_adjustment(text, uuid, numeric, date, text, boolean)
  from public, anon;

grant execute on function public.is_payroll() to authenticated;
grant execute on function public.payroll_day_effect(time, time, boolean) to authenticated;
grant execute on function public.payroll_cutoff(date) to authenticated;
grant execute on function public.payroll_earnings(text, numeric, integer, integer, numeric, numeric) to authenticated;
grant execute on function public.build_payroll(date, date) to authenticated;
grant execute on function public.employee_id_for_caller() to authenticated;
grant execute on function public.lock_payroll(uuid) to authenticated;
grant execute on function public.unlock_payroll(uuid) to authenticated;
grant execute on function public.save_employee(uuid, text, text, text, numeric, time, time, smallint, uuid, boolean) to authenticated;
grant execute on function public.enroll_employee_face(uuid, numeric[]) to authenticated;
grant execute on function public.register_kiosk_device(text) to authenticated;
grant execute on function public.manual_attendance(uuid, date, text, timestamptz, text, text) to authenticated;
grant execute on function public.save_attendance_day(uuid, date, boolean, text, numeric, boolean) to authenticated;
grant execute on function public.add_payroll_adjustment(text, uuid, numeric, date, text, boolean) to authenticated;
grant execute on function public.kiosk_roster(text) to anon, authenticated;
grant execute on function public.kiosk_punch(text, uuid, text, text) to anon, authenticated;

-- Phase 4 investors. supabase/migrations/20261123_phase4_investors.sql
-- Phase 4 investor accounts and semi-monthly commission.
-- Idempotent. Does not drop customer rows or customer columns.
-- MAL and AL are not accounts and are never mapped in.
-- Old codes: A=ALVIN, J=JOLLI, AJ=AINA, NELSONANN=NELSON, Hadj=HADJ.
--
-- Apply after phase 1. Modem pullout fees are included when
-- public.modem_pullouts exists (phase 2). Auto ticket expenses are
-- included when expenses.auto exists.

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
alter table public.staff add column if not exists investor_party text;
alter table public.staff enable row level security;
revoke all on table public.staff from public, anon;
grant select, insert, update, delete on public.staff to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'staff' and policyname = 'staff_admin_all'
  ) then
    create policy staff_admin_all on public.staff
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

alter table public.expenses add column if not exists account_code text;
alter table public.expenses add column if not exists expense_side text;

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public' and rel.relname = 'expenses' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%expense_side%'
  loop
    execute format('alter table public.expenses drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.expenses add constraint expenses_side_check
  check (expense_side is null or expense_side in ('operational', 'personal'));

create or replace function public.commission_line(
  p_gross numeric,
  p_operational numeric,
  p_percent numeric,
  p_personal numeric
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  left_amount numeric := round(coalesce(p_gross, 0) - coalesce(p_operational, 0), 2);
begin
  return jsonb_build_object(
    'amount_left', left_amount,
    'share', round((left_amount * coalesce(p_percent, 0) / 100) - coalesce(p_personal, 0), 2)
  );
end;
$$;

create table if not exists public.investor_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  label text not null,
  company boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists investor_accounts_code_uidx on public.investor_accounts (upper(code));

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'investor_accounts_code_blocked'
  ) then
    alter table public.investor_accounts add constraint investor_accounts_code_blocked
      check (upper(code) not in ('MAL', 'AL'));
  end if;
end $$;

create table if not exists public.investor_parties (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff (id) on delete cascade,
  party text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists investor_parties_uidx
  on public.investor_parties (staff_id, upper(party));

create table if not exists public.investor_splits (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.investor_accounts (id) on delete cascade,
  party text not null,
  percent numeric(6, 2) not null check (percent > 0 and percent <= 100)
);

create unique index if not exists investor_splits_party_uidx
  on public.investor_splits (account_id, upper(party));

create or replace function public.investor_splits_check()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  acc uuid := coalesce(new.account_id, old.account_id);
  total numeric;
begin
  if coalesce(current_setting('fiberbro.skip_split_check', true), '') = '1' then
    return null;
  end if;
  select coalesce(sum(percent), 0) into total
  from public.investor_splits
  where account_id = acc;
  if total <> 100 then
    raise exception 'Splits must total 100. This account totals %.', total;
  end if;
  return null;
end;
$$;

drop trigger if exists investor_splits_sum on public.investor_splits;
create constraint trigger investor_splits_sum
  after insert or update or delete on public.investor_splits
  deferrable initially deferred
  for each row
  execute function public.investor_splits_check();

create table if not exists public.extra_income (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.investor_accounts (id) on delete cascade,
  amount numeric(12, 2) not null check (amount >= 0),
  income_date date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.pahabol (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.investor_accounts (id) on delete cascade,
  customer_id uuid references public.customers (id) on delete set null,
  amount numeric(12, 2) not null check (amount >= 0),
  received_on date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.investor_personal_expenses (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.investor_accounts (id) on delete cascade,
  party text not null,
  amount numeric(12, 2) not null check (amount >= 0),
  spent_on date not null default current_date,
  note text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists public.commission_runs (
  id uuid primary key default gen_random_uuid(),
  cutoff_start date not null,
  cutoff_end date not null,
  status text not null default 'draft' check (status in ('draft', 'locked')),
  snapshot jsonb not null default '[]'::jsonb,
  created_by text,
  created_at timestamptz not null default now(),
  locked_by text,
  locked_at timestamptz,
  unique (cutoff_start, cutoff_end)
);

create or replace function public.commission_actor()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(auth.jwt() ->> 'email', ''), 'system');
$$;

create or replace function public.is_investor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff s
    join public.investor_parties ip on ip.staff_id = s.id
    where lower(s.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
      and s.role = 'investor'
      and s.active
  );
$$;

create or replace function public.pullout_fees(p_start date, p_end date, p_code text)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  total numeric := 0;
begin
  if to_regclass('public.modem_pullouts') is null then
    return 0;
  end if;
  execute $q$
    select coalesce(sum(m.return_fee), 0)
    from public.modem_pullouts m
    where m.pulled_on between $1 and $2
      and public.customer_account_code(m.customer_id) = $3
  $q$ into total using p_start, p_end, p_code;
  return coalesce(total, 0);
end;
$$;

create or replace function public.account_operational(p_start date, p_end date, p_code text)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  total numeric := 0;
  has_auto boolean;
begin
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'expenses' and column_name = 'auto'
  ) into has_auto;
  if has_auto then
    execute $q$
      select coalesce(sum(amount), 0)
      from public.expenses
      where expense_date between $1 and $2
        and upper(coalesce(account_code, '')) = upper($3)
        and status = 'approved'
        and (
          expense_side = 'operational'
          or category = 'Operational'
          or coalesce(auto, false)
        )
    $q$ into total using p_start, p_end, p_code;
  else
    select coalesce(sum(amount), 0) into total
    from public.expenses
    where expense_date between p_start and p_end
      and upper(coalesce(account_code, '')) = upper(p_code)
      and status = 'approved'
      and (expense_side = 'operational' or category = 'Operational');
  end if;
  return coalesce(total, 0);
end;
$$;

create or replace function public.build_commission(p_start date, p_end date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  run_id uuid;
  acc record;
  split record;
  collections numeric;
  catchup numeric;
  extra numeric;
  pullout numeric;
  gross numeric;
  operational numeric;
  personal numeric;
  line jsonb;
  parties jsonb;
  snapshot jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can build the commission report.';
  end if;
  if p_end < p_start then
    raise exception 'Cut-off end is before the start.';
  end if;
  if exists (
    select 1 from public.commission_runs
    where cutoff_start = p_start and cutoff_end = p_end and status = 'locked'
  ) then
    raise exception 'This cut-off is locked.';
  end if;

  for acc in
    select * from public.investor_accounts
    where active and upper(code) not in ('MAL', 'AL')
    order by code
  loop
    select coalesce(sum(p.amount), 0) into collections
    from public.payments p
    where p.status = 'confirmed'
      and (coalesce(p.confirmed_at, p.submitted_at) at time zone 'Asia/Manila')::date between p_start and p_end
      and public.customer_account_code(p.customer_id) = acc.code;
    select coalesce(sum(amount), 0) into catchup
    from public.pahabol
    where account_id = acc.id and received_on between p_start and p_end;
    select coalesce(sum(amount), 0) into extra
    from public.extra_income
    where account_id = acc.id and income_date between p_start and p_end;
    pullout := public.pullout_fees(p_start, p_end, acc.code);
    operational := public.account_operational(p_start, p_end, acc.code);
    gross := round(collections + catchup + extra + pullout, 2);
    parties := '[]'::jsonb;
    for split in
      select * from public.investor_splits where account_id = acc.id order by party
    loop
      select coalesce(sum(pe.amount), 0) into personal
      from public.investor_personal_expenses pe
      where pe.account_id = acc.id and upper(pe.party) = upper(split.party)
        and pe.spent_on between p_start and p_end;
      line := public.commission_line(gross, operational, split.percent, personal);
      parties := parties || jsonb_build_array(jsonb_build_object(
        'party', split.party,
        'percent', split.percent,
        'personal', personal,
        'share', line -> 'share'
      ));
    end loop;
    snapshot := snapshot || jsonb_build_array(jsonb_build_object(
      'account_id', acc.id,
      'code', acc.code,
      'label', acc.label,
      'company', acc.company,
      'collections', collections,
      'pahabol', catchup,
      'extra_income', extra,
      'pullout_fees', pullout,
      'gross', gross,
      'operational', operational,
      'amount_left', public.commission_line(gross, operational, 0, 0) -> 'amount_left',
      'parties', parties
    ));
  end loop;

  insert into public.commission_runs (cutoff_start, cutoff_end, status, snapshot, created_by)
  values (p_start, p_end, 'draft', snapshot, public.commission_actor())
  on conflict (cutoff_start, cutoff_end) do update
    set snapshot = excluded.snapshot, created_by = excluded.created_by
  returning id into run_id;

  return json_build_object('ok', true, 'run_id', run_id);
end;
$$;

create or replace function public.lock_commission(p_run uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can lock a commission report.';
  end if;
  update public.commission_runs
  set status = 'locked', locked_by = public.commission_actor(), locked_at = now()
  where id = p_run and status = 'draft';
  return json_build_object('ok', true);
end;
$$;

create or replace function public.save_investor_account(
  p_id uuid,
  p_code text,
  p_label text,
  p_company boolean,
  p_splits jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  acc uuid;
  total numeric;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can edit account splits.';
  end if;
  if p_code is null or upper(btrim(p_code)) in ('', 'MAL', 'AL') then
    raise exception 'MAL and AL are not part of the system.';
  end if;
  select coalesce(sum((split_row.item ->> 'percent')::numeric), 0) into total
  from jsonb_array_elements(coalesce(p_splits, '[]'::jsonb)) as split_row(item);
  if total <> 100 then
    raise exception 'Splits must total 100.';
  end if;
  if p_id is null then
    insert into public.investor_accounts (code, label, company)
    values (upper(btrim(p_code)), coalesce(nullif(btrim(p_label), ''), upper(btrim(p_code))), coalesce(p_company, false))
    returning id into acc;
  else
    update public.investor_accounts
    set code = upper(btrim(p_code)),
        label = coalesce(nullif(btrim(p_label), ''), upper(btrim(p_code))),
        company = coalesce(p_company, false)
    where id = p_id
    returning id into acc;
  end if;
  perform set_config('fiberbro.skip_split_check', '1', true);
  delete from public.investor_splits where account_id = acc;
  insert into public.investor_splits (account_id, party, percent)
  select acc, btrim(split_row.item ->> 'party'), (split_row.item ->> 'percent')::numeric
  from jsonb_array_elements(p_splits) as split_row(item);
  perform set_config('fiberbro.skip_split_check', '0', true);
  return json_build_object('ok', true, 'id', acc);
end;
$$;

create or replace function public.add_commission_item(
  p_kind text,
  p_account uuid,
  p_amount numeric,
  p_date date,
  p_note text,
  p_party text,
  p_customer uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can encode this.';
  end if;
  if p_kind = 'extra' then
    insert into public.extra_income (account_id, amount, income_date, note, created_by)
    values (p_account, p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.commission_actor());
  elsif p_kind = 'pahabol' then
    insert into public.pahabol (account_id, customer_id, amount, received_on, note, created_by)
    values (p_account, p_customer, p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.commission_actor());
  elsif p_kind = 'personal' then
    if nullif(btrim(p_party), '') is null then
      raise exception 'Personal expense needs a party.';
    end if;
    insert into public.investor_personal_expenses (account_id, party, amount, spent_on, note, created_by)
    values (p_account, btrim(p_party), p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), public.commission_actor());
  elsif p_kind = 'operational' then
    insert into public.expenses (category, amount, expense_date, remarks, status, created_by, account_code, expense_side)
    select 'Others', p_amount, coalesce(p_date, current_date), nullif(btrim(p_note), ''), 'approved', public.commission_actor(), a.code, 'operational'
    from public.investor_accounts a
    where a.id = p_account;
  else
    raise exception 'Unknown item.';
  end if;
  return json_build_object('ok', true);
end;
$$;

create or replace function public.investor_report_lines(p_snapshot jsonb, p_parties text[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', item.obj ->> 'code',
    'gross', item.obj -> 'gross',
    'operational', item.obj -> 'operational',
    'amount_left', item.obj -> 'amount_left',
    'shares', (
      select coalesce(jsonb_agg(share.obj), '[]'::jsonb)
      from jsonb_array_elements(item.obj -> 'parties') as share(obj)
      where upper(share.obj ->> 'party') = any (select upper(x) from unnest(p_parties) as x)
    )
  )), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_snapshot, '[]'::jsonb)) as item(obj)
  where exists (
    select 1
    from jsonb_array_elements(item.obj -> 'parties') as share(obj)
    where upper(share.obj ->> 'party') = any (select upper(x) from unnest(p_parties) as x)
  );
$$;

create or replace function public.investor_portal()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff uuid;
  v_parties text[];
  v_accounts jsonb := '[]'::jsonb;
  v_acc record;
  v_draft jsonb;
  v_locked jsonb;
begin
  select s.id into v_staff
  from public.staff s
  where lower(s.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and s.role = 'investor'
    and s.active
  limit 1;
  if v_staff is null then
    raise exception 'This login is not linked to an investor party.';
  end if;
  select coalesce(array_agg(ip.party), '{}') into v_parties
  from public.investor_parties ip
  where ip.staff_id = v_staff;
  if coalesce(array_length(v_parties, 1), 0) = 0 then
    raise exception 'This login is not linked to an investor party.';
  end if;

  for v_acc in
    select distinct a.code, a.label
    from public.investor_accounts a
    join public.investor_splits s on s.account_id = a.id
    where a.active
      and upper(a.code) not in ('MAL', 'AL')
      and upper(s.party) = any (select upper(x) from unnest(v_parties) as x)
    order by a.code
  loop
    v_accounts := v_accounts || jsonb_build_array(jsonb_build_object(
      'code', v_acc.code,
      'label', v_acc.label,
      'customers', coalesce((
        select count(*) from public.customers c
        where public.customer_account_code(c.id) = v_acc.code
      ), 0),
      'by_status', coalesce((
        select jsonb_object_agg(grouped.status_name, grouped.status_count)
        from (
          select coalesce(nullif(c.account_status, ''), c.stage, 'unknown') as status_name, count(*) as status_count
          from public.customers c
          where public.customer_account_code(c.id) = v_acc.code
          group by 1
        ) grouped
      ), '{}'::jsonb)
    ));
  end loop;

  select jsonb_build_object(
    'label', 'Draft',
    'cutoff_start', r.cutoff_start,
    'cutoff_end', r.cutoff_end,
    'lines', public.investor_report_lines(r.snapshot, v_parties)
  ) into v_draft
  from public.commission_runs r
  where r.status = 'draft'
  order by r.cutoff_end desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'cutoff_start', r.cutoff_start,
    'cutoff_end', r.cutoff_end,
    'lines', public.investor_report_lines(r.snapshot, v_parties)
  ) order by r.cutoff_end desc), '[]'::jsonb) into v_locked
  from public.commission_runs r
  where r.status = 'locked';

  return json_build_object(
    'parties', to_jsonb(v_parties),
    'accounts', v_accounts,
    'draft', v_draft,
    'locked', coalesce(v_locked, '[]'::jsonb)
  );
end;
$$;

create or replace function public.set_investor_parties(p_email text, p_parties text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff uuid;
  v_line text;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can link investor parties.';
  end if;
  select s.id into v_staff
  from public.staff s
  where lower(s.email) = lower(btrim(p_email))
    and s.role = 'investor'
    and s.active;
  if v_staff is null then
    raise exception 'Add this Gmail as an active investor on the staff list first.';
  end if;
  delete from public.investor_parties ip where ip.staff_id = v_staff;
  foreach v_line in array regexp_split_to_array(coalesce(p_parties, ''), E'\\r?\\n|,')
  loop
    if nullif(btrim(v_line), '') is null then
      continue;
    end if;
    insert into public.investor_parties (staff_id, party)
    values (v_staff, btrim(v_line));
  end loop;
  return json_build_object('ok', true);
end;
$$;

alter table public.investor_parties enable row level security;
alter table public.investor_accounts enable row level security;
alter table public.investor_splits enable row level security;
alter table public.extra_income enable row level security;
alter table public.pahabol enable row level security;
alter table public.investor_personal_expenses enable row level security;
alter table public.commission_runs enable row level security;

-- Seed. Skipped when an account already has splits, so a later edit is kept.
do $$
declare
  rec record;
  acc uuid;
begin
  perform set_config('fiberbro.skip_split_check', '1', true);
  for rec in
    select * from (values
      ('AINA', 'AINA', false, '[{"party":"ALVIN","percent":45},{"party":"GW","percent":12},{"party":"AINA","percent":43}]'::jsonb),
      ('NELSON', 'NELSON', false, '[{"party":"ALVIN","percent":55},{"party":"ANN-AINA","percent":30},{"party":"GW","percent":15}]'::jsonb),
      ('HADJ', 'HADJ', false, '[{"party":"ALVIN","percent":55},{"party":"HADJIE","percent":30},{"party":"GW","percent":15}]'::jsonb),
      ('LOKAL', 'NELSONHADJ', false, '[{"party":"ALVIN","percent":70},{"party":"HADJIE","percent":15},{"party":"GW","percent":15}]'::jsonb),
      ('ANN', 'ANN', false, '[{"party":"JOLLI","percent":70},{"party":"ANN","percent":30}]'::jsonb),
      ('REY', 'REY', false, '[{"party":"ALVIN","percent":70},{"party":"REY","percent":30}]'::jsonb),
      ('CHES', 'CHES', false, '[{"party":"ALVIN","percent":70},{"party":"CHES","percent":30}]'::jsonb),
      ('JACQ', 'JACQ', false, '[{"party":"ALVIN","percent":65},{"party":"JACQ","percent":35}]'::jsonb),
      ('NOVA', 'NOVA', false, '[{"party":"ALVIN","percent":55},{"party":"NOVA","percent":30},{"party":"GW","percent":15}]'::jsonb),
      ('NOVAANN', 'NOVAANN', false, '[{"party":"ALVIN","percent":40},{"party":"NOVA","percent":30},{"party":"ANN","percent":30}]'::jsonb),
      ('NOVAREY', 'NOVAREY', false, '[{"party":"ALVIN","percent":40},{"party":"NOVA","percent":30},{"party":"REY","percent":30}]'::jsonb),
      ('OSCAR', 'OSCAR', false, '[{"party":"ALVIN","percent":55},{"party":"OSCAR","percent":30},{"party":"GW","percent":15}]'::jsonb),
      ('FB', 'FB', true, '[{"party":"FB","percent":100}]'::jsonb),
      ('JOLLI', 'JOLLI', true, '[{"party":"JOLLI","percent":100}]'::jsonb),
      ('ALVIN', 'ALVIN', true, '[{"party":"ALVIN","percent":100}]'::jsonb)
    ) as t(code, label, company, splits)
  loop
    insert into public.investor_accounts (code, label, company)
    values (rec.code, rec.label, rec.company)
    on conflict ((upper(code))) do nothing;
    select id into acc from public.investor_accounts where upper(code) = upper(rec.code);
    if not exists (select 1 from public.investor_splits where account_id = acc) then
      insert into public.investor_splits (account_id, party, percent)
      select acc, split_row.item ->> 'party', (split_row.item ->> 'percent')::numeric
      from jsonb_array_elements(rec.splits) as split_row(item);
    end if;
  end loop;
  perform set_config('fiberbro.skip_split_check', '0', true);
end $$;

set constraints all immediate;

revoke all on table public.investor_parties from public, anon;
revoke all on table public.investor_accounts from public, anon;
revoke all on table public.investor_splits from public, anon;
revoke all on table public.extra_income from public, anon;
revoke all on table public.pahabol from public, anon;
revoke all on table public.investor_personal_expenses from public, anon;
revoke all on table public.commission_runs from public, anon;

grant select, insert, update, delete on public.investor_parties to authenticated;
grant select, insert, update, delete on public.investor_accounts to authenticated;
grant select, insert, update, delete on public.investor_splits to authenticated;
grant select, insert, update, delete on public.extra_income to authenticated;
grant select, insert, update, delete on public.pahabol to authenticated;
grant select, insert, update, delete on public.investor_personal_expenses to authenticated;
grant select, insert, update, delete on public.commission_runs to authenticated;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'investor_parties', 'investor_accounts', 'investor_splits', 'extra_income', 'pahabol',
    'investor_personal_expenses', 'commission_runs'
  ]
  loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = tbl and policyname = tbl || '_admin_all'
    ) then
      execute format(
        'create policy %I on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())',
        tbl || '_admin_all', tbl
      );
    end if;
  end loop;
end $$;

revoke execute on function
  public.commission_line(numeric, numeric, numeric, numeric),
  public.investor_report_lines(jsonb, text[]),
  public.investor_splits_check(),
  public.commission_actor(),
  public.pullout_fees(date, date, text),
  public.account_operational(date, date, text)
  from public, anon, authenticated;

revoke execute on function
  public.is_investor(),
  public.build_commission(date, date),
  public.lock_commission(uuid),
  public.save_investor_account(uuid, text, text, boolean, jsonb),
  public.add_commission_item(text, uuid, numeric, date, text, text, uuid),
  public.investor_portal(),
  public.set_investor_parties(text, text)
  from public, anon;

grant execute on function public.is_investor() to authenticated;
grant execute on function public.build_commission(date, date) to authenticated;
grant execute on function public.lock_commission(uuid) to authenticated;
grant execute on function public.save_investor_account(uuid, text, text, boolean, jsonb) to authenticated;
grant execute on function public.add_commission_item(text, uuid, numeric, date, text, text, uuid) to authenticated;
grant execute on function public.investor_portal() to authenticated;
grant execute on function public.set_investor_parties(text, text) to authenticated;

-- Harden older RPCs. supabase/migrations/20261123b_harden_old_rpcs.sql
-- Harden two older RPCs. Idempotent. Does not drop customer data.
-- The customer portal still signs in with portal_login. It does not call
-- these two functions.
--
-- admin_set_portal_pin stays callable by a signed-in admin only.
-- refresh_wallet_credit is the payments trigger. Anon and authenticated
-- cannot execute it. Supabase grants execute on public functions directly
-- to anon and authenticated, so revoke from public is not enough.

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
  v_pin text := nullif(btrim(coalesce(pin, '')), '');
  v_target uuid := customer_id;
  v_updated uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can set a portal PIN.';
  end if;

  if v_pin is not null and v_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits.';
  end if;

  if v_pin is null and p_enabled is null then
    raise exception 'Enter a PIN or choose whether the portal is enabled.';
  end if;

  if v_pin is not null then
    update public.customers c
    set portal_pin_hash = extensions.crypt(v_pin, extensions.gen_salt('bf')),
        failed_login_count = 0,
        locked_until = null,
        portal_enabled = coalesce(p_enabled, true)
    where c.id = v_target
    returning c.id into v_updated;
  else
    update public.customers c
    set portal_enabled = p_enabled
    where c.id = v_target
    returning c.id into v_updated;
  end if;

  if v_updated is null then
    raise exception 'Customer was not found.';
  end if;

  if v_pin is not null then
    delete from public.portal_sessions s where s.customer_id = v_target;
  end if;

  return json_build_object('ok', true);
end;
$$;

revoke all on function public.admin_set_portal_pin(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_portal_pin(uuid, text, boolean) to authenticated;

revoke all on function public.refresh_wallet_credit() from public, anon, authenticated;
