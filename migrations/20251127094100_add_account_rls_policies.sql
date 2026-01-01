-- =====================================================
-- ROW LEVEL SECURITY POLICIES FOR ACCOUNT FEATURES
-- Date: 2025-11-27
-- Description: RLS policies for cashback, payments, reviews, support, and badges
-- =====================================================

-- =====================================================
-- CASHBACK EARNINGS RLS
-- =====================================================

ALTER TABLE public.cashback_earnings ENABLE ROW LEVEL SECURITY;

-- Users can view their own earnings
CREATE POLICY "Users can view own cashback earnings"
ON public.cashback_earnings
FOR SELECT
USING (auth.uid() = user_id);

-- Only system can insert earnings (via service role)
CREATE POLICY "Service role can insert cashback earnings"
ON public.cashback_earnings
FOR INSERT
WITH CHECK (auth.role() = 'service_role');

-- Only system can update earnings
CREATE POLICY "Service role can update cashback earnings"
ON public.cashback_earnings
FOR UPDATE
USING (auth.role() = 'service_role');

-- =====================================================
-- PAYMENT REQUESTS RLS
-- =====================================================

ALTER TABLE public.payment_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own payment requests
CREATE POLICY "Users can view own payment requests"
ON public.payment_requests
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own payment requests
CREATE POLICY "Users can create own payment requests"
ON public.payment_requests
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Only system can update payment requests
CREATE POLICY "Service role can update payment requests"
ON public.payment_requests
FOR UPDATE
USING (auth.role() = 'service_role');

-- =====================================================
-- MERCHANT REVIEWS RLS
-- =====================================================

ALTER TABLE public.merchant_reviews ENABLE ROW LEVEL SECURITY;

-- Users can view their own reviews
CREATE POLICY "Users can view own reviews"
ON public.merchant_reviews
FOR SELECT
USING (auth.uid() = user_id);

-- Users can view approved reviews from others
CREATE POLICY "Users can view approved reviews"
ON public.merchant_reviews
FOR SELECT
USING (status = 'approved');

-- Users can create their own reviews
CREATE POLICY "Users can create own reviews"
ON public.merchant_reviews
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Only system can update reviews (moderation)
CREATE POLICY "Service role can update reviews"
ON public.merchant_reviews
FOR UPDATE
USING (auth.role() = 'service_role');

-- =====================================================
-- SUPPORT TICKETS RLS
-- =====================================================

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Users can view their own tickets
CREATE POLICY "Users can view own support tickets"
ON public.support_tickets
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own tickets
CREATE POLICY "Users can create own support tickets"
ON public.support_tickets
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own tickets (limited fields)
CREATE POLICY "Users can update own support tickets"
ON public.support_tickets
FOR UPDATE
USING (auth.uid() = user_id);

-- =====================================================
-- SUPPORT TICKET RESPONSES RLS
-- =====================================================

ALTER TABLE public.support_ticket_responses ENABLE ROW LEVEL SECURITY;

-- Users can view responses to their tickets
CREATE POLICY "Users can view responses to own tickets"
ON public.support_ticket_responses
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.support_tickets
        WHERE id = ticket_id AND user_id = auth.uid()
    )
);

-- Users can create responses to their own tickets
CREATE POLICY "Users can create responses to own tickets"
ON public.support_ticket_responses
FOR INSERT
WITH CHECK (
    auth.uid() = user_id AND
    EXISTS (
        SELECT 1 FROM public.support_tickets
        WHERE id = ticket_id AND user_id = auth.uid()
    )
);

-- Staff can create responses (via service role)
CREATE POLICY "Service role can create staff responses"
ON public.support_ticket_responses
FOR INSERT
WITH CHECK (auth.role() = 'service_role');

-- =====================================================
-- USER BADGES RLS
-- =====================================================

ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;

-- Users can view their own badges
CREATE POLICY "Users can view own badges"
ON public.user_badges
FOR SELECT
USING (auth.uid() = user_id);

-- Users can view other users' badges (public)
CREATE POLICY "Users can view all badges"
ON public.user_badges
FOR SELECT
USING (true);

-- Only system can award badges
CREATE POLICY "Service role can insert badges"
ON public.user_badges
FOR INSERT
WITH CHECK (auth.role() = 'service_role');

-- =====================================================
-- USER TIERS RLS
-- =====================================================

ALTER TABLE public.user_tiers ENABLE ROW LEVEL SECURITY;

-- Users can view their own tier
CREATE POLICY "Users can view own tier"
ON public.user_tiers
FOR SELECT
USING (auth.uid() = user_id);

-- Users can view other users' tiers (public)
CREATE POLICY "Users can view all tiers"
ON public.user_tiers
FOR SELECT
USING (true);

-- Only system can update tiers
CREATE POLICY "Service role can manage tiers"
ON public.user_tiers
FOR ALL
USING (auth.role() = 'service_role');

-- =====================================================
-- FAQS RLS
-- =====================================================

ALTER TABLE public.faqs ENABLE ROW LEVEL SECURITY;

-- Everyone can view active FAQs
CREATE POLICY "Anyone can view active FAQs"
ON public.faqs
FOR SELECT
USING (is_active = true);

-- Only service role can manage FAQs
CREATE POLICY "Service role can manage FAQs"
ON public.faqs
FOR ALL
USING (auth.role() = 'service_role');

-- =====================================================
-- UPDATE EXISTING USERS TABLE RLS FOR NEW COLUMNS
-- =====================================================

-- Users can update their own extended profile fields
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;

CREATE POLICY "Users can update own profile"
ON public.users
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);
