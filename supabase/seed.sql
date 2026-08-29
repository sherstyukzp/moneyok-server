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
-- type ∈ {payment, savings, credit_card, investment, reserve, liability, business, cash}
-- archived_at NULL = active; non-NULL = archived at that time.
insert into public.accounts (
  id, budget_book_id, name, type, currency, initial_balance, current_balance,
  color, icon, note, archived_at
)
values
  ('33333333-3333-3333-3333-333333333331', '22222222-2222-2222-2222-222222222222',
   'Cash',      'cash',        'USD', 200.00, 200.00,
   '#10b981', 'wallet',     'Щоденні витрати', null),
  ('33333333-3333-3333-3333-333333333332', '22222222-2222-2222-2222-222222222222',
   'Main Bank', 'payment',     'USD', 5000.00, 5000.00,
   '#3b82f6', 'building-2', 'Основний платіжний рахунок (Monobank)', null),
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222',
   'Credit',    'credit_card', 'USD', 0.00, 0.00,
   '#ef4444', 'credit-card','Кредитна картка для щомісячних витрат', null),
  -- Archived example (savings pot we no longer track).
  ('33333333-3333-3333-3333-333333333334', '22222222-2222-2222-2222-222222222222',
   'Old Savings', 'savings',   'USD', 0.00, 0.00,
   '#a855f7', 'piggy-bank', 'Закритий ощадний рахунок', now() - interval '60 days')
on conflict (id) do nothing;

-- 3) Categories (hierarchical: parent groups + leaf subcategories) ----------
-- Parents (parent_id IS NULL) have no icon/color; subcategories (leaves) do.
insert into public.categories (id, budget_book_id, parent_id, name, kind, icon, color)
values
  -- Parents
  ('44444444-4444-4444-4444-444444444450', '22222222-2222-2222-2222-222222222222', null, 'Їжа та напої', 'expense', null, null),
  ('44444444-4444-4444-4444-444444444460', '22222222-2222-2222-2222-222222222222', null, 'Авто',        'expense', null, null),
  ('44444444-4444-4444-4444-444444444461', '22222222-2222-2222-2222-222222222222', null, 'Житло',      'expense', null, null),
  ('44444444-4444-4444-4444-444444444462', '22222222-2222-2222-2222-222222222222', null, 'Дозвілля',   'expense', null, null),
  ('44444444-4444-4444-4444-444444444463', '22222222-2222-2222-2222-222222222222', null, 'Транспорт',  'expense', null, null),
  ('44444444-4444-4444-4444-444444444466', '22222222-2222-2222-2222-222222222222', null, 'Дохід',      'income',  null, null),
  -- Subcategories (leaves)
  ('44444444-4444-4444-4444-444444444451', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444450', 'Продукти',            'expense', 'cart',           '#f59e0b'),
  ('44444444-4444-4444-4444-444444444452', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444450', 'Кафе і ресторани',    'expense', 'utensils',       '#fb923c'),
  ('44444444-4444-4444-4444-444444444453', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444450', 'Кавʼярні',            'expense', 'coffee',         '#a855f7'),
  ('44444444-4444-4444-4444-444444444454', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444460', 'Паливо',              'expense', 'fuel',           '#16a34a'),
  ('44444444-4444-4444-4444-444444444455', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444460', 'Обслуговування',      'expense', 'wrench',         '#dc2626'),
  ('44444444-4444-4444-4444-444444444456', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444460', 'Автомийка',           'expense', 'car',            '#64748b'),
  ('44444444-4444-4444-4444-444444444457', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444461', 'Оренда',              'expense', 'home',           '#ef4444'),
  ('44444444-4444-4444-4444-444444444458', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444461', 'Комунальні платежі',  'expense', 'zap',            '#eab308'),
  ('44444444-4444-4444-4444-444444444459', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444461', 'Інтернет',            'expense', 'wifi',           '#22c55e'),
  ('44444444-4444-4444-4444-444444444470', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444462', 'Кіно',                'expense', 'clapperboard',   '#ec4899'),
  ('44444444-4444-4444-4444-444444444471', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444462', 'Ігри',                'expense', 'gamepad-2',      '#8b5cf6'),
  ('44444444-4444-4444-4444-444444444472', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444462', 'Книги',               'expense', 'book-open',      '#6366f1'),
  ('44444444-4444-4444-4444-444444444464', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444463', 'Громадський транспорт', 'expense', 'bus',           '#0ea5e9'),
  ('44444444-4444-4444-4444-444444444465', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444463', 'Метро',               'expense', 'train-front',    '#06b6d4'),
  ('44444444-4444-4444-4444-444444444467', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444466', 'Зарплата',            'income',  'briefcase',      '#10b981'),
  ('44444444-4444-4444-4444-444444444468', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444466', 'Фріланс',             'income',  'laptop',         '#06b6d4'),
  ('44444444-4444-4444-4444-444444444469', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444466', 'Подарунки',           'income',  'gift',           '#f59e0b')
on conflict (id) do nothing;

-- 4) Recipients ------------------------------------------------------------
insert into public.recipients (id, budget_book_id, name, account_id, category_id, notes)
values
  ('77777777-7777-7777-7777-777777777771', '22222222-2222-2222-2222-222222222222',
   'Grocery Store', '33333333-3333-3333-3333-333333333332',
   '44444444-4444-4444-4444-444444444451', 'Neighborhood supermarket'),
  ('77777777-7777-7777-7777-777777777772', '22222222-2222-2222-2222-222222222222',
   'Landlord', null, '44444444-4444-4444-4444-444444444457', 'Apartment rent'),
  ('77777777-7777-7777-7777-777777777773', '22222222-2222-2222-2222-222222222222',
   'Metro', null, '44444444-4444-4444-4444-444444444465', 'Public transport card')
on conflict (id) do nothing;

-- 5) Transactions (after accounts + categories + recipients so FKs resolve) --
-- Balances are maintained by the apply_transaction_balance trigger.
insert into public.transactions (
  id, budget_book_id, account_id, category_id, type, amount, currency,
  note, transaction_date, transfer_account_id, recipient_id
)
values
  ('55555555-5555-5555-5555-555555555551', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444467',
   'income',  4000.00, 'USD', 'Monthly salary', current_date - interval '10 days', null, null),
  ('55555555-5555-5555-5555-555555555552', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444451',
   'expense', 250.00, 'USD', 'Groceries', current_date - interval '8 days', null,
   '77777777-7777-7777-7777-777777777771'),
  ('55555555-5555-5555-5555-555555555553', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', '44444444-4444-4444-4444-444444444457',
   'expense', 1200.00, 'USD', 'Apartment rent', current_date - interval '5 days', null,
   '77777777-7777-7777-7777-777777777772'),
  ('55555555-5555-5555-5555-555555555554', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333331', '44444444-4444-4444-4444-444444444465',
   'expense', 60.00, 'USD', 'Metro pass', current_date - interval '2 days', null,
   '77777777-7777-7777-7777-777777777773'),
  ('55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333332', null, 'transfer', 300.00, 'USD',
   'Transfer to cash', current_date - interval '3 days', '33333333-3333-3333-3333-333333333331', null)
on conflict (id) do nothing;

-- 5) Budgets --------------------------------------------------------------
insert into public.budgets (
  id, budget_book_id, category_id, name, amount_limit, period_type, start_date, end_date
)
values
  ('66666666-6666-6666-6666-666666666661', '22222222-2222-2222-2222-222222222222',
   '44444444-4444-4444-4444-444444444451', 'Food budget', 600.00, 'monthly',
   date_trunc('month', current_date)::date, null),
  ('66666666-6666-6666-6666-666666666662', '22222222-2222-2222-2222-222222222222',
   '44444444-4444-4444-4444-444444444457', 'Rent budget', 1200.00, 'monthly',
   date_trunc('month', current_date)::date, null)
on conflict (id) do nothing;
