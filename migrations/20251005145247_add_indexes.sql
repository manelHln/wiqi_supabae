-- Coupon Searches
CREATE INDEX idx_coupon_searches_user_id ON public.coupon_searches(user_id);
CREATE INDEX idx_coupon_searches_created_at ON public.coupon_searches(created_at);
CREATE INDEX idx_coupon_searches_website ON public.coupon_searches(website_domain);

-- Search Quota Usage
CREATE INDEX idx_search_quota_user_date ON public.search_quota_usage(user_id, date);

-- Coupon Cache
CREATE INDEX idx_domain_active ON coupon_cache(website_domain, cache_expires_at);

-- Followed Websites
CREATE INDEX idx_followed_websites_user_id ON public.followed_websites(user_id);
CREATE INDEX idx_followed_websites_active ON public.followed_websites(user_id, is_active) WHERE is_active = true;

-- Price Trackers
CREATE INDEX idx_price_trackers_user_id ON public.price_trackers(user_id);
CREATE INDEX idx_price_trackers_active ON public.price_trackers(is_active) WHERE is_active = true;
CREATE INDEX idx_price_trackers_domain ON public.price_trackers(website_domain);

-- Price History
CREATE INDEX idx_price_history_tracker_id ON public.price_history(price_tracker_id);
CREATE INDEX idx_price_history_recorded_at ON public.price_history(recorded_at);

-- Notifications
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_unread ON public.notifications(user_id, is_read) WHERE is_read = false;
CREATE INDEX idx_notifications_created_at ON public.notifications(created_at DESC);

-- Referral Codes
CREATE INDEX idx_referral_codes_code ON public.referral_codes(referral_code);
CREATE INDEX idx_referral_codes_user_id ON public.referral_codes(user_id);

-- Referrals
CREATE INDEX idx_referrals_referrer_id ON public.referrals(referrer_id);
CREATE INDEX idx_referrals_referred_user_id ON public.referrals(referred_user_id);
CREATE INDEX idx_referrals_status ON public.referrals(status);

-- Bonus Searches
CREATE INDEX idx_bonus_searches_user_id ON public.bonus_searches(user_id);
CREATE INDEX idx_bonus_searches_active ON public.bonus_searches(user_id, is_active) WHERE is_active = true;

-- User Analytics
CREATE INDEX idx_user_analytics_user_date ON public.user_analytics(user_id, date);
CREATE INDEX idx_user_analytics_date ON public.user_analytics(date DESC);

-- Coupon Usage Events
CREATE INDEX idx_coupon_usage_user_id ON public.coupon_usage_events(user_id);
CREATE INDEX idx_coupon_usage_used_at ON public.coupon_usage_events(used_at);
CREATE INDEX idx_coupon_usage_website ON public.coupon_usage_events(website_domain);

-- Popular Websites
CREATE INDEX idx_popular_websites_ranking ON public.popular_websites(ranking) WHERE ranking IS NOT NULL;
CREATE INDEX idx_popular_websites_searches ON public.popular_websites(total_searches DESC);