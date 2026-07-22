create or replace function sanitize_staging_import_dimensions()
returns trigger
language plpgsql
as $$
begin
  new.channel_name = nullif(btrim(new.channel_name), '');
  new.cluster_name = nullif(btrim(new.cluster_name), '');

  if lower(coalesce(new.channel_name, '')) = '[object object]' then
    new.channel_name = null;
  end if;

  if lower(coalesce(new.cluster_name, '')) = '[object object]' then
    new.cluster_name = null;
  end if;

  return new;
end;
$$;

drop trigger if exists sanitize_staging_sell_out_import_dimensions on staging_sell_out;
create trigger sanitize_staging_sell_out_import_dimensions
before insert or update on staging_sell_out
for each row
execute function sanitize_staging_import_dimensions();

drop trigger if exists sanitize_staging_targets_import_dimensions on staging_targets;
create trigger sanitize_staging_targets_import_dimensions
before insert or update on staging_targets
for each row
execute function sanitize_staging_import_dimensions();

with invalid_channels as (
  select id
  from channels
  where name = '[object Object]'
),
invalid_clusters as (
  select id
  from clusters
  where name = '[object Object]'
)
update sell_out so
set
  channel_id = c.channel_id,
  cluster_id = c.cluster_id
from customers c
where c.id = so.customer_id
  and (
    so.channel_id in (select id from invalid_channels)
    or so.cluster_id in (select id from invalid_clusters)
  );

with invalid_channels as (
  select id
  from channels
  where name = '[object Object]'
),
invalid_clusters as (
  select id
  from clusters
  where name = '[object Object]'
)
update sales_targets t
set
  channel_id = c.channel_id,
  cluster_id = c.cluster_id
from customers c
where c.id = t.customer_id
  and (
    t.channel_id in (select id from invalid_channels)
    or t.cluster_id in (select id from invalid_clusters)
  );

delete from channels ch
where ch.name = '[object Object]'
  and not exists (
    select 1
    from sell_out so
    where so.channel_id = ch.id
  )
  and not exists (
    select 1
    from sales_targets t
    where t.channel_id = ch.id
  )
  and not exists (
    select 1
    from customers c
    where c.channel_id = ch.id
  );

delete from clusters cl
where cl.name = '[object Object]'
  and not exists (
    select 1
    from sell_out so
    where so.cluster_id = cl.id
  )
  and not exists (
    select 1
    from sales_targets t
    where t.cluster_id = cl.id
  )
  and not exists (
    select 1
    from customers c
    where c.cluster_id = cl.id
  );

select refresh_report_views();
