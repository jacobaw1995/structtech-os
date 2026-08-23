-- Temporary: lets me call the deployed edge function from inside Postgres to verify
-- it boots. Dropped again immediately after the check.
create extension if not exists http with schema extensions;
