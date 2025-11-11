-- =====================================================
-- Insert Subscription Plans
-- =====================================================
INSERT INTO public.subscription_plans (name, slug, daily_search_limit, monthly_search_limit, price_monthly, price_yearly, features) VALUES
(
    'Free', 
    'free', 
    5, 
    150, 
    0, 
    0, 
    '[
        "5 coupon searches per day",
        "2 followed websites",
        "Basic notifications",
        "Community support"
    ]'::jsonb
),
(
    'Pro', 
    'pro', 
    50, 
    1500, 
    9.99, 
    99.00, 
    '[
        "50 searches per day",
        "10 followed websites",
        "Priority support",
        "Price drop alerts",
        "Advanced notifications",
        "Search history (30 days)"
    ]'::jsonb
),
(
    'Premium', 
    'premium', 
    -1, 
    -1, 
    19.99, 
    199.00, 
    '[
        "Unlimited searches",
        "Unlimited followed websites",
        "Auto-apply best coupons",
        "Advanced analytics dashboard",
        "API access",
        "Priority AI processing",
        "VIP support",
        "Search history (unlimited)",
        "Custom alerts"
    ]'::jsonb
);

INSERT INTO public.popular_websites (website_domain, website_name, total_searches, successful_searches, avg_coupons_found, ranking) VALUES
('amazon.fr', 'Amazon France', 0, 0, 0, 1),
('amazon.com', 'Amazon', 0, 0, 0, 2),
('ebay.fr', 'eBay France', 0, 0, 0, 3),
('cdiscount.com', 'CDiscount', 0, 0, 0, 4),
('fnac.com', 'Fnac', 0, 0, 0, 5),
('darty.com', 'Darty', 0, 0, 0, 6),
('aliexpress.com', 'AliExpress', 0, 0, 0, 7),
('zalando.fr', 'Zalando', 0, 0, 0, 8),
('asos.com', 'ASOS', 0, 0, 0, 9),
('shein.com', 'SHEIN', 0, 0, 0, 10);