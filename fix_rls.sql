-- Activer les permissions complètes de lecture / écriture pour tous les appareils
ALTER TABLE public.interventions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.interventions;
CREATE POLICY "Allow all" ON public.interventions FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);

ALTER TABLE public.techniciens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.techniciens;
CREATE POLICY "Allow all" ON public.techniciens FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);

ALTER TABLE public.depenses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.depenses;
CREATE POLICY "Allow all" ON public.depenses FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);

ALTER TABLE public.inventaire_camion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.inventaire_camion;
CREATE POLICY "Allow all" ON public.inventaire_camion FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);

-- Notifier Supabase de recharger immédiatement le cache
NOTIFY pgrst, 'reload schema';
