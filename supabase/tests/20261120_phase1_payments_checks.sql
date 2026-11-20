-- Manual checks for phase 1. Not part of the migration.
-- Apply supabase/migrations/20261120_phase1_payments.sql first, then run this
-- whole file. It rolls back, so it does not keep the sample customer.
--
-- Expected:
-- 1. After inserting a confirmed payment, the invoice status is paid and
--    confirmed_at / confirmed_by are filled by the BEFORE stamp trigger.
-- 2. add_gcash_refs parses "2026-11-16 3047334127750 500.00" into one row.
--    That call needs an admin JWT. In the SQL editor, set the claim first:
--    select set_config('request.jwt.claims', '{"email":"fiberbropayatas@gmail.com"}', true);

begin;

insert into public.customers (name, stage, source, monthly_bill, due_date_number)
values ('Phase1 Check', 'active', 'admin', 1000, 18);

insert into public.invoices (customer_id, period, amount, due_date, status)
select id, '2026-11', 1000, date '2026-11-18', 'unpaid'
from public.customers
where name = 'Phase1 Check'
order by created_at desc
limit 1;

insert into public.payments (invoice_id, customer_id, amount, method, reference_no, status, source)
select i.id, i.customer_id, 1000, 'gcash', '3047334127750', 'confirmed', 'admin'
from public.invoices i
join public.customers c on c.id = i.customer_id
where c.name = 'Phase1 Check' and i.period = '2026-11';

-- Invoice should be paid, and the payment row should have confirmation stamps.
select i.status as invoice_status, p.confirmed_at is not null as stamped_at, p.confirmed_by
from public.invoices i
join public.payments p on p.invoice_id = i.id
join public.customers c on c.id = i.customer_id
where c.name = 'Phase1 Check';

select set_config('request.jwt.claims', '{"email":"fiberbropayatas@gmail.com"}', true);

select public.add_gcash_refs(
  (select id from public.gcash_accounts where name = 'Alvin' limit 1),
  E'2026-11-16 3047334127750 500.00\n2026-11-16 3047 334 127751 250'
);

select ref_number, txn_date, amount, duplicate_flag
from public.gcash_refs
where ref_number in ('3047334127750', '3047334127751')
order by ref_number;

rollback;
