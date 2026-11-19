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
