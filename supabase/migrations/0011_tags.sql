-- 0011: Tags (optional labels for transactions).
--
-- Tags are short labels with a name and optional color that can be
-- attached to transactions. Each tag belongs to a budget_book.
--
-- A transaction may have zero or one tag (tag_id is nullable).
-- If a tag is deleted, the transaction's tag_id is set to null.

-- 1) tags table ------------------------------------------------------------
create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  budget_book_id uuid not null references public.budget_books (id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tags_budget_book_id_idx
  on public.tags (budget_book_id);

create unique index if not exists tags_book_name_unique
  on public.tags (budget_book_id, lower(name));

create trigger tags_set_updated_at
  before update on public.tags
  for each row execute function public.set_updated_at();

-- 3) RLS on tags ---------------------------------------------------------
alter table public.tags enable row level security;

create policy "tags_select_own" on public.tags for select
  using (exists (select 1 from public.budget_books bb
                 where bb.id = tags.budget_book_id and bb.user_id = auth.uid()));

create policy "tags_insert_own" on public.tags for insert
  with check (exists (select 1 from public.budget_books bb
                      where bb.id = tags.budget_book_id and bb.user_id = auth.uid()));

create policy "tags_update_own" on public.tags for update
  using (exists (select 1 from public.budget_books bb
                 where bb.id = tags.budget_book_id and bb.user_id = auth.uid()))
  with check (exists (select 1 from public.budget_books bb
                     where bb.id = tags.budget_book_id and bb.user_id = auth.uid()));

create policy "tags_delete_own" on public.tags for delete
  using (exists (select 1 from public.budget_books bb
                 where bb.id = tags.budget_book_id and bb.user_id = auth.uid()));

-- 4) grants --------------------------------------------------------------
grant select, insert, update, delete on table public.tags
  to authenticated, service_role;

-- 5) tag_id on transactions ------------------------------------------------
alter table public.transactions add column if not exists tag_id uuid
  references public.tags (id) on delete set null;

create index if not exists transactions_tag_id_idx
  on public.transactions (tag_id);