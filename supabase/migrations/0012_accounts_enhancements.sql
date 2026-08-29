-- 0012: Enhance accounts.
--
-- UX-driven changes to public.accounts:
--
--   1. type -> richer set that matches the creation form:
--        payment       (Платіжний рахунок)
--        savings       (Ощадний рахунок)
--        credit_card   (Кредитна карта)
--        investment    (Інвестиція)
--        reserve       (Застереження)
--        liability     (Зобов'язання)
--        business      (Бізнес-рахунок)
--        cash          (Готівка)
--
--      Existing rows are remapped: 'bank' -> 'payment', 'credit' -> 'credit_card',
--      'other' -> 'cash'. The legacy CHECK constraint is replaced with one that
--      matches the new enum.
--
--   2. New presentation / metadata columns:
--        color  text  -- hex like '#f59e0b', same convention as categories.
--        icon   text  -- short identifier (e.g. 'wallet', 'piggy-bank').
--        note   text  -- free-form description.
--
--   3. Archive support:
--        archived_at timestamptz  -- NULL = active, non-NULL = archived at that time.
--      Archived accounts remain readable / writable by the owner; the frontend
--      is expected to filter `archived_at IS NULL` for the active list and to
--      surface archived ones in a dedicated view (and let the user restore).
--
--   4. Reconciliation:
--      `current_balance` stays auto-maintained by the transaction trigger.
--      Users can directly UPDATE it to override / reconcile (RLS allows UPDATE
--      through budget_book ownership; the trigger only fires on transaction
--      changes, not on account changes), which makes it the natural place
--      to land a real-world balance correction.

-- 1) Migrate existing type values before swapping the CHECK constraint. ----
update public.accounts
   set type = case type
     when 'bank'   then 'payment'
     when 'credit' then 'credit_card'
     when 'other'  then 'cash'
     else type
   end
 where type in ('bank', 'credit', 'other');

alter table public.accounts
  drop constraint if exists accounts_type_check;

alter table public.accounts
  add constraint accounts_type_check
    check (type in ('payment', 'savings', 'credit_card', 'investment',
                    'reserve', 'liability', 'business', 'cash'));

-- 2) Presentation / metadata columns. --------------------------------------
alter table public.accounts
  add column if not exists color text,
  add column if not exists icon  text,
  add column if not exists note  text;

-- 3) Archive timestamp + indexes. ------------------------------------------
alter table public.accounts
  add column if not exists archived_at timestamptz;

-- Cheap "list active accounts in a book" path.
create index if not exists accounts_active_idx
  on public.accounts (budget_book_id)
  where archived_at is null;

-- Cheap "list archived accounts in a book" path (sorted by archive time desc).
create index if not exists accounts_archived_idx
  on public.accounts (budget_book_id, archived_at desc)
  where archived_at is not null;