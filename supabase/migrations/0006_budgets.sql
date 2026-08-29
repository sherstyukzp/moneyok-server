-- 0006: Budgets.
--
-- A budget sets a spending limit on a category for a given period
-- (monthly / yearly / custom). Belongs to a budget_book.

create table if not exists public.budgets (
  id            uuid primary key default gen_random_uuid(),
  budget_book_id uuid not null references public.budget_books (id) on delete cascade,
  category_id   uuid not null references public.categories (id),
  name          text not null,
  amount_limit  numeric(18, 2) not null check (amount_limit > 0),
  period_type   text not null check (period_type in ('monthly', 'yearly', 'custom')),
  start_date    date not null,
  end_date      date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint budgets_dates_valid check (end_date is null or end_date >= start_date)
);

create index if not exists budgets_budget_book_id_idx
  on public.budgets (budget_book_id);

create index if not exists budgets_category_id_idx
  on public.budgets (category_id);

create trigger budgets_set_updated_at
  before update on public.budgets
  for each row execute function public.set_updated_at();

-- Enforce that the budget category belongs to the same budget_book.
create or replace function public.budgets_validate_category_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category_book uuid;
begin
  select budget_book_id into v_category_book from public.categories where id = new.category_id;
  if v_category_book is distinct from new.budget_book_id then
    raise exception 'category does not belong to the budget budget_book';
  end if;
  return new;
end;
$$;

create trigger budgets_validate_category_book
  before insert or update on public.budgets
  for each row execute function public.budgets_validate_category_book();
