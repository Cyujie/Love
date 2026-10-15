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

-- Room planning and privacy-limited current location sharing.
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


-- Account avatars, visible only to the account owner and their couple partner.
create table if not exists public.couple_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  avatar_path text check (avatar_path is null or char_length(avatar_path) <= 512),
  updated_at timestamptz not null default now()
);

alter table public.couple_profiles enable row level security;

drop policy if exists "users and their partners can read profiles" on public.couple_profiles;
create policy "users and their partners can read profiles" on public.couple_profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.couples c
      where (c.created_by = couple_profiles.user_id or c.partner_id = couple_profiles.user_id)
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

drop policy if exists "users can create their own profile" on public.couple_profiles;
create policy "users can create their own profile" on public.couple_profiles
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "users can update their own profile" on public.couple_profiles;
create policy "users can update their own profile" on public.couple_profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update on public.couple_profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('couple-avatars', 'couple-avatars', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "couple members can read avatars" on storage.objects;
create policy "couple members can read avatars" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'couple-avatars' and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.couples c
        where (storage.foldername(name))[1] in (c.created_by::text, c.partner_id::text)
          and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
      )
    )
  );

drop policy if exists "users can upload their own avatar" on storage.objects;
create policy "users can upload their own avatar" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'couple-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "users can delete their own avatar" on storage.objects;
create policy "users can delete their own avatar" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'couple-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Append-only shared income and expense ledger.
create table if not exists public.couple_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  entry_type text not null check (entry_type in ('income','expense')),
  amount numeric(12,2) not null check (amount > 0),
  category text not null default '其他' check (char_length(category) between 1 and 40),
  note text not null default '' check (char_length(note) <= 300),
  occurred_on date not null default (now() at time zone 'Asia/Shanghai')::date,
  created_at timestamptz not null default now()
);

create index if not exists couple_ledger_entries_couple_date_idx
  on public.couple_ledger_entries (couple_id, occurred_on desc, created_at desc);

alter table public.couple_ledger_entries enable row level security;

drop policy if exists "couple members can read ledger entries" on public.couple_ledger_entries;
create policy "couple members can read ledger entries" on public.couple_ledger_entries
  for select to authenticated
  using (exists (
    select 1 from public.couples c
    where c.id = couple_ledger_entries.couple_id
      and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
  ));

drop policy if exists "couple members can add their own ledger entries" on public.couple_ledger_entries;
create policy "couple members can add their own ledger entries" on public.couple_ledger_entries
  for insert to authenticated
  with check (
    author_id = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_ledger_entries.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

grant select, insert on public.couple_ledger_entries to authenticated;

-- Realtime private chat for paired accounts.
create table if not exists public.couple_chat_messages (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists couple_chat_messages_couple_created_idx
  on public.couple_chat_messages (couple_id, created_at desc);

alter table public.couple_chat_messages enable row level security;

drop policy if exists "couple members can read chat messages" on public.couple_chat_messages;
create policy "couple members can read chat messages" on public.couple_chat_messages
  for select to authenticated
  using (exists (
    select 1 from public.couples c
    where c.id = couple_chat_messages.couple_id
      and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
  ));

drop policy if exists "couple members can send their own chat messages" on public.couple_chat_messages;
create policy "couple members can send their own chat messages" on public.couple_chat_messages
  for insert to authenticated
  with check (
    author_id = (select auth.uid()) and exists (
      select 1 from public.couples c
      where c.id = couple_chat_messages.couple_id
        and ((select auth.uid()) = c.created_by or (select auth.uid()) = c.partner_id)
    )
  );

grant select, insert on public.couple_chat_messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'couple_chat_messages'
  ) then
    alter publication supabase_realtime add table public.couple_chat_messages;
  end if;
end $$;

-- Add covering indexes to the user foreign keys in shared activity tables.
create index if not exists couple_chat_messages_author_idx on public.couple_chat_messages (author_id);
create index if not exists couple_ledger_entries_author_idx on public.couple_ledger_entries (author_id);
create index if not exists couple_room_plans_updated_by_idx on public.couple_room_plans (updated_by);
