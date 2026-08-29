-- 0003: Budget books.
--
-- A budget book is the top-level owner of all financial entities
-- (accounts, categories, transactions, budgets). Every book belongs to a user.
-- The schema supports multiple books per user (Personal / Family / Work).

create table if not exists public.budget_books (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists budget_books_user_id_idx
  on public.budget_books (user_id);

create trigger budget_books_set_updated_at
  before update on public.budget_books
  for each row execute function public.set_updated_at();

-- Keep at most one default book per user.
create unique index budget_books_single_default_idx
  on public.budget_books (user_id)
  where is_default;

-- Auto-create a default "Personal" budget book when a profile is created
-- (i.e. when a new user signs up). Keeps the "one default book on start"
-- business rule without frontend involvement.
create or replace function public.handle_new_default_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.budget_books (user_id, name, is_default)
  values (new.id, 'Personal', true);

  return new;
end;
$$;

create trigger on_profile_created_default_book
  after insert on public.profiles
  for each row execute function public.handle_new_default_book();
