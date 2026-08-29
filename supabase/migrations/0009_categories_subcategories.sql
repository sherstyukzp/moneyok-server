-- 0009: Categories → hierarchical (parents + subcategories).
--
-- Business rules (per user request):
--   * categories form a single-level hierarchy via parent_id (nullable).
--   * Category = parent grouping (e.g. "Food & Drink"). No color/icon on it.
--   * Subcategory = leaf (e.g. "Groceries", "Alcohol"). Has color + icon.
--   * transactions & budgets may only reference subcategories (leaves).
--   * A subcategory must share the same kind and budget_book as its parent.
--
-- Migration path: keeps the existing `categories` table and adds parent_id.

-- 1) Add parent_id self reference ----------------------------------------
alter table public.categories
  add column parent_id uuid references public.categories (id) on delete cascade;

create index if not exists categories_parent_id_idx
  on public.categories (parent_id);

-- 2) Adjust uniqueness: siblings must be unique within the same parent;
--    parents (parent_id IS NULL) unique per (book, name, kind).
drop index if exists categories_book_name_kind_unique;

create unique index categories_siblings_unique
  on public.categories (budget_book_id, parent_id, name);

create unique index categories_parent_name_kind_unique
  on public.categories (budget_book_id, name, kind)
  where parent_id is null;

-- 3) Enforce the hierarchy rules via a BEFORE trigger ---------------------
create or replace function public.categories_validate_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_book uuid;
  v_parent_kind text;
begin
  if new.parent_id is null then
    -- It's a parent grouping: must NOT carry color/icon.
    if new.icon is not null or new.color is not null then
      raise exception 'parent categories cannot have icon or color';
    end if;
  else
    -- It's a leaf subcategory: parent must exist, be in the same book,
    -- be a parent (not itself a child), and match kind.
    select budget_book_id, kind
      into v_parent_book, v_parent_kind
      from public.categories
     where id = new.parent_id;

    if v_parent_book is null then
      raise exception 'category parent does not exist';
    end if;
    if v_parent_book is distinct from new.budget_book_id then
      raise exception 'category parent must belong to the same budget_book';
    end if;
    if (select parent_id from public.categories where id = new.parent_id) is not null then
      raise exception 'category parent must be a top-level category (no nesting)';
    end if;
    if v_parent_kind is distinct from new.kind then
      raise exception 'subcategory kind must match its parent category kind';
    end if;
  end if;

  return new;
end;
$$;

create trigger categories_validate_hierarchy
  before insert or update on public.categories
  for each row execute function public.categories_validate_hierarchy();

-- 4) transactions may only reference leaf subcategories -------------------
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

  return new;
end;
$$;

-- 5) budgets may only reference leaf subcategories -------------------------
create or replace function public.budgets_validate_category_book()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category_book uuid;
  v_category_is_leaf boolean;
begin
  select budget_book_id, (parent_id is not null)
    into v_category_book, v_category_is_leaf
    from public.categories where id = new.category_id;

  if v_category_book is distinct from new.budget_book_id then
    raise exception 'category does not belong to the budget budget_book';
  end if;
  if not v_category_is_leaf then
    raise exception 'budgets must reference a subcategory (leaf), not a parent category';
  end if;

  return new;
end;
$$;

-- Required so rebuilding the triggers above keeps RLS/trigger grants intact.
-- (No direct RLS change: categories RLS already routes through budget_book.)
