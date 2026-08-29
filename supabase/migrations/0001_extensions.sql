-- 0001: Enable extensions used across the schema.
-- pgcrypto provides gen_random_uuid() for primary key generation.

create extension if not exists pgcrypto;

-- updated_at trigger used by every table.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
