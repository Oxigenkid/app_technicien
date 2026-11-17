-- ==============================================================================
-- 🚀 AJOUT DES COLONNES MANQUANTES & RÉPLICATION COMPLÈTE TEMPS RÉEL
-- ==============================================================================

-- 1. Colonnes requises par les formulaires pour éviter les erreurs de schéma
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS systeme_wylie TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS type_intervention TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS numero_bon_commande TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS adresse_intervention TEXT;

-- 2. Réplication complète : indispensable pour que Supabase Realtime diffuse
--    instantanément les SUPPRESSIONS et MODIFICATIONS vers Windows et Android
ALTER TABLE public.interventions REPLICA IDENTITY FULL;
ALTER TABLE public.techniciens REPLICA IDENTITY FULL;
ALTER TABLE public.depenses REPLICA IDENTITY FULL;

-- 3. Rechargement immédiat du cache PostgREST
NOTIFY pgrst, 'reload schema';
