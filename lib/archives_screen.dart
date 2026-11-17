import 'package:flutter/material.dart';
import 'app_helpers.dart';
import 'rapport_detail_screen.dart';

/// 🏛️ Écran dédié aux Rapports et Interventions Archivés RaycoWylie
/// Comprend la recherche multi-critères : Système, Client, Machine, Contact, Dates, etc.
/// Permet de consulter le rapport complet et de Restaurer l'archive (obligatoire avant suppression).
class ArchivesRapportsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> interventions;
  final Function(Map<String, dynamic> item) onRestaurer;
  final Function(Map<String, dynamic> item) onSupprimerDefinitif;
  final VoidCallback onActualiser;

  const ArchivesRapportsScreen({
    super.key,
    required this.interventions,
    required this.onRestaurer,
    required this.onSupprimerDefinitif,
    required this.onActualiser,
  });

  @override
  State<ArchivesRapportsScreen> createState() => _ArchivesRapportsScreenState();
}

class _ArchivesRapportsScreenState extends State<ArchivesRapportsScreen> {
  final TextEditingController _rechercheCtrl = TextEditingController();
  String _critereFiltre = 'Tous'; // 'Tous', 'Système', 'Client', 'Machine', 'Technicien'
  String? _filtreTechnicien;
  String? _filtreSysteme;

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _interventionsArchivees {
    return widget.interventions.where((item) => estInterventionArchivee(item)).toList();
  }

  List<Map<String, dynamic>> get _interventionsFiltrees {
    final query = _rechercheCtrl.text.trim().toLowerCase();
    return _interventionsArchivees.where((item) {
      // 1. Filtre par technicien si sélectionné
      if (_filtreTechnicien != null && _filtreTechnicien != 'Tous') {
        final tech = (item['nom_technicien'] ?? '').toString();
        if (tech != _filtreTechnicien) return false;
      }

      // 2. Filtre rapide par type de système
      if (_filtreSysteme != null && _filtreSysteme != 'Tous') {
        final sys = (item['numero_serie_systeme'] ??
                item['systeme_wylie'] ??
                item['numero_produit'] ??
                '')
            .toString()
            .toLowerCase();
        if (!sys.contains(_filtreSysteme!.toLowerCase())) return false;
      }

      if (query.isEmpty) return true;

      // 3. Recherche textuelle selon le critère choisi
      switch (_critereFiltre) {
        case 'Système':
          final serieSys = (item['numero_serie_systeme'] ?? item['systeme_wylie'] ?? '').toString().toLowerCase();
          final numProduit = (item['numero_produit'] ?? '').toString().toLowerCase();
          final version = (item['version_logiciel'] ?? '').toString().toLowerCase();
          return serieSys.contains(query) || numProduit.contains(query) || version.contains(query);

        case 'Client':
          final client = (item['nom_client'] ?? '').toString().toLowerCase();
          final contact = (item['nom_contact'] ?? '').toString().toLowerCase();
          final commande = (item['numero_commande'] ?? '').toString().toLowerCase();
          final po = (item['numero_bon_commande'] ?? '').toString().toLowerCase();
          final ref = (item['numero_reference'] ?? '').toString().toLowerCase();
          final ville = (item['ville'] ?? item['adresse'] ?? '').toString().toLowerCase();
          return client.contains(query) ||
              contact.contains(query) ||
              commande.contains(query) ||
              po.contains(query) ||
              ref.contains(query) ||
              ville.contains(query);

        case 'Machine':
          final marque = (item['marque'] ?? '').toString().toLowerCase();
          final modele = (item['modele'] ?? '').toString().toLowerCase();
          final type = (item['type_machine'] ?? '').toString().toLowerCase();
          final serie = (item['numero_serie_machine'] ?? '').toString().toLowerCase();
          final unite = (item['numero_unite'] ?? '').toString().toLowerCase();
          return marque.contains(query) ||
              modele.contains(query) ||
              type.contains(query) ||
              serie.contains(query) ||
              unite.contains(query);

        case 'Technicien':
          final tech = (item['nom_technicien'] ?? '').toString().toLowerCase();
          final camion = (item['numero_camion'] ?? '').toString().toLowerCase();
          return tech.contains(query) || camion.contains(query);

        case 'Tous':
        default:
          final fullText = [
            item['nom_client'],
            item['nom_contact'],
            item['numero_commande'],
            item['numero_bon_commande'],
            item['numero_reference'],
            item['numero_rapport'],
            item['type_machine'],
            item['marque'],
            item['modele'],
            item['numero_serie_machine'],
            item['numero_unite'],
            item['numero_serie_systeme'],
            item['systeme_wylie'],
            item['numero_produit'],
            item['nom_technicien'],
            item['numero_camion'],
            item['trouble'],
            item['description_travail'],
            item['notes'],
          ].where((e) => e != null).join(' ').toLowerCase();
          return fullText.contains(query);
      }
    }).toList();
  }

  void _confirmerRestauration(Map<String, dynamic> item) {
    final client = item['nom_client'] ?? 'Client inconnu';
    final commande = item['numero_commande'] ?? item['id'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.unarchive, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Restaurer l\'intervention',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Voulez-vous restaurer le rapport archivé de $client (Commande $commande) ?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ce rapport réapparaîtra dans l\'onglet principal "Interventions Actives". Une fois restauré, vous pourrez l\'éditer ou le supprimer si désiré.',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore_page, size: 18),
            label: const Text('Restaurer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onRestaurer(item);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Rapport pour $client restauré dans l\'agenda actif !'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmerSuppressionApresRestauration(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Archive protégée',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Par mesure de sécurité industrielle, un rapport archivé ne peut pas être effacé directement.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, size: 18, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pour effacer cette archive, veuillez d\'abord la "Restaurer" dans vos interventions actives. Vous pourrez ensuite procéder à sa suppression définitive.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restaurer maintenant'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD1001F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmerRestauration(item);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archives = _interventionsFiltrees;
    final totalArchives = _interventionsArchivees.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.inventory_2, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rapports & Interventions Archivés',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$totalArchives rapport(s) dans le coffre d\'archivage',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF455A64), // Gris bleuté archive
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () {
              widget.onActualiser();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── BANDEAU DE RECHERCHE ET CRITÈRES MULTIPLES ─────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Champ de recherche dynamique
                TextField(
                  controller: _rechercheCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher par ${_critereFiltre.toLowerCase()} (client, N° série, grue, PO, technicien)...',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF455A64)),
                    suffixIcon: _rechercheCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _rechercheCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF455A64), width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),

                // Filtres par critères
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text(
                        'Filtrer par : ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      ...['Tous', 'Système', 'Client', 'Machine', 'Technicien'].map((critere) {
                        final isSel = _critereFiltre == critere;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(critere, style: const TextStyle(fontSize: 11.5)),
                            selected: isSel,
                            selectedColor: const Color(0xFF455A64),
                            labelStyle: TextStyle(
                              color: isSel ? Colors.white : Colors.black87,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _critereFiltre = critere);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── LISTE DES RAPPORTS ARCHIVÉS ──────────────────────────────
          Expanded(
            child: archives.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 72,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            totalArchives == 0
                                ? 'Aucune intervention archivée pour le moment'
                                : 'Aucun rapport archivé ne correspond à votre recherche',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            totalArchives == 0
                                ? 'Vous pouvez archiver des interventions complétées depuis l\'agenda principal en cliquant sur "Archiver".'
                                : 'Essayez d\'ajuster vos filtres de recherche ou sélectionnez le critère "Tous".',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: archives.length,
                    itemBuilder: (context, index) {
                      final item = archives[index];
                      return _buildCarteArchive(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarteArchive(Map<String, dynamic> item) {
    final client = item['nom_client'] ?? 'Client inconnu';
    final commande = item['numero_commande'] ?? item['id'] ?? '--';
    final ref = item['numero_reference'] ?? '';
    final po = item['numero_bon_commande'] ?? '';
    final machine = '${item['type_machine'] ?? ''} ${item['marque'] ?? ''} ${item['modele'] ?? ''}'.trim();
    final serieMachine = item['numero_serie_machine'] ?? '';
    final systeme = item['numero_serie_systeme'] ?? item['systeme_wylie'] ?? '';
    final produit = item['numero_produit'] ?? '';
    final tech = item['nom_technicien'] ?? 'Technicien non assigné';
    final dateInterv = item['date_chantier'] ?? item['created_at']?.toString().substring(0, 10) ?? '--';
    final String? dateArch = item['date_archivage']?.toString().substring(0, 10);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── EN-TÊTE : BADGE ARCHIVÉ + DATES + ACTIONS ────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.archive, size: 12, color: Color(0xFF37474F)),
                          SizedBox(width: 4),
                          Text(
                            'ARCHIVÉ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF37474F),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Date : $dateInterv',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                if (dateArch != null)
                  Text(
                    'Archivé le $dateArch',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ─── NOM DU CLIENT & COMMANDES ─────────────────────────────
            Text(
              client,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Cmd #$commande', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                if (po.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('PO #$po', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                  ),
                if (ref.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Réf #$ref', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  ),
              ],
            ),

            const Divider(height: 20),

            // ─── CRITÈRES : MACHINE, SYSTÈME, TECHNICIEN ───────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colonne Machine & Grue
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.precision_manufacturing, size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          const Text('Machine / Grue :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        machine.isNotEmpty ? machine : '--',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      if (serieMachine.isNotEmpty)
                        Text(
                          'S/N: $serieMachine',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),

                // Colonne Système RaycoWylie
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.memory, size: 14, color: Color(0xFFD1001F)),
                          const SizedBox(width: 4),
                          const Text('Système Rayco :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        systeme.isNotEmpty ? systeme : (produit.isNotEmpty ? produit : '--'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF8B0000)),
                      ),
                      if (produit.isNotEmpty && systeme.isNotEmpty)
                        Text('Produit: $produit', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Ligne Technicien & Durées
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(
                  'Tech : $tech',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (item['duree_chantier'] != null)
                  Text(
                    'Chantier : ${item['duree_chantier']}',
                    style: TextStyle(fontSize: 11, color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // ─── ACTIONS : CONSULTER LE RAPPORT + RESTAURER + SUPPRIMER PROTÉGÉE ───
            Row(
              children: [
                // Consulter le rapport complet
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Consulter Rapport', style: TextStyle(fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF455A64),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RapportDetailScreen(intervention: item),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Restaurer l'archive (Remet dans les interventions actives)
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.unarchive, size: 18),
                    label: const Text('Restaurer', style: TextStyle(fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _confirmerRestauration(item),
                  ),
                ),
                const SizedBox(width: 6),

                // Bouton poubelle protégé (explique qu'il faut restaurer avant d'effacer)
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  tooltip: 'Effacer l\'archive (Nécessite restauration préalable)',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: () => _confirmerSuppressionApresRestauration(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
