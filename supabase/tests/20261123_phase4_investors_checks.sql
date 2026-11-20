-- Manual checks for phase 4. Not part of the migration.
-- Apply supabase/migrations/20261123_phase4_investors.sql first, then run this
-- whole file. It rolls back.
--
-- Expected:
-- AJ maps to AINA, A to ALVIN, J to JOLLI, NELSONANN to NELSON, Hadj to HADJ.
-- MAL and AL map to null.
-- Gross 1450 minus operational 200 leaves 1250.
-- ALVIN at 45% minus 62.50 personal is a 500 share.

begin;

select public.map_account_code('AJ') as aj,
       public.map_account_code('A') as a_code,
       public.map_account_code('J') as j_code,
       public.map_account_code('NELSONANN') as nelsonann,
       public.map_account_code('Hadj') as hadj,
       public.map_account_code('MAL') as mal,
       public.map_account_code('AL') as al;

select public.commission_line(1450, 200, 45, 62.50) as alvin_on_aina;

select code
from public.investor_accounts
where upper(code) in ('MAL', 'AL');

select a.code, sum(s.percent) as total
from public.investor_accounts a
join public.investor_splits s on s.account_id = a.id
group by a.code
order by a.code;

rollback;
