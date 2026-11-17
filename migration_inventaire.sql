-- Exécutez ces 4 lignes dans Supabase SQL Editor :

ALTER TABLE public.inventaire_camion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.inventaire_camion;
CREATE POLICY "Allow all" ON public.inventaire_camion FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);
NOTIFY pgrst, 'reload schema';
