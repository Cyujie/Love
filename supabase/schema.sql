-- Run once in the Supabase SQL Editor of the project you intend to use.
create extension if not exists pgcrypto;

create table if not exists public.couples (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null unique references auth.users(id) on delete cascade,
  partner_id uuid unique references auth.users(id) on delete set null,
  invite_code text not null unique check (invite_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  started_on date not null default (now() at time zone 'Asia/Shanghai')::date,
  created_at timestamptz not null default now(),
  constraint couple_members_distinct check (partner_id is null or partner_id <> created_by)
);

create table if not exists public.couple_memories (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  content text not null default '',
  photo_path text,
  constraint couple_memories_content_check check (char_length(content) <= 1000 and (char_length(content) >= 1 or photo_path is not null)),
  created_at timestamptz not null default now()
);

alter table public.couple_memories add column if not exists photo_path text;

create table if not exists public.couple_events (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('important_date','checkin','wish','wish_step','wish_done','tree_water','pet_feed','pet_play','farm_water','farm_harvest','reminder')),
  title text not null check (char_length(title) between 1 and 120),
  content text not null default '' check (char_length(content) <= 1000),
  event_date date,
  related_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists couple_memories_couple_created_idx on public.couple_memories (couple_id, created_at desc);
create index if not exists couple_memories_author_idx on public.couple_memories (author_id);
create index if not exists couple_events_couple_created_idx on public.couple_events (couple_id, created_at desc);
create index if not exists couple_events_author_idx on public.couple_events (author_id);

alter table public.couples enable row level security;
alter table public.couple_memories enable row level security;
alter table public.couple_events enable row level security;

drop policy if exists "couple members can read their space" on public.couples;
create policy "couple members can read their space" on public.couples
  for select to authenticated
  using ((select auth.uid()) = created_by or (select auth.uid()) = partner_id);

drop policy if exists "users can create their own space" on public.couples;

drop policy if exists "members can read shared memories" on public.couple_memories;
create policy "members can read shared memories" on public.couple_memories
  for select to authenticated
  using (exists (select 1 from public.couples c where c.id = couple_id and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)));

drop policy if exists "members can add shared memories" on public.couple_memories;
create policy "members can add shared memories" on public.couple_memories
  for insert to authenticated
  with check (
    author_id = (select auth.uid()) and
    exists (select 1 from public.couples c where c.id = couple_id and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id))
  );

drop policy if exists "members can read shared events" on public.couple_events;
create policy "members can read shared events" on public.couple_events
  for select to authenticated
  using (exists (select 1 from public.couples c where c.id = couple_id and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)));

drop policy if exists "members can add shared events" on public.couple_events;
create policy "members can add shared events" on public.couple_events
  for insert to authenticated
  with check (
    author_id = (select auth.uid()) and
    exists (select 1 from public.couples c where c.id = couple_id and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id))
  );

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.join_couple_impl(invite_code_input text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  joined_id uuid;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in before joining a couple space';
  end if;
  if exists (select 1 from public.couples c where c.created_by = current_user_id or c.partner_id = current_user_id) then
    raise exception 'This account already belongs to a couple space';
  end if;
  update public.couples
    set partner_id = current_user_id
    where invite_code = upper(invite_code_input)
      and partner_id is null
      and created_by <> current_user_id
    returning id into joined_id;
  if joined_id is null then
    raise exception 'Invite code is invalid, already used, or belongs to your own account';
  end if;
  return joined_id;
end;
$$;

revoke all on function private.join_couple_impl(text) from public, anon;
grant execute on function private.join_couple_impl(text) to authenticated;

create or replace function public.join_couple(invite_code_input text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select private.join_couple_impl(invite_code_input); $$;

revoke all on function public.join_couple(text) from public, anon;
grant execute on function public.join_couple(text) to authenticated;

grant select, insert on public.couples to authenticated;
revoke insert on public.couples from authenticated;
grant select, insert on public.couple_memories to authenticated;
grant select, insert on public.couple_events to authenticated;

create or replace function private.create_couple_impl(invite_code_input text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Sign in before creating a couple space';
  end if;
  if exists (select 1 from public.couples c where c.created_by = current_user_id or c.partner_id = current_user_id) then
    raise exception 'This account already belongs to a couple space';
  end if;
  insert into public.couples (created_by, invite_code)
    values (current_user_id, upper(invite_code_input))
    returning id into new_id;
  return new_id;
end;
$$;

revoke all on function private.create_couple_impl(text) from public, anon;
grant execute on function private.create_couple_impl(text) to authenticated;

create or replace function public.create_couple(invite_code_input text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select private.create_couple_impl(invite_code_input); $$;

revoke all on function public.create_couple(text) from public, anon;
grant execute on function public.create_couple(text) to authenticated;

create or replace function private.set_couple_start_date_impl(couple_id_input uuid, start_date_input date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in before changing the relationship date';
  end if;
  if start_date_input > (now() at time zone 'Asia/Shanghai')::date then
    raise exception 'The relationship start date cannot be in the future';
  end if;
  update public.couples
    set started_on = start_date_input
    where id = couple_id_input
      and ((select auth.uid()) = created_by or (select auth.uid()) = partner_id);
  if not found then
    raise exception 'Couple space not found or access denied';
  end if;
end;
$$;

revoke all on function private.set_couple_start_date_impl(uuid, date) from public, anon;
grant execute on function private.set_couple_start_date_impl(uuid, date) to authenticated;

create or replace function public.set_couple_start_date(couple_id_input uuid, start_date_input date)
returns void
language sql
security invoker
set search_path = ''
as $$ select private.set_couple_start_date_impl(couple_id_input, start_date_input); $$;

revoke all on function public.set_couple_start_date(uuid, date) from public, anon;
grant execute on function public.set_couple_start_date(uuid, date) to authenticated;

-- Private photo storage. Object paths must start with the owning couple UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('couple-moments', 'couple-moments', false, 8388608, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = false, file_size_limit = 8388608, allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "couple members can read moment photos" on storage.objects;
create policy "couple members can read moment photos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'couple-moments' and exists (
      select 1 from public.couples c
      where c.id::text = (storage.foldername(name))[1]
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "couple members can upload moment photos" on storage.objects;
create policy "couple members can upload moment photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'couple-moments' and exists (
      select 1 from public.couples c
      where c.id::text = (storage.foldername(name))[1]
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );
