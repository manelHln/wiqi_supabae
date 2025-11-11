// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { Mistral } from "npm:@mistralai/mistralai@1.10.0"
import { Perplexity } from "npm:@perplexity-ai/perplexity_ai@0.8.0"

const PERPLEXITY_API_KEY = Deno.env.get("PERPLEXITY_API_KEY")!
const MISTRAL_API_KEY = Deno.env.get("MISTRAL_API_KEY")!
const SUPABASE_URL = Deno.env.get("MY_SUPABASE_URL")!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("MY_SUPABASE_SERVICE_ROLE_KEY")!

// console.log(PERPLEXITY_API_KEY, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL)

// Shared types and constants
interface CouponCode {
  code: string
  discount: string
  description: string
  expiresIn: string
  verified: boolean
  restrictions?: string
  confidence_score: number
  source_url?: string
}

interface CouponSearchResponse {
  coupons: CouponCode[]
  search_summary?: string
}

// Shared system prompt generator
// 2. Visit major coupon aggregator sites and EXTRACT the actual codes
const createSystemPrompt = (
  domain: string
) => `You are a coupon code extraction expert and a web scraper.:
1. Scrap the web for current and active coupon codes for ${domain} valid for the USA
CRITICAL REQUIREMENTS:
- Search for any source where you might find the deals
- EXTRACT actual coupon codes from search results
- EXTRACT discount amounts from the text
- Use web_fetch to scrape coupon sites when codes are found in search
- Return ONLY codes that are currently active/verified
- Ignore if coupon code is Not explicitly given and you cannot scrap it`

// Shared JSON schema definition
const COUPON_SCHEMA = {
  type: "object" as const,
  properties: {
    coupons: {
      type: "array" as const,
      items: {
        type: "object" as const,
        properties: {
          code: {
            type: "string" as const,
            description: "The actual coupon code"
          },
          discount: {
            type: "string" as const,
            description: 'The discount amount'
          },
          description: {
            type: "string" as const,
            description: "Description of what the coupon is for"
          },
          expiresIn: {
            type: "string" as const,
            description: 'When it expires or "Unknown" if not specified'
          },
          verified: {
            type: "boolean" as const,
            description: "Whether the source claims it is verified/working"
          },
          restrictions: {
            type: "string" as const,
            description: 'Any restrictions mentioned like "Team plan only"'
          }
        },
        required: [
          "code",
          "discount",
          "description",
          "expiresIn",
          "verified",
        ],
        additionalProperties: false
      }
    }
  }
}

// Mistral
const mistralSearch = async (website_domain: string) => {
  const mistralClient = new Mistral({ apiKey: MISTRAL_API_KEY })

  const mistralChatResponse = await mistralClient.chat.complete({
    model: "mistral-large-2407",
    messages: [
      {
        role: "system",
        content: createSystemPrompt(website_domain)
      },
      {
        role: "user",
        content: `Make an exhaustive research to find discount codes for ${website_domain}`
      }
    ],
    maxTokens: 2000,
    temperature: 0,
    responseFormat: {
      type: "json_schema",
      jsonSchema: {
        name: "coupon_codes",
        schemaDefinition: COUPON_SCHEMA
      }
    }
  })

  return mistralChatResponse.choices[0].message.content
}

// Used by perplexity reasonning model since it adds the <think> block the the result
// function parseJsonAfterThink(content: string) {
//   const marker = "</think>"
//   const idx = content.lastIndexOf(marker)

//   if (idx === -1) {
//     // If marker not found, try parsing the entire content.
//     try {
//       return JSON.parse(content)
//     } catch (e) {
//       throw new Error(
//         "No </think> marker found and content is not valid JSON: " + e.message
//       )
//     }
//   }

//   // Extract the substring after the marker.
//   let jsonStr = content.slice(idx + marker.length).trim()

//   // Remove markdown code fence markers if present.
//   if (jsonStr.startsWith("```json")) {
//     jsonStr = jsonStr.slice(7).trim()
//   }
//   if (jsonStr.startsWith("```")) {
//     jsonStr = jsonStr.slice(3).trim()
//   }
//   if (jsonStr.endsWith("```")) {
//     jsonStr = jsonStr.slice(0, -3).trim()
//   }

//   try {
//     const parsedJson = JSON.parse(jsonStr)
//     return parsedJson
//   } catch (e) {
//     throw new Error(
//       "Failed to parse valid JSON from response content: " + e.message
//     )
//   }
// }

// Perplexity
const perplexitySearch = async (website_domain: string) => {
  const perplexity = new Perplexity({ apiKey: PERPLEXITY_API_KEY })

  const response = await perplexity.chat.completions.create({
    model: "sonar-pro",
    messages: [
      {
        role: "system",
        content: createSystemPrompt(website_domain)
      },
      {
        role: "user",
        content: `Provide an exhaustive research to find discount codes for ${website_domain}`
      }
    ],
    temperature: 0,
    max_tokens: 5000,
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "coupon_codes",
        strict: true,
        schema: {
          ...COUPON_SCHEMA,
          properties: {
            ...COUPON_SCHEMA.properties,
            search_summary: {
              type: "string" as const,
              description: "Brief summary of what you found in your search"
            }
          },
          required: ["coupons", "search_summary"],
          additionalProperties: false
        }
      }
    },
    web_search_options: {
      search_context_size: "low"
    }
  })

  return response.choices[0].message.content
}

const searchCoupons = async (
  website_domain: string,
  provider: "mistral" | "perplexity"
) => {
  if (provider === "mistral") {
    const result = await mistralSearch(website_domain)
    return result
  }

  if (provider === "perplexity") {
    return await perplexitySearch(website_domain)
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type"
}

interface CouponSearchRequest {
  website_domain: string
  website_name?: string
  from_cache?: boolean
  current_site?: string
}

interface Coupon {
  code: string
  discount: string
  description: string
  expiresIn?: string
  verified: boolean
  restrictions: string
  confidence_score: number
  source_url: string
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      throw new Error("Missing authorization header")
    }

    const token = authHeader.replace("Bearer ", "")
    const {
      data: { user },
      error: authError
    } = await supabase.auth.getUser(token)

    if (authError || !user) {
      throw new Error("Unauthorized")
    }

    const { website_domain, website_name, from_cache }: CouponSearchRequest =
      await req.json()

    if (!website_domain) {
      throw new Error("website_domain is required")
    }

    console.log(`Searching coupons for ${website_domain} (user: ${user.id}), ${from_cache}`)

    let coupons: Coupon[] = []
    if (from_cache) {
      const { data: cachedData, error: cacheError } = await supabase
        .from("coupon_cache")
        .select("*")
        .eq("website_domain", website_domain)
        .gt("cache_expires_at", new Date().toISOString())
        .order("confidence_score", { ascending: false })

      console.log("Using cached coupons")
      coupons = cachedData

      if (cacheError) {
        console.error("Quota check error:", cacheError)
        throw new Error("Failed to check quota")
      }

      return new Response(
        JSON.stringify({
          success: true,
          coupons,
          from_cache: false,
          website_domain,
          total_found: coupons.length
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200
        }
      )
    }

    // Check user quota
    const { data: quotaData, error: quotaError } = await supabase.rpc(
      "get_user_quota",
      {
        p_user_id: user.id
      }
    )

    if (quotaError) {
      console.error("Quota check error:", quotaError)
      throw new Error("Failed to check quota")
    }

    const quota = quotaData[0]
    if (!quota.can_search) {
      return new Response(
        JSON.stringify({
          error: "Quota exceeded",
          message:
            "You have reached your daily search limit. Upgrade to Pro for more searches!"
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 429
        }
      )
    }

    console.log("Calling AI API...", website_domain)
    const startTime = Date.now()

    try {
      const content = await searchCoupons(website_domain, 'mistral')
      // console.log(content)
      const result_json = JSON.parse(content)
      const { coupons: result_search_coupon } = result_json
      const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000)

      // Prepare all coupon records
      const couponRecords = Array.from(
        new Map(
          result_search_coupon.map((coupon) => {
            const key = `${website_domain}_${coupon.code}`
            return [
              key,
              {
                website_domain,
                code: coupon.code,
                discount: coupon.discount,
                description: coupon.description,
                expires_in: coupon.expiresIn,
                verified: coupon.verified,
                restrictions: coupon.restrictions,
                cache_expires_at: expiresAt.toISOString(),
                last_seen_at: new Date().toISOString()
              }
            ]
          })
        ).values()
      )

      const { data, error } = await supabase
        .from("coupon_cache")
        .upsert(couponRecords, {
          onConflict: "website_domain,code"
        })
        .select()

      if (error) {
        console.error("Failed to cache coupons:", error)
      }

      const searchDuration = Date.now() - startTime
      coupons = data

      console.log(`Found ${coupons.length} coupons`)

      // Log the search for analitycs
      await supabase.from("coupon_searches").insert({
        user_id: user.id,
        website_domain,
        website_name: website_name || website_domain,
        coupons_found: coupons.length,
        search_successful: coupons.length > 0,
        ai_model_used: "perplexity",
        search_duration_ms: searchDuration
      })

      // Update popular websites stats
      await supabase.rpc("update_popular_websites", {
        p_website_domain: website_domain,
        p_website_name: website_name || website_domain,
        p_coupons_found: coupons.length,
        p_was_successful: coupons.length > 0
      })
    } catch (perplexityError) {
      console.error("Perplexity SDK error:", perplexityError)
      throw new Error(
        `Perplexity API error: ${perplexityError.message || "Unknown error"}`
      )
    }

    const { error: incrementError } = await supabase.rpc(
      "increment_search_count",
      {
        p_user_id: user.id
      }
    )

    if (incrementError) {
      console.error("Failed to increment search count:", incrementError)
    }

    return new Response(
      JSON.stringify({
        success: true,
        coupons,
        from_cache: false,
        website_domain,
        total_found: coupons.length
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      }
    )
  } catch (error) {
    console.error("Error in search-coupons function:", error)

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        coupons: []
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500
      }
    )
  }
})
