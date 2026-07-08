#!/usr/bin/env python3
"""Generate src/database/supabase/seed.sql from the real import sample.

Reads the `.dev_files/dados-importacao/*.xlsx` layouts and emits a deterministic
SQL seed (explicit UUIDs) that loads real master data + transactional data, so
the local Supabase can validate the system with a correct sample.

Run from the repo root:
    python3 src/database/scripts/generate_seed_from_sample.py
"""
from __future__ import annotations

import os
import uuid
from datetime import datetime

import openpyxl

SAMPLE_DIR = os.environ.get(
    "SAMPLE_DIR",
    os.path.join(os.path.dirname(__file__), "..", "..", "..", ".dev_files", "dados-importacao"),
)
OUT_PATH = os.path.join(os.path.dirname(__file__), "..", "supabase", "seed.sql")
NS = uuid.UUID("6f0c3a2e-1b7d-4e5a-9c3b-000000000000")
ADMIN_USER_ID = "00000000-0000-0000-0000-000000000001"
ADMIN_EMAIL = "admin@email.com"
ADMIN_PASSWORD = "123321"


def uid(*parts: str) -> str:
    return str(uuid.uuid5(NS, "|".join(str(p) for p in parts)))


def rows(fname: str) -> list[tuple]:
    wb = openpyxl.load_workbook(os.path.join(SAMPLE_DIR, fname), read_only=True, data_only=True)
    ws = wb.active
    data = list(ws.iter_rows(min_row=2, values_only=True))
    wb.close()
    return data


def sql_str(value) -> str:
    if value is None or value == "":
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def num(value) -> str:
    if value is None or value == "":
        return "null"
    text = str(value).strip()
    # Brazilian decimals: if a comma is present, it's the decimal separator.
    if "," in text:
        text = text.replace(".", "").replace(",", ".")
    try:
        return repr(float(text))
    except ValueError:
        return "null"


def ean_core(ean) -> str:
    e = str(ean).strip()
    if len(e) == 14 and e.startswith("1"):
        return e[1:]
    return e


def iso(dt) -> str | None:
    if dt is None:
        return None
    if isinstance(dt, datetime):
        return dt.date().isoformat()
    return str(dt)[:10]


def main() -> None:
    # ---- read files ----
    clientes = rows("Layout Clientes.xlsx")
    produtos = rows("Layout Produtos.xlsx")
    vendedores = rows("Layout Vendedores.xlsx")
    sellout = rows("Layout SellOut.xlsx") + rows("Layout SellOut_aa.xlsx")
    sellin = rows("Layout SellIn.xlsx") + rows("Layout SellIn_aa.xlsx")
    meta = rows("Layout SellOut_meta.xlsx")

    dist_cnpj = str(clientes[0][0])
    dist_id = uid("dist", dist_cnpj)

    # ---- channels / clusters ----
    channels = sorted({str(r[10]) for r in clientes if r[10]})
    clusters = sorted({str(r[11]) for r in clientes if r[11]})
    channel_id = {c: uid("channel", c) for c in channels}
    cluster_id = {c: uid("cluster", c) for c in clusters}

    # ---- product hierarchy (macro -> cat -> sub) + products ----
    macros, cats, subs = {}, {}, {}  # name -> id ; sub -> (id, cat, macro)
    products = {}  # core_ean -> dict
    for r in produtos:
        ean, desc, caixa, unidades, sub, cat, macro, sku = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]
        if ean is None or str(ean).strip() in ("", "None"):
            continue
        core = ean_core(ean)
        if core in products:
            continue
        macros.setdefault(str(macro), uid("macro", macro))
        cats.setdefault(str(cat), uid("cat", macro, cat))
        subs.setdefault(str(sub), (uid("sub", macro, cat, sub), str(cat), str(macro)))
        products[core] = {
            "id": uid("prod", core),
            "ean": str(ean).strip(),
            "sku": str(sku).strip() if sku else None,
            "name": str(desc).strip(),
            "sub": str(sub),
            "box": caixa,
            "units": unidades,
        }

    # ---- sales reps (supervisors + sellers) ----
    supervisors, sellers = {}, {}  # code -> dict
    for r in vendedores:
        if r[1] is None or str(r[1]).strip() in ("", "None"):
            continue
        vcode, vname, carteira, scode, sname = str(r[1]), r[2], r[3], str(r[4]), r[5]
        supervisors.setdefault(scode, {"id": uid("sup", scode), "name": str(sname)})
        if vcode not in sellers:
            sellers[vcode] = {
                "id": uid("seller", vcode),
                "name": str(vname),
                "supervisor": scode,
                "carteira": int(carteira) if carteira else None,
            }

    # ---- customers (by pdv_code) + stubs for PDVs only seen in sell out ----
    customers = {}  # pdv_code -> dict
    for r in clientes:
        pdv = str(r[1])
        if pdv in customers:
            continue
        customers[pdv] = {
            "id": uid("cust", dist_cnpj, pdv),
            "cnpj": str(r[2]).strip() if r[2] else None,
            "legal": str(r[3]).strip() if r[3] else f"PDV {pdv}",
            "trade": str(r[4]).strip() if r[4] else None,
            "address": str(r[5]).strip() if r[5] else None,
            "district": str(r[6]).strip() if r[6] else None,
            "city": str(r[7]).strip() if r[7] else None,
            "state": str(r[8]).strip()[:2] if r[8] else None,
            "zip": str(r[9]).strip() if r[9] else None,
            "channel": str(r[10]) if r[10] else None,
            "cluster": str(r[11]) if r[11] else None,
        }
    for r in sellout:
        pdv = str(r[2])
        if pdv not in customers:
            customers[pdv] = {
                "id": uid("cust", dist_cnpj, pdv), "cnpj": None,
                "legal": f"PDV {pdv}", "trade": None, "address": None,
                "district": None, "city": None, "state": None, "zip": None,
                "channel": None, "cluster": None,
            }

    # ---- write ----
    out = []
    w = out.append
    w("-- AUTO-GENERATED by src/database/scripts/generate_seed_from_sample.py")
    w("-- Source: .dev_files/dados-importacao (real anonymized single-distributor sample).")
    w("-- Do not edit by hand; regenerate with the script.\n")

    w("insert into auth.users (")
    w("  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,")
    w("  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin")
    w(") values (")
    w(f"  '{ADMIN_USER_ID}', '00000000-0000-0000-0000-000000000000',")
    w(f"  'authenticated', 'authenticated', {sql_str(ADMIN_EMAIL)},")
    w(f"  extensions.crypt({sql_str(ADMIN_PASSWORD)}, extensions.gen_salt('bf')),")
    w("  now(), now(), now(),")
    w("  '{\"provider\":\"email\",\"providers\":[\"email\"]}'::jsonb,")
    w("  '{}'::jsonb, false")
    w(") on conflict (id) do update set")
    w("  email = excluded.email,")
    w("  encrypted_password = excluded.encrypted_password,")
    w("  email_confirmed_at = excluded.email_confirmed_at,")
    w("  raw_app_meta_data = excluded.raw_app_meta_data,")
    w("  updated_at = now();\n")

    w("insert into auth.identities (")
    w("  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at")
    w(") values (")
    w(f"  '{ADMIN_USER_ID}', '{ADMIN_USER_ID}', {sql_str(ADMIN_EMAIL)},")
    w("  jsonb_build_object(")
    w(f"    'sub', '{ADMIN_USER_ID}',")
    w(f"    'email', {sql_str(ADMIN_EMAIL)},")
    w("    'email_verified', true,")
    w("    'phone_verified', false")
    w("  ),")
    w("  'email', now(), now(), now()")
    w(") on conflict (provider, provider_id) do update set")
    w("  user_id = excluded.user_id,")
    w("  identity_data = excluded.identity_data,")
    w("  updated_at = now();\n")

    w("insert into distributors (id, code, name, cnpj, status) values")
    w(f"  ('{dist_id}', 'DIST{dist_cnpj}', 'Distribuidora {dist_cnpj}', {sql_str(dist_cnpj)}, 'active');\n")

    w("insert into distributor_users (user_id, distributor_id, role, status) values")
    w(f"  ('{ADMIN_USER_ID}', '{dist_id}', 'owner', 'active')")
    w("on conflict (user_id, distributor_id) do update set")
    w("  role = excluded.role,")
    w("  status = excluded.status,")
    w("  updated_at = now();\n")

    # File type configs + a small import history so the Arquivos screens have content.
    ftc = [
        ("SELL_OUT", "Sell Out Distribuidor", "sell_out", "process_sell_out_staging", "xlsx"),
        ("SELL_IN", "Sell In Indústria", "sell_in", "process_sell_in_staging", "xlsx"),
        ("CUSTOMERS", "Base de Clientes", "customers", "upsert_customers", "xlsx"),
        ("PRODUCTS", "Base de Produtos", "products", "upsert_products", "xlsx"),
        ("SELLERS", "Base de Vendedores", "sales_reps", "upsert_sellers", "xlsx"),
        ("TARGETS", "Metas por Cliente/SKU", "sales_targets", "upsert_targets", "xlsx"),
    ]
    ftc_id = {code: uid("ftc", code) for code, *_ in ftc}
    w("insert into file_type_configs (id, code, name, target_table, processing_routine, file_format) values")
    w(",\n".join(
        f"  ('{ftc_id[code]}', {sql_str(code)}, {sql_str(name)}, {sql_str(tbl)}, {sql_str(rout)}, {sql_str(fmt)})"
        for code, name, tbl, rout, fmt in ftc) + ";\n")

    imports = [
        ("Layout SellOut.xlsx", "SELL_OUT", "completed", 3374, 3057, 0),
        ("Layout SellIn.xlsx", "SELL_IN", "completed", 30, 30, 0),
        ("Layout Clientes.xlsx", "CUSTOMERS", "completed_with_errors", 6334, 6095, 6),
        ("Layout Produtos.xlsx", "PRODUCTS", "completed", 5, 5, 0),
        ("Layout Vendedores.xlsx", "SELLERS", "completed", 13, 13, 0),
        ("Layout SellOut_meta.xlsx", "TARGETS", "completed", 3362, 1469, 0),
    ]
    w("insert into file_imports (file_name, sheet_name, file_type_id, status, total_records, processed_records, error_count, imported_by, distributor_id, finished_at) values")
    w(",\n".join(
        f"  ({sql_str(fn)}, 'Planilha1', '{ftc_id[code]}', '{st}'::import_status, {tot}, {proc}, {err}, "
        f"'{ADMIN_USER_ID}', '{dist_id}', now() - '{i} days'::interval)"
        for i, (fn, code, st, tot, proc, err) in enumerate(imports, start=1)) + ";\n")

    w("insert into channels (id, distributor_id, name) values")
    w(",\n".join(f"  ('{channel_id[c]}', '{dist_id}', {sql_str(c)})" for c in channels) + ";\n")

    w("insert into clusters (id, distributor_id, name) values")
    w(",\n".join(f"  ('{cluster_id[c]}', '{dist_id}', {sql_str(c)})" for c in clusters) + ";\n")

    # hierarchy: macro, then cat, then sub
    w("insert into product_hierarchy (id, distributor_id, parent_id, level, name) values")
    lines = [f"  ('{mid}', '{dist_id}', null, 'macro_category', {sql_str(m)})" for m, mid in macros.items()]
    for c, cid in cats.items():
        macro_of = next(str(r[7]) for r in produtos if str(r[6]) == c)
        lines.append(f"  ('{cid}', '{dist_id}', '{macros[macro_of]}', 'category', {sql_str(c)})")
    for s, (sid, cat, macro) in subs.items():
        lines.append(f"  ('{sid}', '{dist_id}', '{cats[cat]}', 'subcategory', {sql_str(s)})")
    w(",\n".join(lines) + ";\n")

    w("insert into products (id, ean, sku_code, name, subcategory_id, unit_label, units_per_pack, box_count, distributor_id) values")
    plines = []
    for core, p in products.items():
        sid = subs[p["sub"]][0]
        plines.append(
            f"  ('{p['id']}', {sql_str(p['ean'])}, {sql_str(p['sku'])}, {sql_str(p['name'])}, "
            f"'{sid}', 'CX', {num(p['units'])}, {num(p['box'])}, '{dist_id}')"
        )
    w(",\n".join(plines) + ";\n")

    w("insert into sales_reps (id, name, role, code, distributor_id) values")
    w(",\n".join(
        f"  ('{s['id']}', {sql_str(s['name'])}, 'supervisor', {sql_str(code)}, '{dist_id}')"
        for code, s in supervisors.items()) + ";\n")
    w("insert into sales_reps (id, name, role, supervisor_id, code, portfolio_size, distributor_id) values")
    w(",\n".join(
        f"  ('{s['id']}', {sql_str(s['name'])}, 'seller', '{supervisors[s['supervisor']]['id']}', "
        f"{sql_str(code)}, {s['carteira'] if s['carteira'] is not None else 'null'}, '{dist_id}')"
        for code, s in sellers.items()) + ";\n")

    # customers in batches
    def batch(header: str, values: list[str], size: int = 500) -> None:
        for i in range(0, len(values), size):
            w(header)
            w(",\n".join(values[i:i + size]) + ";\n")

    cust_vals = []
    for pdv, c in customers.items():
        ch = f"'{channel_id[c['channel']]}'" if c["channel"] in channel_id else "null"
        cl = f"'{cluster_id[c['cluster']]}'" if c["cluster"] in cluster_id else "null"
        cust_vals.append(
            f"  ('{c['id']}', {sql_str(c['cnpj'])}, {sql_str(c['legal'])}, {sql_str(c['trade'])}, "
            f"{sql_str(c['address'])}, {sql_str(c['district'])}, {sql_str(c['city'])}, {sql_str(c['state'])}, "
            f"{sql_str(c['zip'])}, {ch}, {cl}, '{dist_id}', {sql_str(pdv)}, 'active')"
        )
    batch(
        "insert into customers (id, cnpj, legal_name, trade_name, address, district, city, state, "
        "zip_code, channel_id, cluster_id, distributor_id, pdv_code, status) values",
        cust_vals,
    )

    # partitions for the transactional window
    all_dates = [iso(r[6]) for r in sellout if r[6]] + [iso(r[4]) for r in sellin if r[4]]
    months = sorted({d[:7] + "-01" for d in all_dates if d})
    for m in months:
        w(f"select ensure_month_partition('sell_out', '{m}'::date);")
        w(f"select ensure_month_partition('sell_in', '{m}'::date);")
    w("")

    # sell out: invoice_number proxy = pdv-date (one invoice per customer/day)
    so_vals, skipped_so = [], 0
    for r in sellout:
        pdv, ean, vcode, vol, val, dt = str(r[2]), r[1], str(r[3]), r[4], r[5], iso(r[6])
        core = ean_core(ean)
        p = products.get(core)
        c = customers.get(pdv)
        s = sellers.get(vcode)
        if not (p and c and dt and vol is not None and val is not None):
            skipped_so += 1
            continue
        inv = f"{pdv}-{dt}"
        srep = f"'{s['id']}'" if s else "null"
        so_vals.append(
            f"  ('{dist_id}', '{c['id']}', '{p['id']}', {srep}, {sql_str(inv)}, "
            f"'{dt}', {num(vol)}, {num(val)})"
        )
    batch(
        "insert into sell_out (distributor_id, customer_id, product_id, sales_rep_id, "
        "invoice_number, invoice_date, quantity, gross_value) values",
        so_vals,
    )

    # sell in: EAN core match to product; invoice proxy per product/day
    si_vals, skipped_si = [], 0
    for r in sellin:
        ean, vol, val, dt = r[1], r[2], r[3], iso(r[4])
        p = products.get(ean_core(ean))
        if not (p and dt and vol is not None and val is not None):
            skipped_si += 1
            continue
        si_vals.append(
            f"  ('{dist_id}', '{p['id']}', {sql_str('SI-' + p['ean'] + '-' + dt)}, "
            f"'{dt}', {num(vol)}, {num(val)})"
        )
    batch(
        "insert into sell_in (distributor_id, product_id, invoice_number, invoice_date, "
        "quantity, gross_value) values",
        si_vals,
    )

    # targets: aggregate target by (customer, product, month)
    agg: dict[tuple, list[float]] = {}
    for r in meta:
        pdv, ean, vol, val, dt = str(r[2]), r[1], r[4], r[5], iso(r[6])
        p = products.get(ean_core(ean))
        c = customers.get(pdv)
        if not (p and c and dt):
            continue
        key = (c["id"], p["id"], dt[:7] + "-01")
        acc = agg.setdefault(key, [0.0, 0.0])
        try:
            acc[0] += float(str(vol).replace(",", ".")) if vol is not None else 0
            acc[1] += float(str(val).replace(",", ".")) if val is not None else 0
        except ValueError:
            pass
    tgt_vals = [
        f"  ('{dist_id}', '{cid}', '{pid}', '{month}', {qty!r}, {round(gv, 2)!r})"
        for (cid, pid, month), (qty, gv) in agg.items()
    ]
    batch(
        "insert into sales_targets (distributor_id, customer_id, product_id, target_date, quantity, gross_value) values",
        tgt_vals,
    )

    w("select refresh_report_views();")

    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")

    print(f"seed.sql escrito: {os.path.abspath(OUT_PATH)}")
    print(f"  distribuidor: {dist_cnpj}")
    print(f"  canais={len(channels)} clusters={len(clusters)} produtos={len(products)}")
    print(f"  hierarquia: {len(macros)} macro / {len(cats)} cat / {len(subs)} sub")
    print(f"  supervisores={len(supervisors)} vendedores={len(sellers)} clientes={len(customers)}")
    print(f"  sell_out={len(so_vals)} (skip {skipped_so})  sell_in={len(si_vals)} (skip {skipped_si})  metas={len(tgt_vals)}")


if __name__ == "__main__":
    main()
