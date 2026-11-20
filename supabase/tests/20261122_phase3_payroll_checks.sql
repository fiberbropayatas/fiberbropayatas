-- Manual checks for phase 3. Not part of the migration.
-- Apply supabase/migrations/20261122_phase3_payroll.sql first, then run this
-- whole file. It rolls back.
--
-- Expected:
-- 09:10 is free, 09:15 and 09:20 are ₱30, 11:00 is a half day with no late penalty.
-- Regular 26000, 10 days, 2 half days, 2 approved OT hours, 100 incentive
-- earns 9350. Net after 30 late, 500 cash advance, and 100 violation is 8720.
-- Fixed pay for the same monthly rate is 13000 plus OT and incentive.

begin;

select public.payroll_day_effect(time '09:00', time '09:10', false) as ten_min,
       public.payroll_day_effect(time '09:00', time '09:15', false) as fifteen,
       public.payroll_day_effect(time '09:00', time '09:20', false) as twenty,
       public.payroll_day_effect(time '09:00', time '11:00', false) as two_hours;

select public.payroll_earnings('regular', 26000, 10, 2, 2, 100) as regular_pay,
       public.payroll_earnings('fixed', 26000, 10, 2, 0, 0) as fixed_half;

-- 9350 earnings - 30 late - 500 cash advance - 100 violation.
select round(
  ((public.payroll_earnings('regular', 26000, 10, 2, 2, 100) ->> 'earnings')::numeric) - 30 - 500 - 100,
  2
) as sample_net;

select cutoff_start, cutoff_end from public.payroll_cutoff(date '2026-11-10');
select cutoff_start, cutoff_end from public.payroll_cutoff(date '2026-11-20');

rollback;
