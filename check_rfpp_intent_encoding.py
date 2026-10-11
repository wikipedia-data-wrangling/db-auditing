"""Validate every staged JSON metadata value as UTF-8 before application."""
import psycopg
with psycopg.connect('service=wiki', application_name='rfpp-intent-encoding-check') as conn:
    conn.execute('SET TRANSACTION READ ONLY')
    count=0
    with conn.cursor(name='encoding_check') as cur:
        cur.execute('SELECT rfpp_id,intent::text FROM analysis.rfpp_intent_v2_stage ORDER BY rfpp_id')
        for identifier, data in cur:
            if isinstance(data,bytes): data.decode('utf-8',errors='strict')
            else: data.encode('utf-8',errors='strict')
            count+=1
    assert count==217554
    print(f'PASS: all {count} staged intent JSON records are valid UTF-8.')
