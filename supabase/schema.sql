-- VerbaDoc Supabase Schema
-- Run these in the Supabase SQL editor (Dashboard → SQL Editor → New query)

-- ── Tables ────────────────────────────────────────────────────────────────

-- user_plans: one row per user, defaults to free
CREATE TABLE IF NOT EXISTS public.user_plans (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    plan    TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- usage_tracking: one row per (user, month)
-- month format: 'YYYY-MM'
CREATE TABLE IF NOT EXISTS public.usage_tracking (
    user_id          UUID    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month            TEXT    NOT NULL,
    generation_count INT     NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, month)
);

-- ── RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.user_plans     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_tracking ENABLE ROW LEVEL SECURITY;

-- Users can read their own plan (the iOS app calls /rest/v1/user_plans)
CREATE POLICY "own plan read" ON public.user_plans
    FOR SELECT USING (auth.uid() = user_id);

-- Only service role can insert/update plans (done by webhook / admin)
-- Usage writes go through the Edge Function using the service role key.

-- ── Function: increment_usage ─────────────────────────────────────────────
-- Called by the Edge Function via adminClient.rpc(...)

CREATE OR REPLACE FUNCTION public.increment_usage(p_user_id UUID, p_month TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER   -- runs as postgres, bypasses RLS
AS $$
BEGIN
    INSERT INTO public.usage_tracking (user_id, month, generation_count)
    VALUES (p_user_id, p_month, 1)
    ON CONFLICT (user_id, month)
    DO UPDATE SET generation_count = usage_tracking.generation_count + 1;
END;
$$;

-- ── Trigger: auto-create free plan on sign-up ─────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.user_plans (user_id, plan)
    VALUES (NEW.id, 'free')
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── RevenueCat webhook (optional) ─────────────────────────────────────────
-- When a user purchases Pro in the App Store, RevenueCat sends a webhook.
-- Create a Supabase Edge Function (e.g. /functions/v1/revenuecat-webhook)
-- that verifies the RevenueCat signature and runs:
--
--   UPDATE public.user_plans
--   SET plan = 'pro', updated_at = now()
--   WHERE user_id = '<user-id-from-app-user-id>';
--
-- RevenueCat app_user_id should be set to the Supabase user UUID on sign-in:
--   // In iOS, after AuthService.signIn():
--   Purchases.shared.logIn(AuthService.shared.currentUser!.id) { _, _, _ in }
