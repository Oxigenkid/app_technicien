-- ==============================================================================
-- 🚀 CONFIGURATION & SYNCHRONISATION SUPABASE - RAYCO FIELD SERVICE
-- Projet : tnkyoqpxewvjsqlkvkcf.supabase.co
-- Exécutez ce script dans l'éditeur SQL de votre tableau de bord Supabase (SQL Editor)
-- pour activer la synchronisation bidirectionnelle en direct (Temps Réel)
-- ==============================================================================

-- 0. NETTOYAGE PRÉVENTIF DES ANCIENNES TABLES VIDES (Évite l'erreur 'id en UUID')
DROP TABLE IF EXISTS public.interventions CASCADE;
DROP TABLE IF EXISTS public.techniciens CASCADE;
DROP TABLE IF EXISTS public.depenses CASCADE;
DROP TABLE IF EXISTS public.inventaire_camion CASCADE;

-- 1. CRÉATION DE LA TABLE 'interventions' (id TEXT universel)
CREATE TABLE public.interventions (
    id TEXT PRIMARY KEY,
    nom_client TEXT,
    adresse_facturation TEXT,
    adresse TEXT,
    statut TEXT DEFAULT 'En attente',
    numero_commande TEXT,
    numero_bon_commande TEXT,
    numero_rapport TEXT,
    numero_reference TEXT,
    adresse_intervention TEXT,
    nom_technicien TEXT,
    numero_camion TEXT,
    trouble TEXT,
    type_machine TEXT,
    marque TEXT,
    modele TEXT,
    annee TEXT,
    numero_serie_machine TEXT,
    numero_unite TEXT,
    alimentation TEXT,
    numero_produit TEXT,
    numero_serie_systeme TEXT,
    version_logiciel TEXT,
    engrenage TEXT,
    position_bypass TEXT,
    priorite TEXT DEFAULT 'Normale',
    date_rendez_vous TEXT,
    heure_rendez_vous TEXT,
    duree_minutes INTEGER DEFAULT 120,
    telephone TEXT,
    courriel TEXT,
    nom_contact TEXT,
    date_chantier TEXT,
    heure_depart_trajet TIMESTAMPTZ,
    heure_arrivee_site TIMESTAMPTZ,
    heure_debut_redaction_rapport TIMESTAMPTZ,
    heure_cloture TIMESTAMPTZ,
    heure_signature TIMESTAMPTZ,
    duree_trajet TEXT,
    distance_km TEXT,
    duree_chantier TEXT,
    duree_chantier_secondes BIGINT DEFAULT 0,
    duree_redaction_secondes BIGINT DEFAULT 0,
    duree_pause_secondes BIGINT DEFAULT 0,
    duree_pause_chantier_secondes BIGINT DEFAULT 0,
    en_pause BOOLEAN DEFAULT FALSE,
    heure_debut_pause TIMESTAMPTZ,
    en_pause_chantier BOOLEAN DEFAULT FALSE,
    heure_debut_pause_chantier TIMESTAMPTZ,
    motif_pause_chantier TEXT,
    gps_depart TEXT,
    gps_lat_depart DOUBLE PRECISION,
    gps_lng_depart DOUBLE PRECISION,
    gps_arrivee TEXT,
    notes TEXT,
    photos TEXT,
    pieces_utilisees TEXT,
    signature TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mises à jour préventives (si la table existe déjà)
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS numero_bon_commande TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS numero_reference TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS numero_unite TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS adresse_intervention TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS adresse_facturation TEXT;
ALTER TABLE public.interventions ADD COLUMN IF NOT EXISTS courriel_technicien TEXT;

-- 2. CRÉATION DE LA TABLE 'techniciens' (id TEXT universel)
CREATE TABLE public.techniciens (
    id TEXT PRIMARY KEY,
    nom TEXT NOT NULL,
    numero_camion TEXT,
    est_disponible BOOLEAN DEFAULT TRUE,
    telephone TEXT,
    courriel TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. CRÉATION DE LA TABLE 'depenses' (id TEXT universel)
CREATE TABLE public.depenses (
    id TEXT PRIMARY KEY,
    date TIMESTAMPTZ DEFAULT NOW(),
    technicien TEXT,
    montant DOUBLE PRECISION NOT NULL,
    pourboire DOUBLE PRECISION DEFAULT 0,
    categorie TEXT,
    description TEXT,
    fournisseur TEXT,
    numero_commande TEXT,
    photo_path TEXT,
    mode_paiement TEXT DEFAULT 'Personnel (À rembourser)',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CRÉATION DE LA TABLE 'inventaire_camion' (Multi-camions RaycoWylie)
CREATE TABLE IF NOT EXISTS public.inventaire_camion (
    id TEXT PRIMARY KEY,
    camion TEXT NOT NULL DEFAULT 'Camion #101',
    technicien TEXT,
    localisation TEXT,
    ref TEXT NOT NULL,
    nom TEXT NOT NULL,
    quantite INTEGER DEFAULT 0,
    unite TEXT DEFAULT 'pcs',
    cout DOUBLE PRECISION DEFAULT 0.0,
    entrepot TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.inventaire_camion ADD COLUMN IF NOT EXISTS id TEXT;
ALTER TABLE public.inventaire_camion ADD COLUMN IF NOT EXISTS camion TEXT;
ALTER TABLE public.inventaire_camion ADD COLUMN IF NOT EXISTS technicien TEXT;
ALTER TABLE public.inventaire_camion ADD COLUMN IF NOT EXISTS localisation TEXT;
ALTER TABLE public.inventaire_camion ADD COLUMN IF NOT EXISTS cout DOUBLE PRECISION DEFAULT 0.0;

-- ==============================================================================
-- 🔓 SÉCURITÉ & PERMISSIONS (DÉSACTIVATION DES RESTRICTIONS RLS BLOQUANTES)
-- ==============================================================================
ALTER TABLE public.interventions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.techniciens DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.depenses DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventaire_camion DISABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.interventions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.techniciens TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.depenses TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.inventaire_camion TO anon, authenticated, service_role;

-- ==============================================================================
-- ⚡ ACTIVATION DE LA SYNCHRONISATION EN DIRECT (SUPABASE REALTIME)
-- ==============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'interventions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.interventions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'techniciens'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.techniciens;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'depenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.depenses;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'inventaire_camion'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventaire_camion;
  END IF;
END $$;

-- ==============================================================================
-- 📋 INSERTION DES DONNÉES INITIALES (3 TECHNICIENS & 3 INTERVENTIONS RAYCOWYLIE)
-- ==============================================================================

-- 3 Techniciens avec leurs camions
INSERT INTO public.techniciens (id, nom, numero_camion, est_disponible, telephone, courriel)
VALUES 
    ('tech_01', 'Patrick Popatry', 'Camion #101', TRUE, '418-555-0101', 'p.popatry@raycowylie.com'),
    ('tech_02', 'Martin Tremblay', 'Camion #102', TRUE, '418-555-0102', 'm.tremblay@raycowylie.com'),
    ('tech_03', 'Jean-François Roy', 'Camion #103', FALSE, '418-555-0103', 'jf.roy@raycowylie.com');

-- 3 Interventions de démonstration
INSERT INTO public.interventions (
    id, nom_client, adresse_facturation, adresse, statut, numero_commande, 
    nom_technicien, numero_camion, trouble, type_machine, priorite, 
    date_rendez_vous, heure_rendez_vous, duree_minutes, telephone, courriel
) VALUES 
(
    '1',
    'Auvents W. Lecours',
    'C.P. 1204, Succ. Terminus, Québec, QC G1K 7D7',
    '1050 Boulevard Laurier, Quebec City, QC',
    'En attente',
    'CO-2026-0891',
    'Patrick Popatry',
    'Camion #101',
    'Afficheur Rayco Wylie ne s''allume pas. Câble d''alimentation coupé lors de manœuvres.',
    'Grue mobile Liebherr LTM 1050',
    'Urgente',
    '2026-09-26',
    '08:30',
    120,
    '418-650-2020',
    'service@auventslecours.com'
),
(
    '2',
    'Cosmos Lebourgneuf',
    '5700 Boulevard des Galeries, Bureau 200, Québec, QC G2K 2J6',
    '5700 Boulevard des Galeries, Quebec City, QC',
    'En route',
    'CO-2026-0944',
    'Martin Tremblay',
    'Camion #102',
    'Calibration de moment requise suite au remplacement du câble de télescopage.',
    'Grue télescopique Tadano 70T',
    'Normale',
    '2026-09-26',
    '13:00',
    180,
    '418-624-0024',
    'maintenance@cosmosresto.com'
),
(
    '3',
    'Hôtel Le Germain',
    '1224 Rue Stanley, Montréal, QC H3B 2S7',
    '75 Rue Saint-Antoine, Quebec City, QC',
    'Arrivé',
    'CO-2026-1012',
    'Jean-François Roy',
    'Camion #103',
    'Alarme de surcharge erronée sur capteur d''angle flèche.',
    'Camion-grue National Crane',
    'Critique',
    '2026-09-27',
    '09:00',
    240,
    '418-692-2224',
    'direction@legermainhotels.com'
);

-- Dépenses initiales
INSERT INTO public.depenses (id, date, technicien, montant, pourboire, categorie, fournisseur, description, mode_paiement, numero_commande)
VALUES
    ('dep_01', NOW() - INTERVAL '2 days', 'Patrick Popatry', 142.50, 0.00, 'essence', 'Pétro-Canada', 'Plein de diesel pour Camion #101', 'Personnel (À rembourser)', 'CO-2026-0891'),
    ('dep_02', NOW() - INTERVAL '1 days', 'Patrick Popatry', 18.50, 3.35, 'repas', 'Subway Lebourgneuf', 'Dîner lors de l''intervention sur grue Tadano', 'Personnel (À rembourser)', 'CO-2026-0944'),
    ('dep_03', NOW(), 'Patrick Popatry', 36.40, 0.00, 'outillage', 'BMR / Quincaillerie', 'Boulons inox et colliers de serrage pour capteur Wylie', 'Personnel (À rembourser)', 'CO-2026-1012');
