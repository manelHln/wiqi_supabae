-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- USERS TABLE
-- =====================================================
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    subscription_tier TEXT DEFAULT 'free' CHECK (subscription_tier IN ('free', 'pro', 'premium')),
    total_savings DECIMAL(10, 2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.users IS 'Extended user profiles linked to Supabase auth';


CREATE TABLE public.subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    daily_search_limit INTEGER NOT NULL,
    monthly_search_limit INTEGER,
    price_monthly DECIMAL(10, 2) NOT NULL,
    price_yearly DECIMAL(10, 2),
    features JSONB DEFAULT '[]'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.subscription_plans IS 'Available subscription tiers and their limits';


CREATE TABLE public.user_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES public.subscription_plans(id),
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'expired', 'trial')),
    current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    current_period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    cancel_at_period_end BOOLEAN DEFAULT false,
    stripe_subscription_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.user_subscriptions IS 'Active user subscriptions';


CREATE TABLE public.user_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    notifications_enabled BOOLEAN DEFAULT true,
    email_notifications BOOLEAN DEFAULT true,
    price_drop_alerts BOOLEAN DEFAULT true,
    quota_warning_alerts BOOLEAN DEFAULT true,
    language TEXT DEFAULT 'fr',
    currency TEXT DEFAULT 'EUR',
    auto_apply_coupons BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.coupon_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    website_domain TEXT NOT NULL,
    website_name TEXT NOT NULL,
    search_query TEXT,
    coupons_found INTEGER DEFAULT 0,
    search_successful BOOLEAN DEFAULT false,
    ai_model_used TEXT,
    search_duration_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.coupon_searches IS 'History of all coupon searches performed';

CREATE TABLE public.search_quota_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    searches_used INTEGER DEFAULT 0,
    quota_limit INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, date)
);

COMMENT ON TABLE public.search_quota_usage IS 'Daily search quota tracking per user';

CREATE TABLE public.coupon_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    website_domain TEXT NOT NULL,
    code VARCHAR(100) NOT NULL,
    discount VARCHAR(50),
    description TEXT,
    expires_in TEXT,
    verified BOOLEAN DEFAULT true,
    restrictions TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Updated when AI finds it again
    cache_expires_at TIMESTAMP WITH TIME ZONE NOT NULL, -- 24hrs from creation
    
    UNIQUE(website_domain, code)
);

COMMENT ON TABLE public.coupon_cache IS 'Temporary cache of AI-generated coupons (6 hour TTL)';

CREATE TABLE public.followed_websites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    website_name TEXT NOT NULL,
    website_url TEXT NOT NULL,
    website_favicon TEXT,
    last_searched_at TIMESTAMP WITH TIME ZONE,
    coupon_count_last_search INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.followed_websites IS 'Websites users are following for deals';

CREATE TABLE public.price_trackers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    product_url TEXT NOT NULL,
    product_name TEXT NOT NULL,
    website_domain TEXT NOT NULL,
    current_price DECIMAL(10, 2) NOT NULL,
    target_price DECIMAL(10, 2),
    original_price DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'EUR',
    last_price_check TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    price_drop_detected BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.price_trackers IS 'Products being tracked for price drops';

CREATE TABLE public.price_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price_tracker_id UUID NOT NULL REFERENCES public.price_trackers(id) ON DELETE CASCADE,
    price DECIMAL(10, 2) NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('price_drop', 'quota_limit', 'subscription_expiry', 'coupon_found', 'savings_milestone')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    related_id UUID,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.referral_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referral_code TEXT UNIQUE NOT NULL,
    total_referrals INTEGER DEFAULT 0,
    successful_referrals INTEGER DEFAULT 0,
    bonus_searches_earned INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.referral_codes IS 'User referral codes for inviting friends';

CREATE TABLE public.referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referred_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referral_code TEXT NOT NULL REFERENCES public.referral_codes(referral_code),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
    reward_type TEXT DEFAULT 'bonus_searches' CHECK (reward_type IN ('bonus_searches', 'discount', 'free_month')),
    reward_amount INTEGER NOT NULL,
    reward_claimed BOOLEAN DEFAULT false,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.bonus_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK (source IN ('referral', 'promotion', 'reward', 'admin')),
    amount INTEGER NOT NULL,
    reason TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    used_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE public.bonus_searches IS 'Extra searches earned through referrals/promotions';

CREATE TABLE public.user_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    searches_performed INTEGER DEFAULT 0,
    coupons_found INTEGER DEFAULT 0,
    coupons_used INTEGER DEFAULT 0,
    estimated_savings DECIMAL(10, 2) DEFAULT 0,
    price_checks INTEGER DEFAULT 0,
    price_drops_detected INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, date)
);

CREATE TABLE public.platform_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE UNIQUE NOT NULL,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    new_signups INTEGER DEFAULT 0,
    total_searches INTEGER DEFAULT 0,
    total_coupons_found INTEGER DEFAULT 0,
    total_savings DECIMAL(10, 2) DEFAULT 0,
    premium_conversions INTEGER DEFAULT 0,
    ai_api_cost DECIMAL(10, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.coupon_usage_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    search_id UUID REFERENCES public.coupon_searches(id) ON DELETE SET NULL,
    website_domain TEXT NOT NULL,
    coupon_code TEXT NOT NULL,
    discount_amount DECIMAL(10, 2),
    was_successful BOOLEAN NOT NULL,
    user_feedback TEXT CHECK (user_feedback IN ('worked', 'expired', 'invalid', 'limited')),
    used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE public.popular_websites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    website_domain TEXT UNIQUE NOT NULL,
    website_name TEXT NOT NULL,
    total_searches INTEGER DEFAULT 0,
    successful_searches INTEGER DEFAULT 0,
    avg_coupons_found DECIMAL(5, 2) DEFAULT 0,
    last_search_at TIMESTAMP WITH TIME ZONE,
    ranking INTEGER,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);