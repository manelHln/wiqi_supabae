-- =====================================================
-- Enable RLS on all tables
-- =====================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_quota_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.followed_websites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_trackers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bonus_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.popular_websites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_cache ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- Public read-only tables
-- =====================================================

-- Subscription plans are viewable by everyone
CREATE POLICY "Subscription plans are viewable by everyone" 
    ON public.subscription_plans
    FOR SELECT 
    USING (true);

-- Popular websites are viewable by everyone
CREATE POLICY "Popular websites are viewable by everyone" 
    ON public.popular_websites
    FOR SELECT 
    USING (true);

-- Coupon cache is viewable by everyone
CREATE POLICY "Coupon cache is viewable by everyone" 
    ON public.coupon_cache
    FOR SELECT 
    USING (true);

CREATE POLICY "Users can view own profile" 
    ON public.users
    FOR SELECT 
    USING ((SELECT auth.uid()) = id);

CREATE POLICY "Users can update own profile" 
    ON public.users
    FOR UPDATE 
    USING ((SELECT auth.uid()) = id);


CREATE POLICY "Users can view own subscription" 
    ON public.user_subscriptions
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update own subscription" 
    ON public.user_subscriptions
    FOR UPDATE 
    USING ((SELECT auth.uid()) = user_id);


CREATE POLICY "Users can view own searches" 
    ON public.coupon_searches
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert own searches" 
    ON public.coupon_searches
    FOR INSERT 
    WITH CHECK ((SELECT auth.uid()) = user_id);


CREATE POLICY "Users can manage own quota" 
    ON public.search_quota_usage
    FOR ALL 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can manage own followed websites" 
    ON public.followed_websites
    FOR ALL 
    USING ((SELECT auth.uid()) = user_id);


CREATE POLICY "Users can manage own price trackers" 
    ON public.price_trackers
    FOR ALL 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can view own price history" 
    ON public.price_history
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.price_trackers 
            WHERE price_trackers.id = price_history.price_tracker_id 
            AND price_trackers.user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Users can view own notifications" 
    ON public.notifications
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update own notifications" 
    ON public.notifications
    FOR UPDATE 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can delete own notifications" 
    ON public.notifications
    FOR DELETE 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can manage own settings" 
    ON public.user_settings
    FOR ALL 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update own referral code" 
    ON public.referral_codes
    FOR UPDATE 
    USING ((SELECT auth.uid()) = user_id);

-- Anyone can view referral codes (for validation)
CREATE POLICY "Anyone can view referral codes for validation" 
    ON public.referral_codes
    FOR SELECT 
    USING (true);

CREATE POLICY "Users can view own referrals" 
    ON public.referrals
    FOR SELECT 
    USING ((SELECT auth.uid()) = referrer_id OR (SELECT auth.uid()) = referred_user_id);

CREATE POLICY "Users can insert referrals" 
    ON public.referrals
    FOR INSERT 
    WITH CHECK ((SELECT auth.uid()) = referred_user_id);

CREATE POLICY "Users can view own bonus searches" 
    ON public.bonus_searches
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can view own analytics" 
    ON public.user_analytics
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can view own coupon usage" 
    ON public.coupon_usage_events
    FOR SELECT 
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert own coupon usage" 
    ON public.coupon_usage_events
    FOR INSERT 
    WITH CHECK ((SELECT auth.uid()) = user_id);