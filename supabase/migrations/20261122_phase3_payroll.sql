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
begin
  if not public.is_payroll() then
    raise exception 'Only payroll or an admin can update the day.';
  end if;
  if coalesce(p_approve, false) and not public.is_admin() then
    raise exception 'Only an admin can approve overtime.';
  end if;
  if coalesce(p_approve, false) then
    v_ot_status := 'approved';
  elsif coalesce(p_ot_hours, 0) = 0 then
    v_ot_status := 'pending';
  end if;
  insert into public.attendance_days (employee_id, work_date, half_day, half_reason, ot_hours, ot_status)
  values (p_employee, p_date, coalesce(p_half, false), nullif(btrim(p_half_reason), ''), coalesce(p_ot_hours, 0), v_ot_status)
  on conflict (employee_id, work_date) do update
    set half_day = excluded.half_day,
        half_reason = excluded.half_reason,
        ot_hours = excluded.ot_hours,
        ot_status = case when p_approve then 'approved' else attendance_days.ot_status end;
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
