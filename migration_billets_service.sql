-- ==============================================================================
-- 🎫 MIGRATION SUPABASE : PROGRAMME DE BILLET DE SERVICE TÉLÉPHONIQUE RAYCOWYLIE
-- Inspiré du Flowchart officiel RaycoWylie (Capture -> Diagnostic -> Résolution -> Capitalisation)
-- Seules informations obligatoires : Nom du client (ou entreprise) & Téléphone
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.billets_service_technique (
    id TEXT PRIMARY KEY,
    reference_tf TEXT,                     -- TF-XXXXX (référence commande / billet)
    
    -- PHASE 1 : CAPTURE DU CONTACT (Obligatoires : nom_client & telephone)
    nom_client TEXT NOT NULL,              -- OBLIGATOIRE (Nom & prénom / contact)
    telephone TEXT NOT NULL,               -- OBLIGATOIRE (Téléphone du client)
    entreprise TEXT,                       -- Entreprise / Distributeur / Client final
    courriel TEXT,
    pays_region TEXT,                      -- Pays / région / fuseau horaire
    type_client TEXT DEFAULT 'Client final',-- 'Client final' ou 'Distributeur'
    
    -- IDENTIFICATION DE LA MACHINE (Optionnelle)
    type_grue TEXT,                        -- Boom truck, mobile, tour, portique, etc.
    marque TEXT,
    modele TEXT,
    numero_serie_machine TEXT,
    annee TEXT,
    heures_fonctionnement TEXT,
    site_chantier TEXT,                    -- Site / chantier / localisation
    
    -- SYSTÈME RAYCOWYLIE INSTALLÉ
    systeme_raycowylie TEXT,               -- i4000, i4500, i5000, i4300, ATB, etc.
    accessoires TEXT,                      -- Anémomètre, caméras, load link, Rayconnect...
    
    -- PHASE 2 : DIAGNOSTIC DU TROUBLE
    categorie_trouble TEXT,                -- 'Écran / Alimentation', 'Alarme surcharge', 'Anti-2-Block (ATB)', 'Capteurs & Mesures', 'Caméra / Affichage', 'Pièces / Commande'
    description_trouble TEXT,              -- Détails du symptôme signalé
    reponses_questions_guidees JSONB DEFAULT '{}'::jsonb, -- Questionnaire dynamique
    
    -- PHASE 3 : RÉSOLUTION & ESCALADE
    statut_resolution TEXT DEFAULT 'En cours', -- 'Résolu', 'Escalade', 'En cours', 'Fermé'
    solution_appliquee TEXT,               -- Procédure / solution adoptée
    pieces_utilisees TEXT,                 -- Pièces requises ou livrées
    motif_escalade TEXT,                   -- 'Superviseur technique', 'Envoi de pièce (stock/RMA)', 'Rendez-vous technicien terrain'
    delai_promis TEXT,                     -- Délai promis au client
    relance_planifiee TIMESTAMPTZ,
    
    -- PHASE 4 : CAPITALISATION & SUIVI
    technicien_intervenant TEXT,
    notes_internes TEXT,
    duree_appel_secondes INTEGER DEFAULT 0, -- Durée chronométrée de l'appel
    duree_appel_texte TEXT,                -- 'HH:MM:SS'
    est_archive BOOLEAN DEFAULT FALSE,      -- Statut d'archivage
    est_resolu_premier_appel BOOLEAN DEFAULT FALSE,
    date_creation TIMESTAMPTZ DEFAULT NOW(),
    date_resolution TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.billets_service_technique ADD COLUMN IF NOT EXISTS duree_appel_secondes INTEGER DEFAULT 0;
ALTER TABLE public.billets_service_technique ADD COLUMN IF NOT EXISTS duree_appel_texte TEXT;
ALTER TABLE public.billets_service_technique ADD COLUMN IF NOT EXISTS est_archive BOOLEAN DEFAULT FALSE;

-- Index pour recherche instantanée rapide
CREATE INDEX IF NOT EXISTS idx_billets_reference_tf ON public.billets_service_technique (reference_tf);
CREATE INDEX IF NOT EXISTS idx_billets_nom_client ON public.billets_service_technique (nom_client);
CREATE INDEX IF NOT EXISTS idx_billets_telephone ON public.billets_service_technique (telephone);
CREATE INDEX IF NOT EXISTS idx_billets_num_serie ON public.billets_service_technique (numero_serie_machine);
CREATE INDEX IF NOT EXISTS idx_billets_systeme ON public.billets_service_technique (systeme_raycowylie);
CREATE INDEX IF NOT EXISTS idx_billets_statut ON public.billets_service_technique (statut_resolution);

-- Permissions d'accès sans restriction
ALTER TABLE public.billets_service_technique DISABLE ROW LEVEL SECURITY;
GRANT ALL ON TABLE public.billets_service_technique TO anon, authenticated, service_role;

-- Publication temps réel Supabase
ALTER PUBLICATION supabase_realtime ADD TABLE public.billets_service_technique;

NOTIFY pgrst, 'reload schema';
