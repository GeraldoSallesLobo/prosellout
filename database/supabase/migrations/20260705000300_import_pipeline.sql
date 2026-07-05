-- File import pipeline: type configuration, import tracking and line-level logs.
-- Files are uploaded to S3 by the frontend (presigned URL); AWS Lambdas update
-- these tables through the service role while processing.

create type import_status as enum (
  'pending', 'validating', 'processing', 'completed', 'completed_with_errors', 'failed'
);
create type import_log_level as enum ('info', 'warning', 'error');

create table file_type_configs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  target_table text not null,
  processing_routine text not null,
  file_format text not null check (file_format in ('xlsx', 'csv')),
  origin text not null default 'upload',
  status entity_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table file_imports (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  sheet_name text,
  file_type_id uuid not null references file_type_configs(id),
  storage_key text,
  status import_status not null default 'pending',
  total_records integer not null default 0,
  processed_records integer not null default 0,
  error_count integer not null default 0,
  imported_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create index file_imports_status_idx on file_imports (status, created_at desc);
create index file_imports_type_idx on file_imports (file_type_id);

create table file_import_logs (
  id bigint generated always as identity primary key,
  import_id uuid not null references file_imports(id) on delete cascade,
  line_number integer,
  level import_log_level not null default 'info',
  message text not null,
  created_at timestamptz not null default now()
);

create index file_import_logs_import_idx on file_import_logs (import_id, id);

create trigger file_type_configs_set_updated_at
  before update on file_type_configs
  for each row execute function set_updated_at();
