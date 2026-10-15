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
