-- Migration Supabase : Ajout des colonnes pour l'archivage des interventions
-- Exécutez ce script dans l'éditeur SQL de votre Dashboard Supabase si vous souhaitez
-- persister les colonnes dédiées en base de données.
-- (L'application supporte également un fallback 100% transparent via le champ 'notes')

ALTER TABLE interventions 
ADD COLUMN IF NOT EXISTS est_archive BOOLEAN DEFAULT FALSE;

ALTER TABLE interventions 
ADD COLUMN IF NOT EXISTS date_archivage TIMESTAMPTZ;

-- Index pour accélérer les requêtes de filtrage par état d'archivage
CREATE INDEX IF NOT EXISTS idx_interventions_est_archive ON interventions(est_archive);
