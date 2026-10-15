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
