-- 0013: Telegram bot sessions.
--
-- The MoneyOK Telegram bot logs a user in through the standard Supabase
-- email/password flow, receives a JWT pair (access_token + refresh_token),
-- encrypts both tokens with AES-256-GCM (key from bot env, never stored
-- here) and stores the ciphertext keyed by telegram_id.
--
-- On every subsequent bot command:
--   1. look up bot_sessions by telegram_id,
--   2. decrypt both tokens,
--   3. refresh the access_token if past expires_at using the refresh_token,
--   4. call /rest/v1 as that authenticated user so RLS scopes everything.
--
-- Access model: NO grant to anon / authenticated and NO RLS policies.
-- Only service_role touches this table, and only the bot uses service_role
-- for this table specifically — every financial request still goes out
-- with the per-user JWT, so RLS remains the source of truth for data.

-- 1) bot_sessions table ---------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_sessions (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_id                 bigint NOT NULL,
  telegram_chat_id            bigint NOT NULL,
  profile_id                  uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  access_token_ciphertext     bytea NOT NULL,
  refresh_token_ciphertext    bytea NOT NULL,
  access_token_expires_at     timestamptz NOT NULL,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS bot_sessions_telegram_id_unique
  ON public.bot_sessions (telegram_id);

CREATE INDEX IF NOT EXISTS bot_sessions_profile_id_idx
  ON public.bot_sessions (profile_id);

CREATE TRIGGER bot_sessions_set_updated_at
  BEFORE UPDATE ON public.bot_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2) RLS ------------------------------------------------------------------
-- Defense in depth: even if a future migration accidentally grants select
-- to authenticated, the absence of any policy keeps the table invisible
-- through PostgREST. Only service_role (which bypasses RLS) can read/write.
ALTER TABLE public.bot_sessions ENABLE ROW LEVEL SECURITY;

-- Intentionally NO policies are created here.

-- 3) Grants ---------------------------------------------------------------
-- service_role is used by the Telegram bot exclusively for this table.
-- anon / authenticated get nothing.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.bot_sessions
  TO service_role;
