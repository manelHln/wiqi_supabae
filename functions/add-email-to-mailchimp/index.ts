import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import mailchimp from "npm:@mailchimp/mailchimp_marketing@^3.0.80"

const MAILCHIMP_API_KEY = Deno.env.get('MAILCHIMP_API_KEY')!
const MAILCHIMP_SERVER_PREFIX = Deno.env.get('MAILCHIMP_SERVER_PREFIX')!
const MAILCHIMP_AUDIENCE_ID = Deno.env.get('MAILCHIMP_AUDIENCE_ID')!
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-webhook-secret',
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  record: {
    id: string
    email: string
    fullName?: string
  }
  schema: string
  old_record: null | any
}

mailchimp.setConfig({
  apiKey: MAILCHIMP_API_KEY,
  server: MAILCHIMP_SERVER_PREFIX,
})

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  const webhookSecret = req.headers.get('x-webhook-secret')
  if (webhookSecret !== WEBHOOK_SECRET) {
    console.error('Invalid webhook secret')
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401 
      }
    )
  }

  try {
    const payload: WebhookPayload = await req.json()
    
    console.log('Received webhook payload:', JSON.stringify(payload, null, 2))

    // Only process INSERT events for the users table
    if (payload.type !== 'INSERT' || payload.table !== 'users') {
      return new Response(
        JSON.stringify({ message: 'Event ignored' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200 
        }
      )
    }

    const { email, fullName } = payload.record

    if (!email) {
      throw new Error('Email is required')
    }

    try {
      const response = await mailchimp.lists.addListMember(MAILCHIMP_AUDIENCE_ID, {
        email_address: email,
        status: 'subscribed',
        merge_fields: {
          FNAME: fullName || '',
        },
        tags: ['SaverPro', 'Extension User'],
      })

      console.log('Successfully added to Mailchimp:', response.id)

      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'User added to Mailchimp successfully',
          mailchimp_id: response.id 
        }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200 
        }
      )

    } catch (mailchimpError) {
      if (mailchimpError.status === 400 && mailchimpError.title === 'Member Exists') {
        console.log('User already exists in Mailchimp:', email, mailchimpError)
        return new Response(
          JSON.stringify({ 
            success: true, 
            message: 'User already exists in Mailchimp',
            mailchimp_id: mailchimpError.response?.body?.id 
          }),
          { 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200 
          }
        )
      }

      console.error('Mailchimp SDK error:', mailchimpError)
      throw new Error(`Mailchimp API error: ${mailchimpError.detail || mailchimpError.title || mailchimpError.message}`)
    }

  } catch (error) {
    console.error('Error in add-to-mailchimp function:', error)
    
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    )
  }
})