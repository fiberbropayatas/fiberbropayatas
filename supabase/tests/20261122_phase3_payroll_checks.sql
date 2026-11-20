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

insert into public.admins (email)
values ('fiberbropayatas@gmail.com')
on conflict (email) do nothing;

select set_config('request.jwt.claims', '{"email":"fiberbropayatas@gmail.com"}', true);
select set_config('request.jwt.claim.email', 'fiberbropayatas@gmail.com', true);

insert into public.employees (name, rate_type, monthly_rate, shift_start, shift_end, rest_day)
values ('Payroll Check', 'regular', 26000, time '09:00', time '18:00', 0);

insert into public.attendance_punches (employee_id, work_date, punch_type, punched_at, source, reason, entered_by)
select id, date '2026-11-01', 'clock_in', timestamptz '2026-11-01 09:20+08', 'manual', 'Rest day test', 'test'
from public.employees where name = 'Payroll Check';

insert into public.attendance_punches (employee_id, work_date, punch_type, punched_at, source, reason, entered_by)
select id, date '2026-11-02', 'clock_in', timestamptz '2026-11-02 09:20+08', 'manual', 'Late test', 'test'
from public.employees where name = 'Payroll Check';

select public.build_payroll(date '2026-11-01', date '2026-11-15');

select ps.days_present, ps.late_penalty, ps.net_pay, ps.detail
from public.payslips ps
join public.employees e on e.id = ps.employee_id
where e.name = 'Payroll Check';

rollback;
