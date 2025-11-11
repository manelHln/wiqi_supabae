-- =====================================================
-- Function to update updated_at timestamp
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = pg_catalog.NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Apply trigger to all tables with updated_at
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_subscriptions_updated_at 
    BEFORE UPDATE ON public.user_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_search_quota_usage_updated_at 
    BEFORE UPDATE ON public.search_quota_usage
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_followed_websites_updated_at 
    BEFORE UPDATE ON public.followed_websites
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_price_trackers_updated_at 
    BEFORE UPDATE ON public.price_trackers
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_settings_updated_at 
    BEFORE UPDATE ON public.user_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_referral_codes_updated_at 
    BEFORE UPDATE ON public.referral_codes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_analytics_updated_at 
    BEFORE UPDATE ON public.user_analytics
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_platform_analytics_updated_at 
    BEFORE UPDATE ON public.platform_analytics
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Create user profile
    INSERT INTO public.users (id, email, created_at)
    VALUES (NEW.id, NEW.email, NOW());
    
    -- Create default user settings
    INSERT INTO public.user_settings (user_id)
    VALUES (NEW.id);
    
    -- Assign free plan
    INSERT INTO public.user_subscriptions (user_id, plan_id, current_period_start, current_period_end)
    SELECT NEW.id, id, NOW(), NOW() + INTERVAL '100 years'
    FROM public.subscription_plans WHERE slug = 'free';
    
    -- Generate referral code
    INSERT INTO public.referral_codes (user_id, referral_code)
    VALUES (NEW.id, LOWER(SUBSTRING(MD5(NEW.id::text || NOW()::text) FROM 1 FOR 10)));
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION add_user_to_mailchimp()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM net.http_post(
    url := 'http://host.docker.internal:54321/functions/v1/add-email-to-mailchimp',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', 'd49edc0a92f7de2698d7fdfcd3da19b9c5e3d5b031a171f47e1cbc908f39370f'
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW),
      'schema', TG_TABLE_SCHEMA,
      'old_record', NULL
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE TRIGGER on_user_created
  AFTER INSERT ON users
  FOR EACH ROW
  EXECUTE FUNCTION add_user_to_mailchimp();