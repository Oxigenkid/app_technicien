import sys
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE

def build_presentation():
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)
    blank_layout = prs.slide_layouts[6]

    COLOR_BG = RGBColor(11, 17, 32)        # #0B1120
    COLOR_CARD = RGBColor(21, 31, 50)      # #151F32
    COLOR_INNER = RGBColor(30, 41, 59)     # #1E293B
    COLOR_RED = RGBColor(209, 0, 31)       # #D1001F
    COLOR_LIGHT_RED = RGBColor(255, 82, 109)
    COLOR_WHITE = RGBColor(248, 250, 252)
    COLOR_MUTED = RGBColor(148, 163, 184)
    COLOR_BLUE = RGBColor(56, 189, 248)
    COLOR_GREEN = RGBColor(52, 211, 153)
    COLOR_AMBER = RGBColor(251, 191, 36)

    slides_data = [
        # Slide 1: Cover
        {
            "type": "cover",
            "badge": "SYSTÈME OFFICIEL DE SERVICE TERRAIN",
            "title": "RaycoFieldService",
            "subtitle": "L'écosystème numérique complet conçu pour les techniciens spécialistes de grues et systèmes de levage Rayco Wylie. Interventions en direct, horodatage certifié, inventaire camions, scanner IA, feuilles de temps et synchronisation cloud instantanée.",
            "tags": [
                ("💻 Windows Desktop", "Bureau & PDF Natif"),
                ("📱 Android APK", "Route, Caméra & GPS"),
                ("☁️ Supabase Cloud", "Temps Réel & Multi-Postes"),
                ("🔒 NIP Personnel", "Sécurité RH & Dépenses")
            ]
        },
        # Slide 2: Vision
        {
            "category": "ENJEUX & VISION",
            "title": "Moderniser & Fiabiliser le Service Terrain",
            "points": [
                ("Zéro Papier & Zéro Perte :", " Remplacement définitif des formulaires manuscrits, illisibles ou égarés entre le chantier et le bureau."),
                ("Traçabilité Totale des Heures :", " Découpage certifié automatique entre trajet aller/retour, chantier actif, pauses et attente facturable."),
                ("Saisie Continue sur le Terrain :", " Ajout direct des photos, notes et pièces utilisées au fur et à mesure des travaux, avant même la clôture."),
                ("Économie de Temps Majeure :", " Plus d'1h30 de formalités administratives économisée chaque jour par technicien.")
            ],
            "cards": [
                ("📄 Standardisation Rayco Wylie", "Contrôles de sécurité conformes aux normes CSA/OSHA pour grues téléscopiques, mobiles et nacelles."),
                ("⏱️ Zéro Litige Facturation", "Horodatage précis dès le départ jusqu'à la signature client éliminant toute contestation d'heures.")
            ]
        },
        # Slide 3: Architecture
        {
            "category": "ARCHITECTURE SYSTÈME",
            "title": "Multiplateforme & Synchronisation Cloud Parfaite",
            "points": [
                ("Supabase Realtime PostgreSQL :", " Flux WebSocket bidirectionnel instantané. Dès qu'une modification survient, tous les appareils sont mis à jour sans recharger."),
                ("Heartbeat Silencieux 10s :", " Auto-synchronisation intelligente d'arrière-plan pour assurer la cohérence entre Android et Windows en permanence."),
                ("Suppression Multi-Appareils Blindée :", " Les interventions supprimées sur un poste s'effacent instantanément sur toute la flotte sans réapparaître."),
                ("Résilience Hors-Ligne (Offline First) :", " Les données restent éditables en zone blanche et se synchronisent dès le retour du réseau.")
            ],
            "cards": [
                ("🖥️ Windows Desktop", "Idéal pour le superviseur et le bureau. Affichage complet, génération de rapports et archivage automatique."),
                ("📱 Android APK", "Optimisé pour téléphones de cabine. Intégration GPS, saisie tactile et scanner de reçus par caméra.")
            ]
        },
        # Slide 4: Dispatch
        {
            "category": "DISPATCH & PILOTAGE",
            "title": "Tableau de Bord & Fiches d'Intervention Riches",
            "points": [
                ("Données Clients & Références :", " Numéro de commande (CO-xxxxx), bon de commande client (#PO), référence (#TF) et contact chantier avec appel en un clic."),
                ("Équipements Rayco Wylie :", " Suivi du type de machine, marque, modèle, numéro d'unité (#GR), numéro de série et modèle de système (i4500 RCI)."),
                ("Filtrage Superviseur Instantané :", " Filtre par technicien ou vue globale de tous les chantiers en cours avec indicateurs visuels de priorité."),
                ("Cycle de Vie Dynamique :", " Progression pas à pas : En attente ➔ En route ➔ Arrivé / Chantier ➔ Pause ➔ Complété.")
            ],
            "cards": [
                ("🧭 Barre d'Outils Contextuelle", "Boutons d'accès direct sur chaque fiche : 📸 Photos, 📝 Notes de service et 🔩 Gestion des pièces."),
                ("📞 Actions d'Urgence", "Lancement direct d'un appel téléphonique ou guidage routier sans copier-coller l'adresse.")
            ]
        },
        # Slide 5: Mobilité & Navigation
        {
            "category": "MOBILITÉ & GÉOLOCALISATION",
            "title": "Départ Immédiat & Navigation Google Maps",
            "points": [
                ("Navigation en 1 Clic :", " Le bouton « Démarrer le trajet » ouvre Google Maps avec l'adresse du chantier pré-remplie et lance le chronomètre."),
                ("Calcul Kilométrique & GPS :", " Coordonnées de départ et d'arrivée mémorisées pour validation précise du déplacement facturable."),
                ("Gestion des Imprévus de Route :", " Mise en pause du trajet pour essence ou embouteillage sans fausser le temps d'intervention sur site."),
                ("Confirmation d'Arrivée :", " Déclenche automatiquement l'horodatage de début de chantier et passe le statut à « Arrivé ».")
            ],
            "cards": [
                ("⏱️ Horodateur Automatique", "Horodatage officiel certifié pour calcul exact du temps de route versus temps machine."),
                ("🗺️ Compatibilité Double OS", "Intents Google Maps natifs sur Android et ouverture du navigateur cartographique sur Windows.")
            ]
        },
        # Slide 6: Pièces & Notes sur le terrain
        {
            "category": "PRODUCTIVITÉ CHANTIER",
            "title": "Ajout des Pièces, Notes & Photos en Direct",
            "points": [
                ("Ajout de Pièces sur la Page Principale :", " Le technicien peut ajouter les composantes utilisées directement pendant l'intervention via le bouton 🔩 + Pièce."),
                ("Synchronisation Cloud Immédiate :", " Les pièces saisies sont enregistrées dans Supabase et pré-remplies automatiquement à l'ouverture du rapport final."),
                ("Galerie Photos Chantier Dédiée :", " Prise de vue avant/après intervention, identification de capteurs défectueux et photos d'ensemble."),
                ("Notes de Service Partagées :", " Consignes d'accès, historique mécanique et observations transmises en direct au bureau de dispatch.")
            ],
            "cards": [
                ("➕ Ajustement Rapide", "Incrémentez/décrémentez les quantités en direct (+ / -) avec affichage du stock disponible par camion."),
                ("📑 Zéro Oubli au Rapport", "Tout ce qui a été noté sur le chantier se retrouve automatiquement injecté dans le rapport officiel.")
            ]
        },
        # Slide 7: Rapport & AAMMJJHHNN
        {
            "category": "RAPPORT & FACTURATION",
            "title": "Rapports Officiels & Numérotation AAMMJJHHNN",
            "points": [
                ("Nouveau Format de Rapport (AAMMJJHHNN) :", " Numérotation chronologique standardisée (Année, Mois, Jour, Heure, Minute - ex : 2610071648)."),
                ("Grille des 6 Contrôles Rayco Wylie :", " Câbles A2B, seuils d'afficheur cabine, solénoïdes de coupure, faisceaux, tables de charge et fixations."),
                ("Signature Client Tactile :", " Recueil de la signature sur écran avec nom du représentant et horodatage certifié sur le PDF."),
                ("PDF Rayco Wylie Professionnel :", " Mise en page haute qualité, logo officiel, ventilation complète des temps et tableau des pièces.")
            ],
            "cards": [
                ("📁 Archivage Automatique", "Sauvegarde dans Documents/RaycoWylie_Documents et stockage cloud prêt pour envoi courriel immédiat."),
                ("⏱️ Arrondi Facturable", "Calcul intelligent au quart d'heure supérieur avec estimation symétrique du trajet retour.")
            ]
        },
        # Slide 8: RH & Feuilles de temps
        {
            "category": "RH & GESTION DE PAIE",
            "title": "Feuilles de Temps Sécurisées par Code NIP",
            "points": [
                ("Code NIP à 4 Chiffres Strict :", " Chaque technicien possède son NIP unique pour consulter et modifier ses heures en toute confidentialité."),
                ("Ventilation en 4 Catégories :", " Déplacement, Travail sur chantier, Attente facturable et déduction systématique des pauses repas."),
                ("« Clock-In / Clock-Out » & Présence :", " Horodateur de quart de travail avec totalisation automatique des heures régulières et supplémentaires."),
                ("Fonction « Estimer Vendredi » :", " Permet d'anticiper le dernier vendredi de la période pour déposer la feuille de paie sans blocage administratif.")
            ],
            "cards": [
                ("🛡️ Verrouillage Anti-Fraude", "Reverrouillage automatique dès qu'un utilisateur change de technicien ou quitte la vue."),
                ("📋 Export Paie Impeccable", "Relevé bimensuel prêt pour la comptabilité avec ventilation complète de chaque journée.")
            ]
        },
        # Slide 9: Dépenses & OCR
        {
            "category": "COMPTABILITÉ MOBILE",
            "title": "Comptes de Dépenses & Scanner IA de Factures",
            "points": [
                ("Scanner IA Intelligent (OCR) :", " Prenez en photo un reçu (restaurant, essence, quincaillerie), l'IA extrait instantanément les données."),
                ("Détection Fiscale Canadienne :", " Extraction du marchand, de la date, du sous-total et calcul automatique TPS/TVQ."),
                ("Ventilation des Pourboires :", " Séparation automatique du pourboire de restaurant selon les normes comptables strictes de l'entreprise."),
                ("Protection par NIP :", " Accès exclusif au compte de dépenses de chaque technicien pour garantir la confidentialité financière.")
            ],
            "cards": [
                ("📸 Zéro Reçu Perdu", "L'image haute définition du reçu est stockée et attachée directement à la ligne comptable."),
                ("📑 Catégorisation Nette", "Carburant, Repas, Hôtel, Outillage, Stationnement avec statuts Approuvé / Payé.")
            ]
        },
        # Slide 10: Inventaire
        {
            "category": "LOGISTIQUE & MATÉRIEL",
            "title": "Inventaire des Camions & Déstockage Automatique",
            "points": [
                ("Inventaire Individualisé par Camion :", " Suivi précis pour Camion #101 (David Hestin), #102 (P-O Patry) et #103 (J-F Allie)."),
                ("Catalogue Officiel Rayco Wylie :", " Références officielles (11BFL..., capteurs, afficheurs, solénoïdes, boîtiers de jonction)."),
                ("Déduction Automatique au Rapport :", " Déstockage automatique des pièces utilisées dès que le rapport d'intervention est validé."),
                ("Recherche Multicritères & Alertes :", " Filtre par camion, disponibilité immédiate et badges d'alerte pour commander à temps.")
            ],
            "cards": [
                ("🔄 Cohérence Stock", "Fin des décalages d'inventaire entre le magasin de pièces central et le stock embarqué dans les camions."),
                ("👥 Emprunt Inter-Camions", "Possibilité d'enregistrer une pièce issue d'un autre camion avec traçabilité complète.")
            ]
        },
        # Slide 11: Rendez-vous
        {
            "category": "PLANIFICATION & AGENDA",
            "title": "Rendez-vous & Synchronisation Outlook / Google",
            "points": [
                ("Planning Centralisé :", " Planification précise avec date, heure d'arrivée prévisionnelle, durée estimée et assignation technicien."),
                ("Fichiers d'Invitation .ICS :", " Génération en un clic d'invitations calendrier compatibles avec Outlook, Microsoft 365 et Apple Calendar."),
                ("Intégration Google Agenda :", " Ajout direct dans l'agenda mobile du technicien sans aucune double saisie manuelle."),
                ("Réassignation & Vue Flotte :", " Visibilité claire de la charge de chaque technicien pour réaffecter les urgences instantanément.")
            ],
            "cards": [
                ("🚨 Convocations Immédiates", "Toutes les informations utiles (contact, grue, diagnostic préalable) transmises dans le corps de l'événement."),
                ("🔄 Vue Synchronisée", "Le technicien voit son agenda se mettre à jour directement sur son application mobile.")
            ]
        },
        # Slide 12: Conclusion
        {
            "type": "cover",
            "badge": "LE STANDARD D'EXCELLENCE RAYCO WYLIE",
            "title": "Prêt pour le Terrain",
            "subtitle": "RaycoFieldService unifie l'ensemble des opérations de service dans un système robuste, moderne et parfaitement connecté. Moins d'administration, plus de productivité et une traçabilité irréprochable.",
            "tags": [
                ("⏱️ +20% Productivité", "Gain de temps administratif par technicien"),
                ("🎯 100% Rapports Signés", "Format standardisé AAMMJJHHNN"),
                ("🔒 100% Sécurisé NIP", "Confidentialité totale des heures et reçus"),
                ("☁️ Synchro Supabase Live", "Zéro conflit multi-postes")
            ]
        }
    ]

    for idx, data in enumerate(slides_data):
        slide = prs.slides.add_slide(blank_layout)

        # Arrière-plan
        bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(13.333), Inches(7.5))
        bg.fill.solid()
        bg.fill.fore_color.rgb = COLOR_BG
        bg.line.fill.background()

        # Bordure supérieure rouge Rayco Wylie
        top_bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(13.333), Inches(0.12))
        top_bar.fill.solid()
        top_bar.fill.fore_color.rgb = COLOR_RED
        top_bar.line.fill.background()

        if data.get("type") == "cover":
            # --- Slide de type Couverture / Fin ---
            card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(1.2), Inches(0.8), Inches(10.933), Inches(5.9))
            card.fill.solid()
            card.fill.fore_color.rgb = COLOR_CARD
            card.line.color.rgb = RGBColor(40, 55, 80)
            card.line.width = Pt(1.5)

            # Badge
            badge_box = slide.shapes.add_textbox(Inches(1.5), Inches(1.2), Inches(10.333), Inches(0.5))
            tf_b = badge_box.text_frame
            tf_b.word_wrap = True
            p_b = tf_b.paragraphs[0]
            p_b.alignment = PP_ALIGN.CENTER
            run_b = p_b.add_run()
            run_b.text = data["badge"]
            run_b.font.size = Pt(12)
            run_b.font.bold = True
            run_b.font.color.rgb = COLOR_LIGHT_RED

            # Titre
            title_box = slide.shapes.add_textbox(Inches(1.5), Inches(1.8), Inches(10.333), Inches(1.2))
            tf_t = title_box.text_frame
            tf_t.word_wrap = True
            p_t = tf_t.paragraphs[0]
            p_t.alignment = PP_ALIGN.CENTER
            run_t = p_t.add_run()
            run_t.text = data["title"]
            run_t.font.size = Pt(46)
            run_t.font.bold = True
            run_t.font.color.rgb = COLOR_WHITE

            # Sous-titre
            sub_box = slide.shapes.add_textbox(Inches(2.0), Inches(3.1), Inches(9.333), Inches(1.3))
            tf_s = sub_box.text_frame
            tf_s.word_wrap = True
            p_s = tf_s.paragraphs[0]
            p_s.alignment = PP_ALIGN.CENTER
            run_s = p_s.add_run()
            run_s.text = data["subtitle"]
            run_s.font.size = Pt(16)
            run_s.font.color.rgb = COLOR_MUTED

            # Tags horizontaux (4 colonnes)
            tags = data.get("tags", [])
            tag_w = Inches(2.35)
            gap = Inches(0.25)
            start_x = Inches(1.6)
            y_pos = Inches(4.7)

            for i, (tag_title, tag_desc) in enumerate(tags):
                tx = start_x + i * (tag_w + gap)
                t_card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, tx, y_pos, tag_w, Inches(1.4))
                t_card.fill.solid()
                t_card.fill.fore_color.rgb = COLOR_INNER
                t_card.line.color.rgb = RGBColor(50, 70, 100)
                t_card.line.width = Pt(1)

                tb = slide.shapes.add_textbox(tx + Inches(0.1), y_pos + Inches(0.15), tag_w - Inches(0.2), Inches(1.1))
                tf_tag = tb.text_frame
                tf_tag.word_wrap = True
                p1 = tf_tag.paragraphs[0]
                p1.alignment = PP_ALIGN.CENTER
                r1 = p1.add_run()
                r1.text = tag_title
                r1.font.size = Pt(13)
                r1.font.bold = True
                r1.font.color.rgb = COLOR_WHITE

                p2 = tf_tag.add_paragraph()
                p2.alignment = PP_ALIGN.CENTER
                r2 = p2.add_run()
                r2.text = tag_desc
                r2.font.size = Pt(11)
                r2.font.color.rgb = COLOR_MUTED

        else:
            # --- Slide Standard (Contenu en 2 colonnes) ---
            main_card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.8), Inches(0.55), Inches(11.733), Inches(6.3))
            main_card.fill.solid()
            main_card.fill.fore_color.rgb = COLOR_CARD
            main_card.line.color.rgb = RGBColor(35, 50, 75)
            main_card.line.width = Pt(1.5)

            # Catégorie (en rouge)
            cat_box = slide.shapes.add_textbox(Inches(1.2), Inches(0.8), Inches(10.5), Inches(0.35))
            tf_cat = cat_box.text_frame
            p_cat = tf_cat.paragraphs[0]
            r_cat = p_cat.add_run()
            r_cat.text = data["category"]
            r_cat.font.size = Pt(11)
            r_cat.font.bold = True
            r_cat.font.color.rgb = COLOR_LIGHT_RED

            # Titre de la slide
            title_box = slide.shapes.add_textbox(Inches(1.2), Inches(1.15), Inches(10.5), Inches(0.7))
            tf_t = title_box.text_frame
            p_t = tf_t.paragraphs[0]
            r_t = p_t.add_run()
            r_t.text = data["title"]
            r_t.font.size = Pt(26)
            r_t.font.bold = True
            r_t.font.color.rgb = COLOR_WHITE

            # Ligne de séparation
            sep = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(1.2), Inches(1.9), Inches(10.9), Inches(0.02))
            sep.fill.solid()
            sep.fill.fore_color.rgb = RGBColor(40, 55, 80)
            sep.line.fill.background()

            # Colonne Gauche : Liste des points clés (4 points)
            pts_box = slide.shapes.add_textbox(Inches(1.2), Inches(2.1), Inches(6.8), Inches(4.3))
            tf_pts = pts_box.text_frame
            tf_pts.word_wrap = True

            for p_i, (p_bold, p_text) in enumerate(data.get("points", [])):
                p = tf_pts.paragraphs[0] if p_i == 0 else tf_pts.add_paragraph()
                p.space_after = Pt(14)
                
                # Puce rouge
                r_bullet = p.add_run()
                r_bullet.text = "●  "
                r_bullet.font.size = Pt(13)
                r_bullet.font.color.rgb = COLOR_RED
                
                # Texte gras
                r_b = p.add_run()
                r_b.text = p_bold
                r_b.font.size = Pt(13.5)
                r_b.font.bold = True
                r_b.font.color.rgb = COLOR_WHITE

                # Texte normal
                r_n = p.add_run()
                r_n.text = p_text
                r_n.font.size = Pt(13)
                r_n.font.color.rgb = COLOR_MUTED

            # Colonne Droite : 2 Cartes Encart Dédiées
            cards = data.get("cards", [])
            card_w = Inches(3.8)
            card_h = Inches(1.9)
            card_x = Inches(8.3)
            card_y1 = Inches(2.25)
            card_y2 = Inches(4.35)

            for c_i, (c_title, c_desc) in enumerate(cards):
                cy = card_y1 if c_i == 0 else card_y2

                c_box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, card_x, cy, card_w, card_h)
                c_box.fill.solid()
                c_box.fill.fore_color.rgb = COLOR_INNER
                c_box.line.color.rgb = RGBColor(50, 70, 100)
                c_box.line.width = Pt(1)

                # Bordure gauche rouge
                c_accent = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, card_x, cy, Inches(0.12), card_h)
                c_accent.fill.solid()
                c_accent.fill.fore_color.rgb = COLOR_RED if c_i == 0 else COLOR_BLUE
                c_accent.line.fill.background()

                c_tb = slide.shapes.add_textbox(card_x + Inches(0.25), cy + Inches(0.15), card_w - Inches(0.4), card_h - Inches(0.3))
                tf_c = c_tb.text_frame
                tf_c.word_wrap = True

                cp1 = tf_c.paragraphs[0]
                cp1.space_after = Pt(6)
                cr1 = cp1.add_run()
                cr1.text = c_title
                cr1.font.size = Pt(13.5)
                cr1.font.bold = True
                cr1.font.color.rgb = COLOR_WHITE

                cp2 = tf_c.add_paragraph()
                cr2 = cp2.add_run()
                cr2.text = c_desc
                cr2.font.size = Pt(11.5)
                cr2.font.color.rgb = COLOR_MUTED

    output_path = r"c:\Users\popatry\app_technicien\RaycoFieldService_Presentation.pptx"
    prs.save(output_path)
    print(f"Presentation saved successfully to {output_path}")

if __name__ == "__main__":
    build_presentation()
