-- 0004: Accounts and categories.
--
-- Both belong to a budget_book. Accounts track money movement,
-- categories classify transactions by income/expense kind.

create table if not exists public.accounts (
  id              uuid primary key default gen_random_uuid(),
  budget_book_id  uuid not null references public.budget_books (id) on delete cascade,
  name            text not null,
  type            text not null check (type in ('cash', 'bank', 'credit', 'investment', 'other')),
  currency        text not null default 'USD',
  initial_balance numeric(18, 2) not null default 0,
  current_balance numeric(18, 2) not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists accounts_budget_book_id_idx
  on public.accounts (budget_book_id);

create trigger accounts_set_updated_at
  before update on public.accounts
  for each row execute function public.set_updated_at();

create table if not exists public.categories (
  id             uuid primary key default gen_random_uuid(),
  budget_book_id uuid not null references public.budget_books (id) on delete cascade,
  name           text not null,
  kind           text not null check (kind in ('income', 'expense')),
  icon           text,
  color          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists categories_budget_book_id_idx
  on public.categories (budget_book_id);

create unique index if not exists categories_book_name_kind_unique
  on public.categories (budget_book_id, name, kind);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();
