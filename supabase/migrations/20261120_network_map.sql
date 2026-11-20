-- Network map: LP points, NAP boxes, customer links, and area polygons.
-- Idempotent. Does not delete rows or overwrite customers.lp / customers.nap / customers.port.

create table if not exists public.distribution_points (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  area text,
  sub_area text,
  port_capacity integer,
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);

create unique index if not exists distribution_points_code_uidx
  on public.distribution_points (upper(code));

create table if not exists public.nap_boxes (
  id uuid primary key default gen_random_uuid(),
  lp_id uuid references public.distribution_points (id) on delete set null,
  code text not null,
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  area text,
  sub_area text,
  port_capacity integer,
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);

create unique index if not exists nap_boxes_code_uidx
  on public.nap_boxes (upper(code));

create index if not exists nap_boxes_lp_idx on public.nap_boxes (lp_id);

create table if not exists public.area_polygons (
  id uuid primary key default gen_random_uuid(),
  area_name text not null,
  path jsonb not null,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.customers add column if not exists lp_id uuid references public.distribution_points (id) on delete set null;
alter table public.customers add column if not exists nap_id uuid references public.nap_boxes (id) on delete set null;

create index if not exists customers_nap_id_idx on public.customers (nap_id);
create index if not exists customers_lp_id_idx on public.customers (lp_id);

alter table public.distribution_points enable row level security;
alter table public.nap_boxes enable row level security;
alter table public.area_polygons enable row level security;

revoke all on table public.distribution_points from public, anon;
revoke all on table public.nap_boxes from public, anon;
revoke all on table public.area_polygons from public, anon;
grant select, insert, update, delete on public.distribution_points to authenticated;
grant select, insert, update, delete on public.nap_boxes to authenticated;
grant select, insert, update, delete on public.area_polygons to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'distribution_points' and policyname = 'distribution_points_admin_all'
  ) then
    create policy distribution_points_admin_all on public.distribution_points
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'nap_boxes' and policyname = 'nap_boxes_admin_all'
  ) then
    create policy nap_boxes_admin_all on public.nap_boxes
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'area_polygons' and policyname = 'area_polygons_admin_all'
  ) then
    create policy area_polygons_admin_all on public.area_polygons
      for all to authenticated
      using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'network-photos',
  'network-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_read'
  ) then
    create policy network_photos_admin_read on storage.objects
      for select to authenticated
      using (bucket_id = 'network-photos' and public.is_admin());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_insert'
  ) then
    create policy network_photos_admin_insert on storage.objects
      for insert to authenticated
      with check (bucket_id = 'network-photos' and public.is_admin() and name ~ '^assets/.+');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'network_photos_admin_delete'
  ) then
    create policy network_photos_admin_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'network-photos' and public.is_admin());
  end if;
end $$;

-- Used NAP ports are not stored. Count customers.nap_id in the admin map.
-- customers.lp and customers.nap text fields stay as entered.
