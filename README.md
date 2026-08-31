# moneyok-server — Supabase backend for a personal finance MVP

Backend for a personal finance budgeting app built entirely on **Supabase**
(Postgres + Supabase Auth + PostgREST REST API), running 100% locally via the
**Supabase CLI** and **Docker**. There is no custom Python/FastAPI backend —
the database schema, RLS and triggers are the backend.

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  Frontend (any client)                                 │
│  • supabase-js  ──► PostgREST REST / GraphQL           │
│  • users sign in via Supabase Auth (email/password)    │
└──────────────────────────┬─────────────────────────────┘
                           │ JWT (supabase-js / REST)
┌──────────────────────────▼─────────────────────────────┐
│  Supabase (local: CLI + Docker)                        │
│  • PostgREST API  :54321/rest/v1                       │
│  • Auth (GoTrue)  :54321/auth/v1                       │
│  • Postgres       :54322                                │
│  • Studio         :54323                                │
│  • built-in MCP   :54321/mcp  (for future AI/MCP layer) │
└────────────────────────────────────────────────────────┘
```

- **Ownership model:** every financial entity belongs to a `budget_book`,
  and each `budget_book` belongs to a user. RLS resolves access by walking
  `entity → budget_book(user_id) → auth.uid()`.
- **Auth foundation:** triggers auto-create a `profile` and a default
  `Personal` budget book on signup (`0002`, `0003`).
- **Business logic in DB:** balance maintenance and cross-book validation
  are handled by PG triggers so clients never compute balances. Account
  owners may still directly UPDATE `current_balance` for reconciliation —
  the trigger only fires on transaction changes, not on account changes,
  so a manual override sticks as the new baseline for future transactions.
- **Multi-book ready:** schema already supports `Personal` / `Family` / `Work`
  books; a user simply creates more books, and every entity scopes to one.

## Directory layout

```
supabase/
├── config.toml          # port, project_id, seed paths, etc.
├── seed.sql             # local demo data (idempotent)
└── migrations/
    ├── 0001_extensions.sql            # pgcrypto, updated_at trigger
    ├── 0002_profiles_auth.sql          # profiles + auth signup trigger
    ├── 0003_budget_books.sql           # budget_books + default book trigger
    ├── 0004_accounts_categories.sql    # accounts, categories
    ├── 0005_transactions.sql           # transactions + balance triggers
    ├── 0006_budgets.sql                # budgets
    ├── 0007_rls.sql                    # RLS policies + grants
    ├── 0008_revoke_security_definer_execute.sql
    ├── 0009_categories_subcategories.sql   # hierarchical categories (parents + leaves)
    ├── 0010_recipients.sql                  # recipients + transactions.recipient_id
    ├── 0011_tags.sql                        # tags + transactions.tag_id
    ├── 0012_accounts_enhancements.sql       # accounts: richer type, color/icon/note, archived_at
    └── 0013_bot_sessions.sql                # Telegram bot sessions (encrypted JWT pair per telegram_id, service_role only)
```

## Schema & relationships

```
profiles (auth.users)
  └─ budget_books (1 user → N books; one is_default per user)
       ├─ accounts      (N per book)
       ├─ categories    (N per book; parents + leaves, kind = income|expense)
       ├─ transactions  (N per book)
       ├─ budgets       (N per book; per category)
       ├─ recipients    (N per book)
       └─ tags          (N per book)
bot_sessions (separate tree: telegram_id → profile_id; service_role only)
```

Entities:

| Table | Key fields | Notes |
|-------|-----------|-------|
| `profiles` | id, email, full_name, default_currency | 1:1 with auth.users |
| `budget_books` | user_id, name, is_default | unique partial index: 1 default/user |
| `accounts` | budget_book_id, name, type, currency, color, icon, note, initial_balance, current_balance, archived_at | type: payment/savings/credit_card/investment/reserve/liability/business/cash; `archived_at` NULL = active |
| `categories` | budget_book_id, name, kind, icon, color, parent_id | unique (book, lower(name), kind); leaves only accept transactions |
| `transactions` | account_id, category_id?, transfer_account_id?, recipient_id?, tag_id?, type, amount, occurred_at | type: income/expense/transfer; balance maintained by trigger |
| `budgets` | category_id, amount_limit, period_type, start_date, end_date | period_type: monthly/yearly/custom |
| `bot_sessions` | telegram_id unique, profile_id, encrypted access/refresh token bytea, access_token_expires_at | Telegram bot only; service_role access; encryption key lives in bot env |

Cross-entity integrity is enforced by triggers (`0005`, `0006`) that reject
rows whose `account`/`category`/`transfer_account` aren't in the same
`budget_book`. Balances update automatically via `apply_transaction_balance`.

## RLS logic (`0007_rls.sql`)

RLS is enabled on every table. All policies are per-table, per-row and go
through ownership of the parent `budget_book`:

| Table | Rule |
|-------|------|
| `profiles` | `auth.uid() = id` |
| `budget_books` | `auth.uid() = user_id` |
| `accounts` / `categories` / `transactions` / `budgets` | `EXISTS (SELECT 1 FROM budget_books bb WHERE bb.id = <row>.budget_book_id AND bb.user_id = auth.uid())` |

Each table has `select / insert / update / delete` policies, so unauthenticated
(`anon`) requests see zero rows and no user can read or write another user's
data. `service_role` bypasses RLS for seeds and background jobs.

## Local run

Prerequisites: **Docker** (running) and the **Supabase CLI**.

Install the CLI (macOS):

```bash
brew install supabase/tap/supabase
```

Start everything (applies migrations + seed):

```bash
supabase start
```

The CLI prints connection URLs and keys. Typical values:

| Service | URL |
|---------|-----|
| REST API | `http://127.0.0.1:54321/rest/v1` |
| Auth | `http://127.0.0.1:54321/auth/v1` |
| Studio (web UI) | `http://127.0.0.1:54323` |
| Built-in MCP endpoint | `http://127.0.0.1:54321/mcp` |

Reset the DB to migrations + seed at any time:

```bash
supabase db reset
```

Stop:

```bash
supabase stop
```

### Demo user (from seed)

| | |
|---|---|
| Email | `demo@moneyok.local` |
| Password | `demo-password` |

The seed creates the demo profile, a default `Personal` budget book, 4
accounts (3 active + 1 archived example), 6 categories, 5 transactions and 2 budgets. Balances are already
consistent (auto-maintained by triggers).

### Quick REST sanity check

```bash
ANON="<ANON_KEY printed by supabase start>"

# sign in as demo
TOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"demo@moneyok.local","password":"demo-password"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# read owned data
curl -s "http://127.0.0.1:54321/rest/v1/budget_books?select=id,name,is_default" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN"
```

```js
// supabase-js equivalent
const supabase = createClient(REST_URL, ANON_KEY);
await supabase.auth.signInWithPassword({ email, password });
const { data } = await supabase
  .from('transactions')
  .select('*, account:accounts(name), category:categories(name)');
```

## Auth model

- Email/password via Supabase Auth.
- On `auth.users` insert → `handle_new_user()` creates `profiles` row.
- On `profiles` insert → `handle_new_default_book()` creates the default
  `Personal` budget book.
- Access to all app tables is gated by RLS using `auth.uid()`.

## MCP / AI agent layer

Supabase exposes a built-in MCP server at `http://127.0.0.1:54321/mcp`
(available once `supabase start` is running). It exposes tools such as
`list_tables`, `execute_sql`, `get_advisors`, `get_logs`, etc., so AI clients
can introspect the schema and run against the local database for accurate
migrations and debugging.

This repo's `opencode.json` already wires that endpoint into opencode:

```json
{
  "mcp": {
    "supabase": {
      "type": "remote",
      "url": "http://127.0.0.1:54321/mcp",
      "enabled": true
    }
  }
}
```

Notes:
- Restart opencode after changing `opencode.json`.
- The schema is normalized around `budget_book` ownership, so a future custom
  MCP layer can expose clean, user-scoped tools (`list_books`,
  `add_transaction`, `get_budget_status`, …).
