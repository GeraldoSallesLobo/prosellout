-- Required Postgres extensions.
-- pg_cron: scheduled jobs (partition creation, materialized view refresh).
-- pgcrypto: gen_random_uuid().
create extension if not exists pgcrypto;
create extension if not exists pg_cron;
