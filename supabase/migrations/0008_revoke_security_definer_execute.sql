-- 0008: Harden internal SECURITY DEFINER trigger functions.
--
-- These functions are used only by DB triggers and should never be exposed
-- as PostgREST RPC endpoints (/rest/v1/rpc/...).
--
-- Sources of EXECUTE on these functions:
--   1. Supabase roles.sql runs ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE
--      ON FUNCTIONS TO anon, authenticated, service_role, so every new
--      function gets explicit EXECUTE grants to those roles at creation.
--   2. Postgres also grants EXECUTE to PUBLIC (`=X`) by default for new
--      functions; anon/authenticated inherit it via the PUBLIC pseudo-role.
--
-- We revoke both so the functions are no longer callable via PostgREST.
-- Trigger execution is unaffected: triggers invoke these functions
-- regardless of EXECUTE privilege (privilege only gates direct CALL/use).

revoke execute on function public.set_updated_at()                  from anon, authenticated, public;
revoke execute on function public.handle_new_user()                 from anon, authenticated, public;
revoke execute on function public.handle_new_default_book()         from anon, authenticated, public;
revoke execute on function public.apply_transaction_balance()       from anon, authenticated, public;
revoke execute on function public.transactions_validate_book()      from anon, authenticated, public;
revoke execute on function public.budgets_validate_category_book()  from anon, authenticated, public;
