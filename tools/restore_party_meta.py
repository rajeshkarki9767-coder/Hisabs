#!/usr/bin/env python3
"""v89.170 recovery: convert a dumped data.partyMetas JSON array into an
idempotent INSERT for public.app_party_meta.

Usage: python3 restore_party_meta.py dump.json > restore.sql
The dump is exactly what `JSON.stringify(data.partyMetas)` produced in the
browser console: [{id, businessId, meta}, ...].
"""
import json, sys

def pg_str(s):
    return "'" + str(s).replace("'", "''") + "'"

def main(path):
    rows = json.load(open(path, encoding='utf-8'))
    assert isinstance(rows, list) and rows, 'dump is empty or not a list'
    values = []
    skipped = 0
    for r in rows:
        if not r or not r.get('id') or not r.get('businessId'):
            skipped += 1
            continue
        meta = r.get('meta')
        meta_sql = (pg_str(json.dumps(meta, ensure_ascii=False)) + '::jsonb') if meta else 'NULL'
        values.append(f"({pg_str(r['id'])}, {pg_str(r['businessId'])}, {meta_sql})")
    assert values, 'no usable rows'
    print('-- v89.170 recovery: restore app_party_meta from device dump')
    print(f'-- rows in dump: {len(rows)}, restorable: {len(values)}, skipped: {skipped}')
    print('INSERT INTO public.app_party_meta (id, business_id, meta)')
    print('VALUES')
    print(',\n'.join('  ' + v for v in values))
    print('ON CONFLICT (id) DO UPDATE SET meta = EXCLUDED.meta, business_id = EXCLUDED.business_id;')
    print()
    print('-- VERIFY:')
    print('SELECT count(*) FROM public.app_party_meta;')

if __name__ == '__main__':
    main(sys.argv[1])
