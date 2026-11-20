-- Manual checks for phase 2. Not part of the migration.
-- Apply supabase/migrations/20261121_phase2_ops.sql first, then run this
-- whole file. It rolls back, so the sample customer, ticket, and expense
-- are not kept.
--
-- Expected:
-- 1. Due day 31 in February 2026 is 2026-02-28, and in February 2024 is 2024-02-29.
--    April 31 becomes 2026-04-30. clamp_due_date already does this.
-- 2. Closing a repair with two SC connectors posts one Operational expense of 56
--    on the investor account code.
-- 3. Completing an installation sets the customer to Active / Newly Installed,
--    fills PPPoE, and records a cash installation payment.

begin;

insert into public.admins (email)
values ('fiberbropayatas@gmail.com')
on conflict (email) do nothing;

select set_config('request.jwt.claims', '{"email":"fiberbropayatas@gmail.com"}', true);
select set_config('request.jwt.claim.email', 'fiberbropayatas@gmail.com', true);

select public.clamp_due_date(2026, 2, 31) as feb_2026,
       public.clamp_due_date(2024, 2, 31) as feb_2024,
       public.clamp_due_date(2026, 4, 31) as apr_2026;

insert into public.investors (name, code)
values ('Phase2 Investor', 'AL');

insert into public.customers (name, stage, source, investor_id, monthly_bill, due_date_number)
select 'Phase2 Check', 'in_progress', 'admin', id, 1000, 31
from public.investors
where code = 'AL'
order by created_at desc
limit 1;

insert into public.staff (email, name, role)
values ('tech-phase2@fiberbro.test', 'Phase2 Tech', 'tech');

insert into public.ops_tickets (ticket_type, customer_id, issue, assigned_to, status)
select 'REP', c.id, 'No internet', s.id, 'Assigned'
from public.customers c
join public.staff s on s.email = 'tech-phase2@fiberbro.test'
where c.name = 'Phase2 Check'
order by c.created_at desc
limit 1;

insert into public.ticket_materials (ticket_id, item, qty, unit_cost)
select id, 'SC Connector', 2, 28
from public.ops_tickets
where customer_id = (select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1)
order by created_at desc
limit 1;

select public.resolve_ops_ticket(
  (select id from public.ops_tickets where ticket_type = 'REP' and customer_id = (
    select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1
  ) order by created_at desc limit 1),
  'Line replaced'
);

select e.category, e.amount, e.account_code, e.scope, e.auto, t.status
from public.expenses e
join public.ops_tickets t on t.id = e.ticket_id
where t.ticket_type = 'REP'
  and t.customer_id = (select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1);

insert into public.ops_tickets (ticket_type, customer_id, issue, status)
select 'INSTALLATION', id, 'New installation', 'Open'
from public.customers
where name = 'Phase2 Check'
order by created_at desc
limit 1;

select public.complete_installation(
  (select id from public.ops_tickets where ticket_type = 'INSTALLATION' and customer_id = (
    select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1
  ) order by created_at desc limit 1),
  'LP1',
  'NAP2',
  '3',
  null,
  'cash',
  1000,
  null
);

select stage, account_status, pppoe is not null as has_pppoe, lp, nap, port
from public.customers
where name = 'Phase2 Check'
order by created_at desc
limit 1;

select invoice_kind, amount, status
from public.invoices
where customer_id = (select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1)
  and invoice_kind = 'installation';

select method, amount, status, notes
from public.payments
where customer_id = (select id from public.customers where name = 'Phase2 Check' order by created_at desc limit 1)
  and notes = 'Installation fee';

rollback;
