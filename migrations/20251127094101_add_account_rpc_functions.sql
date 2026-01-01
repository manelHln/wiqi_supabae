-- =====================================================
-- RPC FUNCTIONS FOR ACCOUNT FEATURES
-- Date: 2025-11-22
-- Description: Helper functions for cashback, payments, reviews, and support
-- =====================================================

-- =====================================================
-- PROFILE MANAGEMENT FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.update_user_profile(
    p_user_id UUID,
    p_first_name TEXT DEFAULT NULL,
    p_last_name TEXT DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_birthdate DATE DEFAULT NULL,
    p_phone_number TEXT DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    UPDATE public.users
    SET 
        first_name = COALESCE(p_first_name, first_name),
        last_name = COALESCE(p_last_name, last_name),
        avatar_url = COALESCE(p_avatar_url, avatar_url),
        address = COALESCE(p_address, address),
        birthdate = COALESCE(p_birthdate, birthdate),
        phone_number = COALESCE(p_phone_number, phone_number),
        updated_at = NOW()
    WHERE id = p_user_id;
    
    RETURN json_build_object('success', true, 'message', 'Profile updated successfully');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.update_user_profile IS 'Updates user profile information';

-- =====================================================
-- EARNINGS FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_user_earnings(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
    v_available DECIMAL;
    v_pending DECIMAL;
    v_confirmed DECIMAL;
    v_total_earned DECIMAL;
    v_total_paid DECIMAL;
BEGIN
    SELECT 
        COALESCE(SUM(CASE WHEN status = 'available' THEN cashback_amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status = 'pending' THEN cashback_amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status = 'confirmed' THEN cashback_amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status IN ('available', 'paid') THEN cashback_amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status = 'paid' THEN cashback_amount ELSE 0 END), 0)
    INTO v_available, v_pending, v_confirmed, v_total_earned, v_total_paid
    FROM public.cashback_earnings
    WHERE user_id = p_user_id;
    
    RETURN json_build_object(
        'available', v_available,
        'pending', v_pending,
        'confirmed', v_confirmed,
        'total_earned', v_total_earned,
        'total_paid', v_total_paid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.get_user_earnings IS 'Returns user cashback earnings summary';

-- =====================================================
-- PAYMENT REQUEST FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_payment_request(
    p_user_id UUID,
    p_amount DECIMAL,
    p_payment_method TEXT,
    p_payment_details JSONB
)
RETURNS JSON AS $$
DECLARE
    v_available DECIMAL;
    v_request_id UUID;
BEGIN
    -- Check available balance
    SELECT COALESCE(SUM(cashback_amount), 0) INTO v_available
    FROM public.cashback_earnings
    WHERE user_id = p_user_id AND status = 'available';
    
    -- Validate minimum amount
    IF p_amount < 20 THEN
        RETURN json_build_object(
            'success', false, 
            'error', 'Minimum withdrawal amount is $20'
        );
    END IF;
    
    -- Validate sufficient balance
    IF v_available < p_amount THEN
        RETURN json_build_object(
            'success', false, 
            'error', 'Insufficient available balance',
            'available', v_available
        );
    END IF;
    
    -- Validate payment method
    IF p_payment_method NOT IN ('bank_transfer', 'paypal', 'gift_voucher') THEN
        RETURN json_build_object(
            'success', false, 
            'error', 'Invalid payment method'
        );
    END IF;
    
    -- Create payment request
    INSERT INTO public.payment_requests (user_id, amount, payment_method, payment_details)
    VALUES (p_user_id, p_amount, p_payment_method, p_payment_details)
    RETURNING id INTO v_request_id;
    
    RETURN json_build_object(
        'success', true, 
        'request_id', v_request_id,
        'message', 'Payment request created successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.create_payment_request IS 'Creates a new payment withdrawal request';

-- =====================================================
-- REFERRAL FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_user_referrals(p_user_id UUID)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_build_object(
            'referral_code', COALESCE(rc.referral_code, ''),
            'total_referrals', COALESCE(rc.total_referrals, 0),
            'successful_referrals', COALESCE(rc.successful_referrals, 0),
            'bonus_earned', COALESCE(rc.bonus_searches_earned, 0),
            'referrals', COALESCE((
                SELECT json_agg(json_build_object(
                    'id', r.id,
                    'user_email', u.email,
                    'user_name', u.full_name,
                    'status', r.status,
                    'reward_amount', r.reward_amount,
                    'reward_claimed', r.reward_claimed,
                    'created_at', r.created_at,
                    'completed_at', r.completed_at
                ) ORDER BY r.created_at DESC)
                FROM public.referrals r
                JOIN public.users u ON u.id = r.referred_user_id
                WHERE r.referrer_id = p_user_id
            ), '[]'::json)
        )
        FROM public.referral_codes rc
        WHERE rc.user_id = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.get_user_referrals IS 'Returns user referral information and list';

-- =====================================================
-- REVIEW FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.submit_merchant_review(
    p_user_id UUID,
    p_merchant_domain TEXT,
    p_merchant_name TEXT,
    p_rating INTEGER,
    p_review_text TEXT
)
RETURNS JSON AS $$
DECLARE
    v_review_id UUID;
    v_existing_review UUID;
BEGIN
    -- Check if user already reviewed this merchant
    SELECT id INTO v_existing_review
    FROM public.merchant_reviews
    WHERE user_id = p_user_id AND merchant_domain = p_merchant_domain;
    
    IF v_existing_review IS NOT NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'You have already submitted a review for this merchant'
        );
    END IF;
    
    -- Validate rating
    IF p_rating < 1 OR p_rating > 5 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Rating must be between 1 and 5'
        );
    END IF;
    
    -- Create review
    INSERT INTO public.merchant_reviews (
        user_id, 
        merchant_domain, 
        merchant_name, 
        rating, 
        review_text
    )
    VALUES (p_user_id, p_merchant_domain, p_merchant_name, p_rating, p_review_text)
    RETURNING id INTO v_review_id;
    
    RETURN json_build_object(
        'success', true,
        'review_id', v_review_id,
        'message', 'Review submitted for moderation'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.submit_merchant_review IS 'Submits a merchant review for moderation';

-- =====================================================
-- SUPPORT TICKET FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_support_ticket(
    p_user_id UUID,
    p_subject TEXT,
    p_category TEXT,
    p_message TEXT
)
RETURNS JSON AS $$
DECLARE
    v_ticket_id UUID;
BEGIN
    -- Validate category
    IF p_category NOT IN ('cashback', 'payment', 'technical', 'account', 'other') THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid ticket category'
        );
    END IF;
    
    -- Create ticket
    INSERT INTO public.support_tickets (user_id, subject, category, message)
    VALUES (p_user_id, p_subject, p_category, p_message)
    RETURNING id INTO v_ticket_id;
    
    RETURN json_build_object(
        'success', true,
        'ticket_id', v_ticket_id,
        'message', 'Support ticket created successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.create_support_ticket IS 'Creates a new support ticket';

CREATE OR REPLACE FUNCTION public.add_ticket_response(
    p_ticket_id UUID,
    p_user_id UUID,
    p_message TEXT,
    p_is_staff BOOLEAN DEFAULT false
)
RETURNS JSON AS $$
DECLARE
    v_response_id UUID;
BEGIN
    -- Add response
    INSERT INTO public.support_ticket_responses (ticket_id, user_id, message, is_staff)
    VALUES (p_ticket_id, p_user_id, p_message, p_is_staff)
    RETURNING id INTO v_response_id;
    
    -- Update ticket status if customer response
    IF NOT p_is_staff THEN
        UPDATE public.support_tickets
        SET updated_at = NOW()
        WHERE id = p_ticket_id;
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'response_id', v_response_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.add_ticket_response IS 'Adds a response to a support ticket';

-- =====================================================
-- BADGE FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.award_badge(
    p_user_id UUID,
    p_badge_type TEXT,
    p_badge_level INTEGER,
    p_badge_name TEXT,
    p_badge_description TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_badge_id UUID;
BEGIN
    -- Insert badge (will fail if already exists due to unique constraint)
    INSERT INTO public.user_badges (user_id, badge_type, badge_level, badge_name, badge_description)
    VALUES (p_user_id, p_badge_type, p_badge_level, p_badge_name, p_badge_description)
    ON CONFLICT (user_id, badge_type, badge_level) DO NOTHING
    RETURNING id INTO v_badge_id;
    
    IF v_badge_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Badge already earned'
        );
    END IF;
    
    -- Create notification
    INSERT INTO public.notifications (user_id, type, title, message)
    VALUES (
        p_user_id,
        'savings_milestone',
        'New Badge Earned!',
        'Congratulations! You earned the ' || p_badge_name || ' badge.'
    );
    
    RETURN json_build_object(
        'success', true,
        'badge_id', v_badge_id,
        'message', 'Badge awarded successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.award_badge IS 'Awards a badge to a user';

-- =====================================================
-- TIER MANAGEMENT FUNCTIONS
-- =====================================================

CREATE OR REPLACE FUNCTION public.update_user_tier(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
    v_total_points INTEGER;
    v_new_tier TEXT;
    v_current_tier TEXT;
BEGIN
    -- Calculate points based on various activities
    SELECT 
        COALESCE(COUNT(DISTINCT ce.id) * 10, 0) + -- 10 points per purchase
        COALESCE(COUNT(DISTINCT ub.id) * 50, 0) + -- 50 points per badge
        COALESCE(COUNT(DISTINCT r.id) * 100, 0) + -- 100 points per referral
        COALESCE(COUNT(DISTINCT mr.id) * 20, 0)   -- 20 points per review
    INTO v_total_points
    FROM public.users u
    LEFT JOIN public.cashback_earnings ce ON ce.user_id = u.id AND ce.status IN ('available', 'paid')
    LEFT JOIN public.user_badges ub ON ub.user_id = u.id
    LEFT JOIN public.referrals r ON r.referrer_id = u.id AND r.status = 'completed'
    LEFT JOIN public.merchant_reviews mr ON mr.user_id = u.id AND mr.status = 'approved'
    WHERE u.id = p_user_id;
    
    -- Determine tier based on points
    IF v_total_points >= 1000 THEN
        v_new_tier := 'platinum';
    ELSIF v_total_points >= 500 THEN
        v_new_tier := 'gold';
    ELSIF v_total_points >= 200 THEN
        v_new_tier := 'silver';
    ELSIF v_total_points >= 50 THEN
        v_new_tier := 'bronze';
    ELSE
        v_new_tier := 'beginner';
    END IF;
    
    -- Get current tier
    SELECT current_tier INTO v_current_tier
    FROM public.user_tiers
    WHERE user_id = p_user_id;
    
    -- Insert or update tier
    INSERT INTO public.user_tiers (user_id, current_tier, points)
    VALUES (p_user_id, v_new_tier, v_total_points)
    ON CONFLICT (user_id) DO UPDATE SET
        current_tier = v_new_tier,
        points = v_total_points,
        tier_updated_at = NOW();
    
    -- Create notification if tier changed
    IF v_current_tier IS NOT NULL AND v_current_tier != v_new_tier THEN
        INSERT INTO public.notifications (user_id, type, title, message)
        VALUES (
            p_user_id,
            'savings_milestone',
            'Tier Upgraded!',
            'Congratulations! You have reached ' || UPPER(v_new_tier) || ' tier.'
        );
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'tier', v_new_tier,
        'points', v_total_points
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.update_user_tier IS 'Calculates and updates user tier based on activity';
