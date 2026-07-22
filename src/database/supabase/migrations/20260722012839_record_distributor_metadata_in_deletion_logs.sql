create or replace function delete_platform_data(
  p_dataset text,
  p_row_ids text[] default null,
  p_start date default null,
  p_end date default null,
  p_distributor_id uuid default null,
  p_search_key text default null,
  p_search_text text default null,
  p_channel_ids uuid[] default null,
  p_cluster_id uuid default null,
  p_supervisor_id uuid default null
)
returns table (
  deleted_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count bigint := 0;
  v_customer_ids uuid[] := array[]::uuid[];
  v_sales_rep_ids uuid[] := array[]::uuid[];
  v_selected_uuid_ids uuid[] := array[]::uuid[];
  v_selected_bigint_ids bigint[] := array[]::bigint[];
  v_has_selected_rows boolean := coalesce(cardinality(p_row_ids), 0) > 0;
  v_admin_user_id uuid := auth.uid();
  v_admin_email text;
  v_distributor_refs jsonb := '[]'::jsonb;
  v_filters jsonb;
begin
  if not current_user_is_admin() then
    raise exception 'Admin access required';
  end if;

  select u.email::text
  into v_admin_email
  from auth.users u
  where u.id = v_admin_user_id;

  if v_has_selected_rows and p_dataset in ('customers', 'sales_reps') then
    select coalesce(array_agg(distinct row_id::uuid), array[]::uuid[])
    into v_selected_uuid_ids
    from unnest(p_row_ids) row_id;
  elsif v_has_selected_rows and p_dataset in ('sell_out', 'sell_in', 'sales_targets') then
    select coalesce(array_agg(distinct row_id::bigint), array[]::bigint[])
    into v_selected_bigint_ids
    from unnest(p_row_ids) row_id;
  end if;

  case p_dataset
    when 'customers' then
      if v_has_selected_rows then
        v_customer_ids := v_selected_uuid_ids;
      else
        select coalesce(array_agg(c.id), array[]::uuid[])
        into v_customer_ids
        from customers c
        left join channels ch on ch.id = c.channel_id
        left join clusters cl on cl.id = c.cluster_id
        where (p_distributor_id is null or c.distributor_id = p_distributor_id)
          and (coalesce(cardinality(p_channel_ids), 0) = 0 or c.channel_id = any(p_channel_ids))
          and (p_cluster_id is null or c.cluster_id = p_cluster_id)
          and (
            nullif(btrim(coalesce(p_search_text, '')), '') is null
            or case p_search_key
              when 'cnpj' then fn_platform_delete_text_matches(c.cnpj, p_search_text)
              when 'name' then fn_platform_delete_text_matches(c.legal_name, p_search_text)
              when 'district' then fn_platform_delete_text_matches(c.district, p_search_text)
              when 'city' then fn_platform_delete_text_matches(c.city, p_search_text)
              when 'state' then fn_platform_delete_text_matches(c.state::text, p_search_text)
              when 'zip' then fn_platform_delete_text_matches(c.zip_code, p_search_text)
              when 'channel' then fn_platform_delete_text_matches(ch.name, p_search_text)
              when 'cluster' then fn_platform_delete_text_matches(cl.name, p_search_text)
              else false
            end
          );
      end if;

      if cardinality(v_customer_ids) > 0 then
        select coalesce(
          jsonb_agg(distinct jsonb_build_object(
            'id', d.id,
            'code', d.code,
            'name', d.name,
            'cnpj', d.cnpj
          )) filter (where d.id is not null),
          '[]'::jsonb
        )
        into v_distributor_refs
        from customers c
        left join distributors d on d.id = c.distributor_id
        where c.id = any(v_customer_ids);

        delete from sales_targets st
        where st.customer_id = any(v_customer_ids);

        delete from sell_out so
        where so.customer_id = any(v_customer_ids);

        delete from customers c
        where c.id = any(v_customer_ids);

        get diagnostics v_deleted_count = row_count;
        perform refresh_report_views();
      end if;

    when 'sales_reps' then
      if v_has_selected_rows then
        select coalesce(array_agg(sr.id), array[]::uuid[])
        into v_sales_rep_ids
        from sales_reps sr
        where sr.role = 'seller'
          and sr.id = any(v_selected_uuid_ids);
      else
        select coalesce(array_agg(sr.id), array[]::uuid[])
        into v_sales_rep_ids
        from sales_reps sr
        left join sales_reps supervisor on supervisor.id = sr.supervisor_id
        where sr.role = 'seller'
          and (p_distributor_id is null or sr.distributor_id = p_distributor_id)
          and (p_supervisor_id is null or sr.supervisor_id = p_supervisor_id)
          and (
            nullif(btrim(coalesce(p_search_text, '')), '') is null
            or case p_search_key
              when 'name' then fn_platform_delete_text_matches(sr.name, p_search_text)
              when 'supervisor' then fn_platform_delete_text_matches(supervisor.name, p_search_text)
              when 'status' then fn_platform_delete_text_matches(sr.status::text, p_search_text)
              else false
            end
          );
      end if;

      if cardinality(v_sales_rep_ids) > 0 then
        select coalesce(
          jsonb_agg(distinct jsonb_build_object(
            'id', d.id,
            'code', d.code,
            'name', d.name,
            'cnpj', d.cnpj
          )) filter (where d.id is not null),
          '[]'::jsonb
        )
        into v_distributor_refs
        from sales_reps sr
        left join distributors d on d.id = sr.distributor_id
        where sr.id = any(v_sales_rep_ids);

        update customers c
        set sales_rep_id = null
        where c.sales_rep_id = any(v_sales_rep_ids);

        update sell_out so
        set sales_rep_id = null
        where so.sales_rep_id = any(v_sales_rep_ids);

        update sales_targets st
        set sales_rep_id = null
        where st.sales_rep_id = any(v_sales_rep_ids);

        update sales_reps sr
        set manager_id = null
        where sr.manager_id = any(v_sales_rep_ids);

        update sales_reps sr
        set supervisor_id = null
        where sr.supervisor_id = any(v_sales_rep_ids);

        delete from sales_reps sr
        where sr.id = any(v_sales_rep_ids);

        get diagnostics v_deleted_count = row_count;
      end if;

    when 'sell_out' then
      with deleted_rows as (
        delete from sell_out so
        using distributors d, customers c, products p
        where d.id = so.distributor_id
          and c.id = so.customer_id
          and p.id = so.product_id
          and (
            (v_has_selected_rows and so.id = any(v_selected_bigint_ids))
            or (
              not v_has_selected_rows
              and (p_start is null or so.invoice_date >= p_start)
              and (p_end is null or so.invoice_date <= p_end)
              and (p_distributor_id is null or so.distributor_id = p_distributor_id)
              and (
                nullif(btrim(coalesce(p_search_text, '')), '') is null
                or case p_search_key
                  when 'distributor' then fn_platform_delete_text_matches(d.name, p_search_text)
                  when 'customer' then fn_platform_delete_text_matches(c.legal_name, p_search_text)
                  when 'ean' then fn_platform_delete_text_matches(p.ean, p_search_text)
                  when 'product' then fn_platform_delete_text_matches(p.name, p_search_text)
                  else false
                end
              )
            )
          )
        returning so.distributor_id
      )
      select
        count(*),
        coalesce(
          jsonb_agg(distinct jsonb_build_object(
            'id', d.id,
            'code', d.code,
            'name', d.name,
            'cnpj', d.cnpj
          )) filter (where d.id is not null),
          '[]'::jsonb
        )
      into v_deleted_count, v_distributor_refs
      from deleted_rows dr
      left join distributors d on d.id = dr.distributor_id;

      perform refresh_report_views();

    when 'sell_in' then
      with deleted_rows as (
        delete from sell_in si
        using distributors d, products p
        where d.id = si.distributor_id
          and p.id = si.product_id
          and (
            (v_has_selected_rows and si.id = any(v_selected_bigint_ids))
            or (
              not v_has_selected_rows
              and (p_start is null or si.invoice_date >= p_start)
              and (p_end is null or si.invoice_date <= p_end)
              and (p_distributor_id is null or si.distributor_id = p_distributor_id)
              and (
                nullif(btrim(coalesce(p_search_text, '')), '') is null
                or case p_search_key
                  when 'distributor' then fn_platform_delete_text_matches(d.name, p_search_text)
                  when 'ean' then fn_platform_delete_text_matches(p.ean, p_search_text)
                  when 'product' then fn_platform_delete_text_matches(p.name, p_search_text)
                  else false
                end
              )
            )
          )
        returning si.distributor_id
      )
      select
        count(*),
        coalesce(
          jsonb_agg(distinct jsonb_build_object(
            'id', d.id,
            'code', d.code,
            'name', d.name,
            'cnpj', d.cnpj
          )) filter (where d.id is not null),
          '[]'::jsonb
        )
      into v_deleted_count, v_distributor_refs
      from deleted_rows dr
      left join distributors d on d.id = dr.distributor_id;

    when 'sales_targets' then
      with deleted_rows as (
        delete from sales_targets st
        using distributors d, customers c, products p
        where d.id = st.distributor_id
          and c.id = st.customer_id
          and p.id = st.product_id
          and (
            (v_has_selected_rows and st.id = any(v_selected_bigint_ids))
            or (
              not v_has_selected_rows
              and (p_start is null or st.target_date >= p_start)
              and (p_end is null or st.target_date <= p_end)
              and (p_distributor_id is null or st.distributor_id = p_distributor_id)
              and (
                nullif(btrim(coalesce(p_search_text, '')), '') is null
                or case p_search_key
                  when 'distributor' then fn_platform_delete_text_matches(d.name, p_search_text)
                  when 'customer' then fn_platform_delete_text_matches(c.legal_name, p_search_text)
                  when 'ean' then fn_platform_delete_text_matches(p.ean, p_search_text)
                  when 'product' then fn_platform_delete_text_matches(p.name, p_search_text)
                  else false
                end
              )
            )
          )
        returning st.distributor_id
      )
      select
        count(*),
        coalesce(
          jsonb_agg(distinct jsonb_build_object(
            'id', d.id,
            'code', d.code,
            'name', d.name,
            'cnpj', d.cnpj
          )) filter (where d.id is not null),
          '[]'::jsonb
        )
      into v_deleted_count, v_distributor_refs
      from deleted_rows dr
      left join distributors d on d.id = dr.distributor_id;

    else
      raise exception 'Unsupported platform data dataset: %', p_dataset;
  end case;

  v_filters := jsonb_strip_nulls(
    jsonb_build_object(
      'mode', case when v_has_selected_rows then 'selected_rows' else 'filters' end,
      'row_ids', p_row_ids,
      'start', p_start,
      'end', p_end,
      'distributor_id', p_distributor_id,
      'distributors', case
        when jsonb_array_length(v_distributor_refs) > 0 then v_distributor_refs
        else null
      end,
      'search_key', p_search_key,
      'search_text', p_search_text,
      'channel_ids', p_channel_ids,
      'cluster_id', p_cluster_id,
      'supervisor_id', p_supervisor_id
    )
  );

  insert into platform_data_deletion_logs (
    admin_user_id, admin_email, dataset, filters, deleted_count
  ) values (
    v_admin_user_id, v_admin_email, p_dataset, v_filters, v_deleted_count
  );

  return query select v_deleted_count;
end;
$$;

revoke execute on function delete_platform_data(
  text, text[], date, date, uuid, text, text, uuid[], uuid, uuid
) from public, anon;

grant execute on function delete_platform_data(
  text, text[], date, date, uuid, text, text, uuid[], uuid, uuid
) to authenticated;
