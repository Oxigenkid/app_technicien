-- ✍️ Migration Supabase pour la signature client à distance
-- Ajoute les colonnes dédiées pour sécuriser et accélérer l'accès par token

ALTER TABLE public.interventions 
ADD COLUMN IF NOT EXISTS signature_token TEXT,
ADD COLUMN IF NOT EXISTS signature_a_distance_demandee BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS nom_signataire_distant TEXT;

-- Index pour recherche rapide et sécurisée par token web
CREATE INDEX IF NOT EXISTS idx_interventions_signature_token 
ON public.interventions (signature_token);

-- S'assurer que les politiques RLS autorisent bien la lecture et la mise à jour pour anon / authenticated
ALTER TABLE public.interventions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all" ON public.interventions;
CREATE POLICY "Allow all" ON public.interventions FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true);

-- Notifier PostgREST pour recharger le schéma
NOTIFY pgrst, 'reload schema';
