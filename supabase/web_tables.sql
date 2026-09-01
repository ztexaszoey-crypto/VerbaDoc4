-- ============================================================
-- VerbaDoc Web Tables — run in Supabase SQL Editor
-- ============================================================

-- Decks
create table if not exists public.decks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  title      text not null,
  emoji      text not null default '📚',
  exam_date  date,
  created_at timestamptz default now()
);

alter table public.decks enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='decks' and policyname='Users see own decks') then
    execute 'create policy "Users see own decks" on public.decks for select using (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='decks' and policyname='Users insert own decks') then
    execute 'create policy "Users insert own decks" on public.decks for insert with check (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='decks' and policyname='Users delete own decks') then
    execute 'create policy "Users delete own decks" on public.decks for delete using (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='decks' and policyname='Users update own decks') then
    execute 'create policy "Users update own decks" on public.decks for update using (auth.uid() = user_id)';
  end if;
end $$;


-- Cards
create table if not exists public.cards (
  id         uuid primary key default gen_random_uuid(),
  deck_id    uuid not null references public.decks(id) on delete cascade,
  question   text not null,
  answer     text not null,
  topic      text,
  created_at timestamptz default now()
);

alter table public.cards enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='cards' and policyname='Users see own cards') then
    execute 'create policy "Users see own cards" on public.cards for select using (exists (select 1 from public.decks d where d.id = deck_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='cards' and policyname='Users insert own cards') then
    execute 'create policy "Users insert own cards" on public.cards for insert with check (exists (select 1 from public.decks d where d.id = deck_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='cards' and policyname='Users delete own cards') then
    execute 'create policy "Users delete own cards" on public.cards for delete using (exists (select 1 from public.decks d where d.id = deck_id and d.user_id = auth.uid()))';
  end if;
end $$;
