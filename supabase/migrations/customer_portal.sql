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
