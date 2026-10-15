create table if not exists public.couple_room_plans (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  plan jsonb not null default '{}'::jsonb check (jsonb_typeof(plan) = 'object' and pg_column_size(plan) <= 16384),
  updated_by uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);

create table if not exists public.couple_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision not null check (accuracy_m between 0 and 100000),
  updated_at timestamptz not null default now()
);

create index if not exists couple_locations_couple_updated_idx
  on public.couple_locations (couple_id, updated_at desc);

alter table public.couple_room_plans enable row level security;
alter table public.couple_locations enable row level security;

drop policy if exists "couple members can read room plans" on public.couple_room_plans;
create policy "couple members can read room plans" on public.couple_room_plans
  for select to authenticated
  using (exists (
    select 1 from public.couples c
    where c.id = couple_room_plans.couple_id
      and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
  ));

drop policy if exists "couple members can create room plans" on public.couple_room_plans;
create policy "couple members can create room plans" on public.couple_room_plans
  for insert to authenticated
  with check (
    updated_by = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_room_plans.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "couple members can update room plans" on public.couple_room_plans;
create policy "couple members can update room plans" on public.couple_room_plans
  for update to authenticated
  using (exists (
    select 1 from public.couples c
    where c.id = couple_room_plans.couple_id
      and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
  ))
  with check (
    updated_by = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_room_plans.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "couple members can read fresh locations" on public.couple_locations;
create policy "couple members can read fresh locations" on public.couple_locations
  for select to authenticated
  using (exists (
    select 1 from public.couples c
    where c.id = couple_locations.couple_id
      and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
      and (couple_locations.user_id = (select auth.uid()) or couple_locations.updated_at > now() - interval '2 minutes')
  ));

drop policy if exists "users can share their own location" on public.couple_locations;
create policy "users can share their own location" on public.couple_locations
  for insert to authenticated
  with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_locations.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "users can update their own location" on public.couple_locations;
create policy "users can update their own location" on public.couple_locations
  for update to authenticated
  using (
    user_id = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_locations.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  )
  with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_locations.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "users can stop sharing their own location" on public.couple_locations;
create policy "users can stop sharing their own location" on public.couple_locations
  for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update on public.couple_room_plans to authenticated;
grant select, insert, update, delete on public.couple_locations to authenticated;
