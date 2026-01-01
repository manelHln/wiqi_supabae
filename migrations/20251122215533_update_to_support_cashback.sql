-- =====================================================
-- MIGRATION: Add Cashback & Account Features Support
-- Date: 2025-11-22
-- Description: Adds tables for cashback earnings, payments, reviews, support, and badges
-- =====================================================

-- =====================================================
-- EXTEND USERS TABLE
-- =====================================================
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS address TEXT,
ADD COLUMN IF NOT EXISTS birthdate DATE,
ADD COLUMN IF NOT EXISTS phone_number TEXT,
ADD COLUMN IF NOT EXISTS first_name TEXT,
ADD COLUMN IF NOT EXISTS last_name TEXT;

COMMENT ON COLUMN public.users.address IS 'User physical address';
COMMENT ON COLUMN public.users.birthdate IS 'User date of birth';
COMMENT ON COLUMN public.users.phone_number IS 'User phone number';

-- =====================================================
-- CASHBACK EARNINGS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.cashback_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    merchant_name TEXT NOT NULL,
    merchant_domain TEXT NOT NULL,
    order_id TEXT,
    order_amount DECIMAL(10, 2) NOT NULL,
    cashback_amount DECIMAL(10, 2) NOT NULL,
    cashback_percentage DECIMAL(5, 2),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'available', 'paid', 'rejected')),
    purchase_date TIMESTAMP WITH TIME ZONE NOT NULL,
    confirmation_date TIMESTAMP WITH TIME ZONE,
    available_date TIMESTAMP WITH TIME ZONE,
    payment_date TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cashback_earnings_user_id ON public.cashback_earnings(user_id);
CREATE INDEX IF NOT EXISTS idx_cashback_earnings_status ON public.cashback_earnings(status);
CREATE INDEX IF NOT EXISTS idx_cashback_earnings_purchase_date ON public.cashback_earnings(purchase_date DESC);

COMMENT ON TABLE public.cashback_earnings IS 'Tracks user cashback earnings from purchases';
COMMENT ON COLUMN public.cashback_earnings.status IS 'pending: awaiting merchant confirmation, confirmed: merchant confirmed, available: ready to withdraw, paid: already paid out, rejected: merchant rejected';

-- =====================================================
-- PAYMENT REQUESTS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.payment_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 20),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('bank_transfer', 'paypal', 'gift_voucher')),
    payment_details JSONB,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    transaction_id TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_requests_user_id ON public.payment_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_status ON public.payment_requests(status);
CREATE INDEX IF NOT EXISTS idx_payment_requests_requested_at ON public.payment_requests(requested_at DESC);

COMMENT ON TABLE public.payment_requests IS 'User cashback withdrawal requests';
COMMENT ON COLUMN public.payment_requests.amount IS 'Amount to withdraw (minimum $20)';
COMMENT ON COLUMN public.payment_requests.payment_details IS 'JSON containing bank account, PayPal email, etc.';

-- =====================================================
-- MERCHANT REVIEWS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.merchant_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    merchant_domain TEXT NOT NULL,
    merchant_name TEXT NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT NOT NULL,
    purchase_verified BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reward_amount DECIMAL(10, 2) DEFAULT 0.20,
    reward_paid BOOLEAN DEFAULT false,
    moderation_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    rejected_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, merchant_domain)
);

CREATE INDEX IF NOT EXISTS idx_merchant_reviews_user_id ON public.merchant_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_merchant_reviews_merchant_domain ON public.merchant_reviews(merchant_domain);
CREATE INDEX IF NOT EXISTS idx_merchant_reviews_status ON public.merchant_reviews(status);

COMMENT ON TABLE public.merchant_reviews IS 'User reviews of merchants with reward system';
COMMENT ON COLUMN public.merchant_reviews.reward_amount IS 'Cashback reward for approved review (default $0.20)';

-- =====================================================
-- SUPPORT TICKETS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    category TEXT CHECK (category IN ('cashback', 'payment', 'technical', 'account', 'other')),
    message TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'closed')),
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    assigned_to UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id ON public.support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at ON public.support_tickets(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_to ON public.support_tickets(assigned_to);

COMMENT ON TABLE public.support_tickets IS 'Customer support ticket system';

-- =====================================================
-- SUPPORT TICKET RESPONSES TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.support_ticket_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    is_staff BOOLEAN DEFAULT false,
    message TEXT NOT NULL,
    attachments JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_responses_ticket_id ON public.support_ticket_responses(ticket_id);
CREATE INDEX IF NOT EXISTS idx_support_ticket_responses_created_at ON public.support_ticket_responses(created_at ASC);

COMMENT ON TABLE public.support_ticket_responses IS 'Responses to support tickets from users and staff';

-- =====================================================
-- USER BADGES TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.user_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    badge_type TEXT NOT NULL CHECK (badge_type IN ('profile', 'purchases', 'earnings', 'referral', 'reviews', 'extension', 'seniority')),
    badge_level INTEGER NOT NULL CHECK (badge_level >= 1 AND badge_level <= 5),
    badge_name TEXT NOT NULL,
    badge_description TEXT,
    earned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, badge_type, badge_level)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user_id ON public.user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_badge_type ON public.user_badges(badge_type);

COMMENT ON TABLE public.user_badges IS 'User achievement badges';

-- =====================================================
-- USER TIERS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.user_tiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    current_tier TEXT DEFAULT 'beginner' CHECK (current_tier IN ('beginner', 'bronze', 'silver', 'gold', 'platinum')),
    points INTEGER DEFAULT 0,
    tier_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_tiers_current_tier ON public.user_tiers(current_tier);

COMMENT ON TABLE public.user_tiers IS 'User tier/status progression system';

-- =====================================================
-- FAQS TABLE (Optional - for dynamic FAQ management)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.faqs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_faqs_category ON public.faqs(category);
CREATE INDEX IF NOT EXISTS idx_faqs_is_active ON public.faqs(is_active);

COMMENT ON TABLE public.faqs IS 'Frequently asked questions content management';
