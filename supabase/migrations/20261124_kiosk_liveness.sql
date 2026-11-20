-- Kiosk liveness photos. Idempotent. Does not drop customer data.
-- The old 4-argument kiosk_punch call still works: the extra arguments
-- have defaults. A failed liveness payload is rejected. The wallet and
-- portal login functions are not changed.

alter table public.attendance_punches
  add column if not exists liveness jsonb;

drop function if exists public.kiosk_punch(text, uuid, text, text);

create or replace function public.kiosk_punch(
  p_token text,
  p_employee uuid,
  p_type text,
  p_selfie text,
  p_burst text[] default null,
  p_liveness jsonb default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device uuid := public.kiosk_device_id(p_token);
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_kind text := p_type;
  v_punch uuid;
  v_shot text;
  v_saved integer := 1;
  v_max_len integer := 500000;
begin
  if v_device is null then
    raise exception 'This phone is not the registered kiosk.';
  end if;
  if nullif(btrim(p_selfie), '') is null or length(p_selfie) < 100 then
    raise exception 'A selfie is required.';
  end if;
  if length(p_selfie) > v_max_len then
    raise exception 'A photo is too large.';
  end if;
  if p_liveness is not null and coalesce(p_liveness ->> 'passed', '') is distinct from 'true' then
    raise exception 'Liveness check did not pass.';
  end if;
  if p_burst is not null and cardinality(p_burst) > 5 then
    raise exception 'Too many photos.';
  end if;
  if not exists (select 1 from public.employees e where e.id = p_employee and e.active) then
    raise exception 'Employee not found.';
  end if;
  if v_kind is null or v_kind = '' or v_kind = 'next' then
    select slots.slot into v_kind
    from (values (1, 'clock_in'), (2, 'lunch_out'), (3, 'lunch_in'), (4, 'clock_out')) as slots(n, slot)
    where not exists (
      select 1 from public.attendance_punches ap
      where ap.employee_id = p_employee and ap.work_date = v_today and ap.punch_type = slots.slot
    )
    order by slots.n
    limit 1;
  end if;
  if v_kind not in ('clock_in', 'lunch_out', 'lunch_in', 'clock_out') then
    raise exception 'Unknown punch.';
  end if;
  if exists (
    select 1 from public.attendance_punches ap
    where ap.employee_id = p_employee and ap.work_date = v_today and ap.punch_type = v_kind
  ) then
    raise exception 'That punch is already recorded for today.';
  end if;
  insert into public.attendance_punches (
    employee_id, work_date, punch_type, punched_at, source, device_id, entered_by, liveness
  ) values (
    p_employee, v_today, v_kind, now(), 'face', v_device, 'kiosk', p_liveness
  )
  returning id into v_punch;
  insert into public.attendance_photos (punch_id, content_type, image_base64)
  values (v_punch, 'image/jpeg', p_selfie);
  if p_burst is not null then
    foreach v_shot in array p_burst loop
      if v_saved >= 5 then
        exit;
      end if;
      if v_shot is null or length(v_shot) < 100 or v_shot = p_selfie then
        continue;
      end if;
      if length(v_shot) > v_max_len then
        raise exception 'A photo is too large.';
      end if;
      insert into public.attendance_photos (punch_id, content_type, image_base64)
      values (v_punch, 'image/jpeg', v_shot);
      v_saved := v_saved + 1;
    end loop;
  end if;
  return json_build_object('ok', true, 'punch_id', v_punch, 'punch_type', v_kind, 'work_date', v_today, 'photos', v_saved);
end;
$$;

revoke all on function public.kiosk_punch(text, uuid, text, text, text[], jsonb) from public, anon, authenticated;
grant execute on function public.kiosk_punch(text, uuid, text, text, text[], jsonb) to anon, authenticated;
