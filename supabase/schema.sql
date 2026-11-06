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
  installed_by text,
  installation_status text,
  installation_date date,
  installation_remarks text,
  plan_speed text,
  plan_split text, -- unused
  price numeric(12, 2),
  plan_status text,
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
    if col in ('created_at', 'updated_at') then
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
