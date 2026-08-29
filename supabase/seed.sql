-- Seed data for local development / demo.
--
-- Creates a demo user (demo@moneyok.local / demo-password), their profile,
-- a default budget book, accounts, categories, transactions and budgets.
--
-- The seed runs with the service_role / postgres role which bypasses RLS,
-- so ownership is set explicitly on budget_books.user_id.
--
-- Note: the auth trigger (handle_new_user + default book) also fires when
-- we insert into auth.users, so we use ON CONFLICT clauses that make the
-- seed idempotent when re-run after `supabase db reset`.

-- 1) Demo auth user -----------------------------------------------------
-- Columns mirror exactly what GoTrue stores for a normal email signup so
-- that password login works out of the box (this includes instance_id and
-- the token columns, which GoTrue requires to be empty strings, not NULL).
insert into auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, aud, role,
  confirmation_token, recovery_token, email_change,
  email_change_token_current, email_change_token_new, phone_change,
  phone_change_token, reauthentication_token, email_change_confirm_status
)
select
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'demo@moneyok.local',
  crypt('demo-password', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Demo User"}',
  now(), now(), 'authenticated', 'authenticated',
  '', '', '', '', '', '', '', '', 0
on conflict (id) do nothing;

-- The auth insert fires handle_new_user which creates the profile and then
-- the default book. Point that book at a fixed deterministic ID so all the
-- child seed rows below can reference it.
update public.budget_books
   set id = '22222222-2222-2222-2222-222222222222',
       name = 'Personal'
 where user_id = '11111111-1111-1111-1111-111111111111'
   and is_default = true;

-- 2) Accounts -----------------------------------------------------------
insert into public.accounts (id, budget_book_id, name, type, currency, initial_balance, current_balance)
values
  ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222', 'Cash',      'cash',   'USD', 200.00, 200.00),
  ('33333333-3333-3333-3333-333333333332', '22222222-2222-2222-2222-222222222222', 'Main Bank', 'bank',   'USD', 5000.00, 5000.00),
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Credit',    'credit', 'USD', 0.00, 0.00)
on conflict (id) do nothing;

-- 3) Categories ----------------------------------------------------------
insert into public.categories (id, budget_book_id, name, kind, icon, color)
values
  ('44444444-4444-4444-4444-444444444441', '22222222-2222-2222-2222-222222222222', 'Salary',       'income',  'briefcase',      '#10b981'),
  ('44444444-4444-4444-4444-444444444442', '22222222-2222-2222-2222-222222222222', 'Freelance',    'income',  'laptop',         '#06b6d4'),
  ('44444444-4444-4444-4444-444444444443', '22222222-2222-2222-2222-222222222222', 'Food',         'expense', 'utensils',       '#f59e0b'),
  ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Rent',         'expense', 'home',           '#ef4444'),
  ('44444444-4444-4444-4444-444444444445', '22222222-2222-2222-2222-222222222222', 'Transport',    'expense', 'bus',            '#8b5cf6'),
  ('44444444-4444-4444-4444-444444444446', '22222222-2222-2222-2222-222222222222', 'Entertainment','expense', 'tv',             '#ec4899')
on conflict (id) do nothing;

-- 4) Transactions (after accounts + categories so FKs resolve) ------------
-- Balances are maintained by the apply_transaction_balance trigger.
insert into public.transactions (
  id, budget_book_id, account_id, category_id, type, amount, currency,
  note, transaction_date, transfer_account_id
)
values
  ('55555555-5555-5555-5555-555555555551', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444441',
   'income',  4000.00, 'USD', 'Monthly salary', current_date - interval '10 days', null),
  ('55555555-5555-5555-5555-555555555552', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444443',
   'expense', 250.00, 'USD', 'Groceries', current_date - interval '8 days', null),
  ('55555555-5555-5555-5555-555555555553', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444444',
   'expense', 1200.00, 'USD', 'Apartment rent', current_date - interval '5 days', null),
  ('55555555-5555-5555-5555-555555555554', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444445',
   'expense', 60.00, 'USD', 'Metro pass', current_date - interval '2 days', null),
  ('55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', null, 'transfer', 300.00, 'USD',
   'Transfer to cash', current_date - interval '3 days', '33333333-3333-3333-3333-333333333331')
on conflict (id) do nothing;

-- 5) Budgets --------------------------------------------------------------
insert into public.budgets (
  id, budget_book_id, category_id, name, amount_limit, period_type, start_date, end_date
)
values
  ('66666666-6666-6666-6666-666666666661', '22222222-2222-2222-2222-222222222222',
   '44444444-4444-4444-4444-444444444443', 'Food budget', 600.00, 'monthly',
   date_trunc('month', current_date)::date, null),
  ('66666666-6666-6666-6666-666666666662', '22222222-2222-2222-2222-222222222222',
   '44444444-4444-4444-4444-444444444444', 'Rent budget', 1200.00, 'monthly',
   date_trunc('month', current_date)::date, null)
on conflict (id) do nothing;
