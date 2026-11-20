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
