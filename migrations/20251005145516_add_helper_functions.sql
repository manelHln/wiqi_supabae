CREATE OR REPLACE FUNCTION public.get_user_quota(p_user_id UUID)
RETURNS TABLE(
    total_quota INTEGER,
    used_quota INTEGER,
    bonus_searches INTEGER,
    can_search BOOLEAN
) AS $$
DECLARE
    v_plan_limit INTEGER;
    v_used_today INTEGER;
    v_bonus INTEGER;
BEGIN
    -- Get user's plan limit
    SELECT sp.daily_search_limit INTO v_plan_limit
    FROM public.user_subscriptions us
    JOIN public.subscription_plans sp ON us.plan_id = sp.id
    WHERE us.user_id = p_user_id 
    AND us.status = 'active'
    LIMIT 1;
    
    -- Get today's usage
    SELECT COALESCE(searches_used, 0) INTO v_used_today
    FROM public.search_quota_usage
    WHERE user_id = p_user_id AND date = CURRENT_DATE;
    
    -- If no record exists, create one
    IF v_used_today IS NULL THEN
        INSERT INTO public.search_quota_usage (user_id, date, searches_used, quota_limit)
        VALUES (p_user_id, CURRENT_DATE, 0, v_plan_limit);
        v_used_today := 0;
    END IF;
    
    -- Get available bonus searches
    SELECT COALESCE(SUM(amount - used_count), 0) INTO v_bonus
    FROM public.bonus_searches
    WHERE user_id = p_user_id 
    AND is_active = true 
    AND (expires_at IS NULL OR expires_at > NOW())
    AND used_count < amount;
    
    -- Return results
    RETURN QUERY SELECT 
        v_plan_limit,
        v_used_today,
        v_bonus,
        CASE 
            WHEN v_plan_limit = -1 THEN true  -- Unlimited
            WHEN v_bonus > 0 THEN true        -- Has bonus searches
            WHEN v_used_today < v_plan_limit THEN true  -- Has daily quota
            ELSE false
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.increment_search_count(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_quota_record RECORD;
    v_bonus_id UUID;
BEGIN
    -- Check if user can search
    SELECT * INTO v_quota_record FROM public.get_user_quota(p_user_id);
    
    IF NOT v_quota_record.can_search THEN
        RETURN false;
    END IF;
    
    -- Use bonus search first
    IF v_quota_record.bonus_searches > 0 THEN
        -- Find oldest active bonus search
        SELECT id INTO v_bonus_id
        FROM public.bonus_searches
        WHERE user_id = p_user_id 
        AND is_active = true 
        AND (expires_at IS NULL OR expires_at > NOW())
        AND used_count < amount
        ORDER BY created_at ASC
        LIMIT 1;
        
        -- Increment bonus usage
        UPDATE public.bonus_searches
        SET used_count = used_count + 1
        WHERE id = v_bonus_id;
        
        -- Mark as inactive if fully used
        UPDATE public.bonus_searches
        SET is_active = false
        WHERE id = v_bonus_id AND used_count >= amount;
    ELSE
        -- Use daily quota
        INSERT INTO public.search_quota_usage (user_id, date, searches_used, quota_limit)
        VALUES (p_user_id, CURRENT_DATE, 1, v_quota_record.total_quota)
        ON CONFLICT (user_id, date) 
        DO UPDATE SET 
            searches_used = public.search_quota_usage.searches_used + 1,
            updated_at = NOW();
    END IF;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.add_bonus_searches(
    p_user_id UUID,
    p_amount INTEGER,
    p_source TEXT,
    p_reason TEXT DEFAULT NULL,
    p_expires_days INTEGER DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_bonus_id UUID;
    v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Calculate expiration if provided
    IF p_expires_days IS NOT NULL THEN
        v_expires_at := NOW() + (p_expires_days || ' days')::INTERVAL;
    END IF;
    
    -- Insert bonus searches
    INSERT INTO public.bonus_searches (user_id, source, amount, reason, expires_at)
    VALUES (p_user_id, p_source, p_amount, p_reason, v_expires_at)
    RETURNING id INTO v_bonus_id;
    
    RETURN v_bonus_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.complete_referral(p_referred_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_referral_record RECORD;
BEGIN
    -- Find pending referral
    SELECT * INTO v_referral_record
    FROM public.referrals
    WHERE referred_user_id = p_referred_user_id 
    AND status = 'pending'
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    
    -- Mark referral as completed
    UPDATE public.referrals
    SET 
        status = 'completed',
        completed_at = NOW(),
        reward_claimed = true
    WHERE id = v_referral_record.id;
    
    -- Award bonus searches to referrer
    PERFORM public.add_bonus_searches(
        v_referral_record.referrer_id,
        v_referral_record.reward_amount,
        'referral',
        'Referral bonus for inviting ' || (SELECT email FROM public.users WHERE id = p_referred_user_id),
        90  -- Expires in 90 days
    );
    
    -- Update referral code stats
    UPDATE public.referral_codes
    SET 
        successful_referrals = successful_referrals + 1,
        bonus_searches_earned = bonus_searches_earned + v_referral_record.reward_amount
    WHERE user_id = v_referral_record.referrer_id;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.calculate_total_savings(p_user_id UUID)
RETURNS DECIMAL AS $$
DECLARE
    v_total_savings DECIMAL;
BEGIN
    SELECT COALESCE(SUM(discount_amount), 0) INTO v_total_savings
    FROM public.coupon_usage_events
    WHERE user_id = p_user_id 
    AND was_successful = true;
    
    -- Update user record
    UPDATE public.users
    SET total_savings = v_total_savings
    WHERE id = p_user_id;
    
    RETURN v_total_savings;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.get_user_dashboard_stats(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'total_savings', COALESCE(u.total_savings, 0),
        'searches_today', COALESCE(sq.searches_used, 0),
        'quota_limit', COALESCE(sq.quota_limit, 0),
        'bonus_searches', COALESCE(
            (SELECT SUM(amount - used_count) 
             FROM public.bonus_searches 
             WHERE user_id = p_user_id 
             AND is_active = true 
             AND (expires_at IS NULL OR expires_at > NOW())), 
            0
        ),
        'followed_websites', COALESCE(
            (SELECT COUNT(*) FROM public.followed_websites WHERE user_id = p_user_id AND is_active = true),
            0
        ),
        'unread_notifications', COALESCE(
            (SELECT COUNT(*) FROM public.notifications WHERE user_id = p_user_id AND is_read = false),
            0
        ),
        'subscription_tier', u.subscription_tier,
        'referral_code', rc.referral_code,
        'referrals_count', rc.successful_referrals
    ) INTO v_stats
    FROM public.users u
    LEFT JOIN public.search_quota_usage sq ON sq.user_id = u.id AND sq.date = CURRENT_DATE
    LEFT JOIN public.referral_codes rc ON rc.user_id = u.id
    WHERE u.id = p_user_id;
    
    RETURN v_stats;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.cleanup_expired_cache()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM public.coupon_cache
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- =====================================================
-- Function to update popular websites stats
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_popular_websites(
    p_website_domain TEXT,
    p_website_name TEXT,
    p_coupons_found INTEGER,
    p_was_successful BOOLEAN
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.popular_websites (
        website_domain, 
        website_name, 
        total_searches, 
        successful_searches,
        avg_coupons_found,
        last_search_at
    )
    VALUES (
        p_website_domain,
        p_website_name,
        1,
        CASE WHEN p_was_successful THEN 1 ELSE 0 END,
        p_coupons_found,
        NOW()
    )
    ON CONFLICT (website_domain) DO UPDATE SET
        total_searches = public.popular_websites.total_searches + 1,
        successful_searches = public.popular_websites.successful_searches + 
            CASE WHEN p_was_successful THEN 1 ELSE 0 END,
        avg_coupons_found = (
            (public.popular_websites.avg_coupons_found * public.popular_websites.total_searches + p_coupons_found) / 
            (public.popular_websites.total_searches + 1)
        ),
        last_search_at = NOW(),
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';