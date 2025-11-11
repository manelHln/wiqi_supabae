const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars');
}
Deno.serve(async (req)=>{
  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({
        error: 'Only POST allowed'
      }), {
        status: 405,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    const payload = await req.json().catch(()=>null);
    console.log(payload);
    if (!payload || !Array.isArray(payload)) {
      return new Response(JSON.stringify({
        error: 'Request body must be a JSON array of coupon objects'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 48 * 60 * 60 * 1000).toISOString(); // 48 hours
    const results = [];
    const rows = payload.map((item)=>({
        code: item.code,
        restrictions: item.restrictions ?? null,
        description: item.description ?? null,
        website_domain: item.website_domain ?? null,
        cache_expires_at: expiresAt
      }));
    const invalid = rows.filter((r)=>!r.code);
    if (invalid.length > 0) {
      return new Response(JSON.stringify({
        error: 'One or more items missing required field: code'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    // Perform insert to coupon_cache via PostgREST
    // Using the service role key so we can bypass RLS as needed.
    const url = `${SUPABASE_URL}/rest/v1/coupon_cache?on_conflict=website_domain,code`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Prefer': 'resolution=merge-duplicates'
      },
      body: JSON.stringify(rows)
    });
    if (!resp.ok) {
      const text = await resp.text();
      console.error('Insert failed', resp.status, text);
      return new Response(JSON.stringify({
        error: 'Database insert failed',
        status: resp.status,
        detail: text
      }), {
        status: 502,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    for (const row of rows){
      results.push({
        code: row.code,
        success: true
      });
    }
    return new Response(JSON.stringify({
      results
    }), {
      status: 201,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  } catch (err) {
    console.error('Unexpected error', err);
    return new Response(JSON.stringify({
      error: 'Internal server error',
      detail: String(err)
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
});
