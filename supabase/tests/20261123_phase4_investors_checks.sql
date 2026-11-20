-- Manual checks for phase 4. Not part of the migration.
-- Apply the phase 2 and phase 4 migrations first, then run this whole file.
-- It rolls back.
--
-- Expected:
-- Investor code A and PPPoE prefix A map to ALVIN. AJ maps to AINA.
-- NELSONHADJ maps to LOKAL. MAL and AL map to null.
-- ALVIN at 45% of amount left 1250, minus 62.50 personal, is a 500 share.
-- Investor A does not see an account that only belongs to investor B.

begin;

insert into public.admins (email)
values ('fiberbropayatas@gmail.com')
on conflict (email) do nothing;

select set_config('request.jwt.claims', '{"email":"fiberbropayatas@gmail.com"}', true);
select set_config('request.jwt.claim.email', 'fiberbropayatas@gmail.com', true);

insert into public.investors (name, code) values
  ('Map A', 'A'),
  ('Map AJ', 'AJ'),
  ('Map Lokal', 'NELSONHADJ'),
  ('Map Mal', 'MAL');

insert into public.customers (name, source, investor_id, pppoe)
select 'Map A customer', 'admin', id, null from public.investors where code = 'A' order by created_at desc limit 1;
insert into public.customers (name, source, investor_id)
select 'Map AJ customer', 'admin', id from public.investors where code = 'AJ' order by created_at desc limit 1;
insert into public.customers (name, source, investor_id)
select 'Map Lokal customer', 'admin', id from public.investors where code = 'NELSONHADJ' order by created_at desc limit 1;
insert into public.customers (name, source, investor_id)
select 'Map Mal customer', 'admin', id from public.investors where code = 'MAL' order by created_at desc limit 1;
insert into public.customers (name, source, pppoe)
values ('Map pppoe A', 'admin', 'A-CRUZ-JUAN');

select c.name, public.customer_account_code(c.id) as account_code
from public.customers c
where c.name like 'Map %'
order by c.name;

select public.commission_line(1450, 200, 45, 62.50) as alvin_on_aina;

select code from public.investor_accounts where upper(code) in ('MAL', 'AL', 'LOKAL');

select set_config('fiberbro.skip_split_check', '1', true);
insert into public.investor_accounts (code, label, company)
values ('ONLYB', 'Only B', false);
insert into public.investor_splits (account_id, party, percent)
select id, 'ONLYB', 100 from public.investor_accounts where code = 'ONLYB';
select set_config('fiberbro.skip_split_check', '0', true);

insert into public.staff (email, name, role) values
  ('investor-a@fiberbro.test', 'Investor A', 'investor'),
  ('investor-b@fiberbro.test', 'Investor B', 'investor');

insert into public.investor_parties (staff_id, party)
select id, 'ALVIN' from public.staff where email = 'investor-a@fiberbro.test';
insert into public.investor_parties (staff_id, party)
select id, 'ONLYB' from public.staff where email = 'investor-b@fiberbro.test';

select set_config('request.jwt.claims', '{"email":"investor-a@fiberbro.test"}', true);
select public.investor_portal() as portal_a;

select set_config('request.jwt.claims', '{"email":"investor-b@fiberbro.test"}', true);
select public.investor_portal() as portal_b;

rollback;
