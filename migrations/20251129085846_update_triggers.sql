CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Create user profile
    INSERT INTO public.users (id, email, first_name, last_name, created_at)
    VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'first_name', NEW.raw_user_meta_data->>'last_name', NOW());
    
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