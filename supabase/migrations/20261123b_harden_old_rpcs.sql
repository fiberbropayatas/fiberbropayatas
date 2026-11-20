-- Harden two older RPCs. Idempotent. Does not drop customer data.
-- The customer portal still signs in with portal_login. It does not call
-- these two functions.
--
-- admin_set_portal_pin stays callable by a signed-in admin only.
-- refresh_wallet_credit is the payments trigger. Anon and authenticated
-- cannot execute it. Supabase grants execute on public functions directly
-- to anon and authenticated, so revoke from public is not enough.

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
  v_pin text := nullif(btrim(coalesce(pin, '')), '');
  v_target uuid := customer_id;
  v_updated uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can set a portal PIN.';
  end if;

  if v_pin is not null and v_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits.';
  end if;

  if v_pin is null and p_enabled is null then
    raise exception 'Enter a PIN or choose whether the portal is enabled.';
  end if;

  if v_pin is not null then
    update public.customers c
    set portal_pin_hash = extensions.crypt(v_pin, extensions.gen_salt('bf')),
        failed_login_count = 0,
        locked_until = null,
        portal_enabled = coalesce(p_enabled, true)
    where c.id = v_target
    returning c.id into v_updated;
  else
    update public.customers c
    set portal_enabled = p_enabled
    where c.id = v_target
    returning c.id into v_updated;
  end if;

  if v_updated is null then
    raise exception 'Customer was not found.';
  end if;

  if v_pin is not null then
    delete from public.portal_sessions s where s.customer_id = v_target;
  end if;

  return json_build_object('ok', true);
end;
$$;

revoke all on function public.admin_set_portal_pin(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_portal_pin(uuid, text, boolean) to authenticated;

revoke all on function public.refresh_wallet_credit() from public, anon, authenticated;
