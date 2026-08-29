-- 0010: Recipients (people / companies that receive money).
--
-- A recipient belongs to a budget_book (like accounts/categories). It may
-- optionally carry a linked account and/or category and free-text notes.
-- Transactions get an optional recipient_id.

-- 1) recipients table ------------------------------------------------------
create table if not exists public.recipients (
  id             uuid primary key default gen_random_uuid(),
  budget_book_id uuid not null references public.budget_books (id) on delete cascade,
  name           text not null,
  account_id     uuid references public.accounts (id) on delete set null,
  category_id    uuid references public.categories (id) on delete set null,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists recipients_budget_book_id_idx
  on public.recipients (budget_book_id);

create index if not exists recipients_account_id_idx
  on public.recipients (account_id);

create index if not exists recipients_category_id_idx
  on public.recipients (category_id);

create unique index if not exists recipients_book_name_unique
  on public.recipients (budget_book_id, lower(name));

create trigger recipients_set_updated_at
  before update on public.recipients
  for each row execute function public.set_updated_at();

-- Enforce that recipient's account + category belong to the same budget_book.
create or replace function public.recipients_validate_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_book uuid;
  v_category_book uuid;
begin
  if new.account_id is not null then
    select budget_book_id into v_account_book from public.accounts where id = new.account_id;
    if v_account_book is distinct from new.budget_book_id then
      raise exception 'account does not belong to the recipient budget_book';
    end if;
  end if;

  if new.category_id is not null then
    select budget_book_id into v_category_book from public.categories where id = new.category_id;
    if v_category_book is distinct from new.budget_book_id then
      raise exception 'category does not belong to the recipient budget_book';
    end if;
  end if;

  return new;
end;
$$;

create trigger recipients_validate_book
  before insert or update on public.recipients
  for each row execute function public.recipients_validate_book();

-- 2) transactions.recipient_id (optional) -----------------------------------
alter table public.transactions
  add column recipient_id uuid references public.recipients (id) on delete set null;

create index if not exists transactions_recipient_id_idx
  on public.transactions (recipient_id);

-- Enforce recipient belongs to the same budget_book as the transaction.
-- Extend the existing validation trigger.
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
  v_category_is_leaf boolean;
  v_recipient_book uuid;
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
    select budget_book_id, (parent_id is not null)
      into v_category_book, v_category_is_leaf
      from public.categories where id = new.category_id;

    if v_category_book is distinct from new.budget_book_id then
      raise exception 'category does not belong to the transaction budget_book';
    end if;
    if not v_category_is_leaf then
      raise exception 'transactions must reference a subcategory (leaf), not a parent category';
    end if;
  end if;

  if new.recipient_id is not null then
    select budget_book_id into v_recipient_book from public.recipients where id = new.recipient_id;
    if v_recipient_book is distinct from new.budget_book_id then
      raise exception 'recipient does not belong to the transaction budget_book';
    end if;
  end if;

  return new;
end;
$$;

-- 3) RLS --------------------------------------------------------------------
alter table public.recipients enable row level security;

create policy "recipients_select_own" on public.recipients for select
  using (exists (select 1 from public.budget_books bb
                 where bb.id = recipients.budget_book_id and bb.user_id = auth.uid()));

create policy "recipients_insert_own" on public.recipients for insert
  with check (exists (select 1 from public.budget_books bb
                      where bb.id = recipients.budget_book_id and bb.user_id = auth.uid()));

create policy "recipients_update_own" on public.recipients for update
  using (exists (select 1 from public.budget_books bb
                 where bb.id = recipients.budget_book_id and bb.user_id = auth.uid()))
  with check (exists (select 1 from public.budget_books bb
                      where bb.id = recipients.budget_book_id and bb.user_id = auth.uid()));

create policy "recipients_delete_own" on public.recipients for delete
  using (exists (select 1 from public.budget_books bb
                 where bb.id = recipients.budget_book_id and bb.user_id = auth.uid()));

-- 4) Grants ------------------------------------------------------------------
grant select, insert, update, delete on table public.recipients
  to authenticated, service_role;
