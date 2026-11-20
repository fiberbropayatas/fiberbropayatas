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
-- last day of the month). The admin dashboard calls it once per day.
-- pg_cron is scheduled only when that extension is already installed
-- (often unavailable on the free tier). Period stays YYYY-MM. period_label
-- is Mon_YYYY (Nov_2026). bill_number is FBROPAY-BILL plus 10 digits.
-- previous_balance is a snapshot of older open bills, not added into amount.
--
-- New account numbers (blank only) use app_settings.account_number_format,
-- default FBRO{CODE2}{SEQ7}, e.g. FBROAL0000001. Existing numbers are kept.

insert into public.app_settings (key, value, is_public) values
  ('account_number_format', 'FBRO{CODE2}{SEQ7}', false)
on conflict (key) do nothing;

alter table public.customers add column if not exists due_day integer;

update public.customers
set due_day = extract(day from installation_date)::integer
where due_day is null
  and installation_date is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'customers_due_day_check'
      and conrelid = 'public.customers'::regclass
  ) then
    alter table public.customers
      add constraint customers_due_day_check
      check (due_day is null or (due_day between 1 and 31));
  end if;
end $$;

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

  new.email_address := coalesce(new.email_address, new.email);
  new.fb_account := coalesce(new.fb_account, new.facebook_name);

  if new.account_number is null or btrim(new.account_number) = '' then
    new.account_number := public.next_fiberbro_account(new.investor_id);
  end if;

  if new.due_day is null and new.installation_date is not null then
    new.due_day := extract(day from new.installation_date)::integer;
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
  if new.due_day is null and new.installation_date is not null then
    new.due_day := extract(day from new.installation_date)::integer;
  end if;
  return new;
end;
$$;

drop trigger if exists customers_fill_due_day on public.customers;
create trigger customers_fill_due_day
  before insert or update of installation_date, due_day on public.customers
  for each row execute function public.customers_fill_due_day();

create or replace function public.sync_invoice_from_payment()
returns trigger
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
  if new.invoice_id is null then
    return new;
  end if;
  select amount, status into bill_amount, bill_status
  from public.invoices where id = new.invoice_id;
  if bill_status = 'void' or bill_amount is null then
    return new;
  end if;
  select coalesce(sum(amount), 0) into paid_sum
  from public.payments
  where invoice_id = new.invoice_id and status = 'confirmed';
  select exists (
    select 1 from public.payments
    where invoice_id = new.invoice_id and status = 'pending'
  ) into waiting;
  if paid_sum + 0.009 >= bill_amount then
    update public.invoices
      set status = 'paid', paid_at = coalesce(paid_at, now())
      where id = new.invoice_id;
  elsif paid_sum > 0 or waiting then
    update public.invoices
      set status = 'pending', paid_at = null
      where id = new.invoice_id;
  else
    update public.invoices
      set status = 'unpaid', paid_at = null
      where id = new.invoice_id;
  end if;
  return new;
end;
$$;

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

create or replace function public.generate_upcoming_bills()
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
    select c.id, c.due_day, c.installation_date, c.monthly_bill, c.price
    from public.customers c
    where c.stage = 'active'
  loop
    for step in 0..1 loop
      due_on := public.clamp_due_date(
        extract(year from (current_date + make_interval(months => step)))::integer,
        extract(month from (current_date + make_interval(months => step)))::integer,
        coalesce(cust.due_day, extract(day from cust.installation_date)::integer, 1)
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
    txn := substring(raw_line from '(\\d{4}-\\d{2}-\\d{2})')::date;
    if txn is null then
      begin
        txn := to_date(substring(raw_line from '([A-Za-z]{3}\\s+\\d{1,2},\\s+\\d{4})'), 'Mon DD, YYYY');
      exception when others then
        txn := null;
      end;
    end if;
    cleaned := regexp_replace(raw_line, '\\d{4}-\\d{2}-\\d{2}', ' ', 'g');
    cleaned := regexp_replace(cleaned, '[A-Za-z]{3}\\s+\\d{1,2},\\s+\\d{4}', ' ', 'g');
    amt := substring(replace(cleaned, ',', '') from '(\\d+\\.\\d{2})\\s*$')::numeric;
    if amt is not null then
      cleaned := regexp_replace(cleaned, '\\d+\\.\\d{2}\\s*$', ' ');
    else
      amt := substring(replace(cleaned, ',', '') from '(\\d+)\\s*$')::numeric;
      if amt is not null then
        cleaned := regexp_replace(cleaned, '\\d+\\s*$', ' ');
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
      'due_day', cust.due_day
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
      'select public.generate_upcoming_bills()'
    );
  end if;
exception when others then
  null;
end $$;
