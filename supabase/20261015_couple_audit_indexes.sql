create index if not exists couple_chat_messages_author_idx on public.couple_chat_messages (author_id);
create index if not exists couple_ledger_entries_author_idx on public.couple_ledger_entries (author_id);
create index if not exists couple_room_plans_updated_by_idx on public.couple_room_plans (updated_by);
