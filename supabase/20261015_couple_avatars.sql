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
