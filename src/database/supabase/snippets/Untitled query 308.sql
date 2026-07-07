select 'distributors' t, count(*) from distributors
union all select 'customers', count(*) from customers
union all select 'products', count(*) from products
union all select 'sell_out', count(*) from sell_out
union all select 'stock_snapshots', count(*) from stock_snapshots;