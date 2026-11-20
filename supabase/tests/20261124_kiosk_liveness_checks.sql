-- Manual checks for kiosk liveness. Not applied by the site.
-- Run after supabase/migrations/20261124_kiosk_liveness.sql. The file rolls back.

begin;

insert into public.kiosk_devices (name, token_hash)
values ('Phase5 phone', encode(extensions.digest('phase5-token', 'sha256'), 'hex'));

insert into public.employees (name, rate_type, monthly_rate)
values ('Liveness Check', 'regular', 1000);

select public.kiosk_punch(
  'phase5-token',
  (select id from public.employees where name = 'Liveness Check' order by created_at desc limit 1),
  'next',
  repeat('a', 120),
  array[repeat('b', 120), repeat('c', 120), repeat('d', 120)],
  '{"passed":true,"challenge":"left","duration_ms":1800,"blink":true,"head":"left"}'::jsonb
);

select ap.punch_type, ap.liveness ->> 'challenge' as challenge, ap.liveness ->> 'passed' as passed,
       (select count(*) from public.attendance_photos ph where ph.punch_id = ap.id) as photos
from public.attendance_punches ap
join public.employees e on e.id = ap.employee_id
where e.name = 'Liveness Check';

rollback;
