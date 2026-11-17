-- ==============================================================================
-- 🚀 ACTIVATION DU BUCKET STORAGE ET ACCÉLÉRATION DES RECHERCHES D'ARCHIVES
-- À exécuter dans votre tableau de bord Supabase -> SQL Editor -> Run
-- ==============================================================================

-- 1. CRÉATION DU BUCKET STORAGE 'photos_chantier'
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'photos_chantier',
    'photos_chantier',
    TRUE,
    20971520, -- 20 Mo max par photo / rapport
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- 2. POLITIQUES D'ACCÈS RLS (LECTURE & ÉCRITURE POUR L'APPLICATION)
DROP POLICY IF EXISTS "Lecture publique photos_chantier" ON storage.objects;
CREATE POLICY "Lecture publique photos_chantier" ON storage.objects
    FOR SELECT USING (bucket_id = 'photos_chantier');

DROP POLICY IF EXISTS "Insertion publique photos_chantier" ON storage.objects;
CREATE POLICY "Insertion publique photos_chantier" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'photos_chantier');

DROP POLICY IF EXISTS "Modification publique photos_chantier" ON storage.objects;
CREATE POLICY "Modification publique photos_chantier" ON storage.objects
    FOR UPDATE USING (bucket_id = 'photos_chantier');

DROP POLICY IF EXISTS "Suppression publique photos_chantier" ON storage.objects;
CREATE POLICY "Suppression publique photos_chantier" ON storage.objects
    FOR DELETE USING (bucket_id = 'photos_chantier');

-- 3. INDEX POUR RECHERCHE RAPIDE DES ARCHIVES D'INTERVENTIONS
CREATE INDEX IF NOT EXISTS idx_interventions_statut ON public.interventions(statut);
CREATE INDEX IF NOT EXISTS idx_interventions_recherche ON public.interventions(numero_commande, nom_client, type_machine);
