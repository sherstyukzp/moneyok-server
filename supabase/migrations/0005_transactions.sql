-- 0005: Transactions.
--
-- Every transaction belongs to a budget_book and an account.
-- A transfer additionally references a second account (transfer_account_id)
-- and leaves category_id NULL.
--
-- Account balances are maintained automatically by a trigger so the
-- frontend never has to compute them.

create table if not exists public.transactions (
  id                  uuid primary key default gen_random_uuid(),
  budget_book_id      uuid not null references public.budget_books (id) on delete cascade,
  account_id          uuid not null references public.accounts (id),
  category_id         uuid references public.categories (id) on delete set null,
  type                text not null check (type in ('income', 'expense', 'transfer')),
  amount              numeric(18, 2) not null check (amount > 0),
  currency            text not null default 'USD',
  note                text,
  transaction_date    date not null default current_date,
  transfer_account_id uuid references public.accounts (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint transactions_no_category_on_transfer
    check (type <> 'transfer' or category_id is null),
  constraint transactions_transfer_requires_target
    check (type <> 'transfer' or transfer_account_id is not null),
  constraint transactions_transfer_not_same_account
    check (type <> 'transfer' or transfer_account_id is distinct from account_id)
);

create index if not exists transactions_budget_book_id_idx
  on public.transactions (budget_book_id);

create index if not exists transactions_account_id_idx
  on public.transactions (account_id);

create index if not exists transactions_category_id_idx
  on public.transactions (category_id);

create index if not exists transactions_date_idx
  on public.transactions (transaction_date);

create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function public.set_updated_at();

-- Enforce that account, transfer_account and category all belong to the
-- same budget_book as the transaction itself.
create or replace function public.transactions_validate_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_book uuid;
  v_transfer_book uuid;
  v_category_book uuid;
begin
  select budget_book_id into v_account_book from public.accounts where id = new.account_id;
  if v_account_book is distinct from new.budget_book_id then
    raise exception 'account does not belong to the transaction budget_book';
  end if;

  if new.transfer_account_id is not null then
    select budget_book_id into v_transfer_book from public.accounts where id = new.transfer_account_id;
    if v_transfer_book is distinct from new.budget_book_id then
      raise exception 'transfer account does not belong to the transaction budget_book';
    end if;
  end if;

  if new.category_id is not null then
    select budget_book_id into v_category_book from public.categories where id = new.category_id;
    if v_category_book is distinct from new.budget_book_id then
      raise exception 'category does not belong to the transaction budget_book';
    end if;
  end if;

  return new;
end;
$$;

create trigger transactions_validate_book
  before insert or update on public.transactions
  for each row execute function public.transactions_validate_book();

-- Balances -------------------------------------------------------------
-- income  -> +amount on account_id
-- expense -> -amount on account_id
-- transfer-> -amount on account_id, +amount on transfer_account_id
create or replace function public.apply_transaction_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Reverse the effect of the old row (on UPDATE/DELETE).
  if tg_op in ('UPDATE', 'DELETE') then
    if old.type = 'income' then
      update public.accounts set current_balance = current_balance - old.amount where id = old.account_id;
    elsif old.type = 'expense' then
      update public.accounts set current_balance = current_balance + old.amount where id = old.account_id;
    elsif old.type = 'transfer' then
      update public.accounts set current_balance = current_balance + old.amount where id = old.account_id;
      if old.transfer_account_id is not null then
        update public.accounts set current_balance = current_balance - old.amount where id = old.transfer_account_id;
      end if;
    end if;
  end if;

  -- Apply the effect of the new/current row.
  if tg_op in ('INSERT', 'UPDATE') then
    if new.type = 'income' then
      update public.accounts set current_balance = current_balance + new.amount where id = new.account_id;
    elsif new.type = 'expense' then
      update public.accounts set current_balance = current_balance - new.amount where id = new.account_id;
    elsif new.type = 'transfer' then
      update public.accounts set current_balance = current_balance - new.amount where id = new.account_id;
      if new.transfer_account_id is not null then
        update public.accounts set current_balance = current_balance + new.amount where id = new.transfer_account_id;
      end if;
    end if;
  end if;

  return null;
end;
$$;

create trigger transactions_apply_balance
  after insert or update or delete on public.transactions
  for each row execute function public.apply_transaction_balance();
