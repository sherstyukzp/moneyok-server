-- 0007: Row Level Security (RLS).
--
-- Access control strategy:
--   * profiles    -> user can only see/update their own row
--   * budget_books-> user can only see/manage their own books
--   * accounts / categories / transactions / budgets
--                 -> user can only see/manage rows whose budget_book
--                    belongs to them (auth.uid() == budget_books.user_id)
--
-- No role is allowed to write another user's data because every write
-- policy re-checks ownership of the parent budget_book.

alter table public.profiles enable row level security;
alter table public.budget_books enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;

-- profiles ---------------------------------------------------------------
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- budget_books -----------------------------------------------------------
create policy "budget_books_select_own"
  on public.budget_books for select
  using (auth.uid() = user_id);

create policy "budget_books_insert_own"
  on public.budget_books for insert
  with check (auth.uid() = user_id);

create policy "budget_books_update_own"
  on public.budget_books for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "budget_books_delete_own"
  on public.budget_books for delete
  using (auth.uid() = user_id);

-- accounts -----------------------------------------------------------
create policy "accounts_select_own"
  on public.accounts for select
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = accounts.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "accounts_insert_own"
  on public.accounts for insert
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = accounts.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "accounts_update_own"
  on public.accounts for update
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = accounts.budget_book_id
        and bb.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = accounts.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "accounts_delete_own"
  on public.accounts for delete
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = accounts.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

-- categories ---------------------------------------------------------
create policy "categories_select_own"
  on public.categories for select
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = categories.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "categories_insert_own"
  on public.categories for insert
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = categories.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "categories_update_own"
  on public.categories for update
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = categories.budget_book_id
        and bb.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = categories.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "categories_delete_own"
  on public.categories for delete
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = categories.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

-- transactions ------------------------------------------------------
create policy "transactions_select_own"
  on public.transactions for select
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = transactions.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "transactions_insert_own"
  on public.transactions for insert
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = transactions.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "transactions_update_own"
  on public.transactions for update
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = transactions.budget_book_id
        and bb.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = transactions.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "transactions_delete_own"
  on public.transactions for delete
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = transactions.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

-- budgets ------------------------------------------------------------
create policy "budgets_select_own"
  on public.budgets for select
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = budgets.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "budgets_insert_own"
  on public.budgets for insert
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = budgets.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "budgets_update_own"
  on public.budgets for update
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = budgets.budget_book_id
        and bb.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.budget_books bb
      where bb.id = budgets.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

create policy "budgets_delete_own"
  on public.budgets for delete
  using (
    exists (
      select 1 from public.budget_books bb
      where bb.id = budgets.budget_book_id
        and bb.user_id = auth.uid()
    )
  );

-- Grants --------------------------------------------------------------
-- Grant full access to authenticated role on all app tables through PostgREST.
grant select, insert, update, delete on table
  public.profiles,
  public.budget_books,
  public.accounts,
  public.categories,
  public.transactions,
  public.budgets
  to authenticated;

-- service_role bypasses RLS and is used for seeds / background jobs.
grant select, insert, update, delete on table
  public.profiles,
  public.budget_books,
  public.accounts,
  public.categories,
  public.transactions,
  public.budgets
  to service_role;
