import 'package:flutter/material.dart';
import 'inventaire_donnees.dart';
import 'techniciens_service.dart';

// ==============================================================================
// 📦 ÉCRAN : INVENTAIRE MULTI-CAMIONS (RAYCO WYLIE)
// ==============================================================================
class InventaireScreen extends StatefulWidget {
  const InventaireScreen({super.key});

  @override
  State<InventaireScreen> createState() => _InventaireScreenState();
}

class _InventaireScreenState extends State<InventaireScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _filtreStockIndex = 0; // 0: En stock, 1: Tous, 2: Rupture
  String _camionSelectionne = 'Camion #101'; // 'Camion #101', 'Camion #102', 'Camion #103', 'Tous'

  @override
  void initState() {
    super.initState();
    // Sélectionner automatiquement le camion par défaut
    final techs = TechnicienService.instance.techniciens;
    if (techs.isNotEmpty) {
      _camionSelectionne = InventaireService.normaliserCamion(techs.first.numeroCamion, techs.first.nom);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InventaireService.instance,
      builder: (context, _) {
        final service = InventaireService.instance;

        // 1. Filtrer par camion
        final articlesDuCamion = service.getArticlesPourCamion(_camionSelectionne);

        // 2. Filtrer par stock
        List<ArticleCamion> baseList;
        if (_filtreStockIndex == 0) {
          baseList = articlesDuCamion.where((a) => a.quantite > 0).toList();
        } else if (_filtreStockIndex == 2) {
          baseList = articlesDuCamion.where((a) => a.quantite == 0).toList();
        } else {
          baseList = articlesDuCamion;
        }

        // 3. Filtrer par recherche texte
        final q = _searchQuery.trim().toLowerCase();
        final filteredArticles = q.isEmpty
            ? baseList
            : baseList.where((article) {
                return article.nom.toLowerCase().contains(q) ||
                    article.ref.toLowerCase().contains(q) ||
                    article.entrepot.toLowerCase().contains(q) ||
                    article.camion.toLowerCase().contains(q) ||
                    article.technicien.toLowerCase().contains(q) ||
                    article.notes.toLowerCase().contains(q);
              }).toList();

        final nbEnStock = articlesDuCamion.where((a) => a.quantite > 0).length;
        final nbRupture = articlesDuCamion.where((a) => a.quantite == 0).length;

        final nomTechAssigne = InventaireService.camionVersTech[_camionSelectionne] ?? 'Tous techniciens';
        final tagTech = InventaireService.camionVersLoc[_camionSelectionne] ?? 'RAYCO';

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventaires Camions',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Rayco Wylie • Pièces Tech 1, Tech 2, Tech 3',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD1001F),
            actions: [
              IconButton(
                icon: Icon(
                  service.isCloudSync ? Icons.cloud_done : Icons.cloud_queue,
                  color: service.isCloudSync ? Colors.white : Colors.amberAccent,
                ),
                tooltip: service.cloudStatusMessage,
                onPressed: () => _afficherModalSynchroCloud(context, service),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Recharger inventaires officiels',
                onPressed: () async {
                  final confirmer = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Recharger les inventaires ?'),
                      content: const Text(
                        'Voulez-vous réinitialiser les stocks avec les 3 fichiers CSV originaux (Tech 1, Tech 2, Tech 3) ?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD1001F)),
                          child: const Text('Réinitialiser', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirmer == true) {
                    await service.reinitialiserDepuisFichier();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Inventaires réinitialisés et synchronisés vers le Cloud !'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white),
                tooltip: 'Statistiques inventaires',
                onPressed: () {
                  _afficherStatistiques(context, service);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ─── 1. SÉLECTEUR DE CAMION / TECHNICIEN ─────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCamionChip(
                        camionId: 'Camion #101',
                        label: 'Camion #101',
                        sousTitre: 'David Hestin (TECH 1)',
                        icon: Icons.local_shipping,
                        badgeCount: service.getArticlesPourCamion('Camion #101', seulementEnStock: true).length,
                      ),
                      const SizedBox(width: 8),
                      _buildCamionChip(
                        camionId: 'Camion #102',
                        label: 'Camion #102',
                        sousTitre: 'Pierre-Olivier Patry (TECH 2)',
                        icon: Icons.local_shipping,
                        badgeCount: service.getArticlesPourCamion('Camion #102', seulementEnStock: true).length,
                      ),
                      const SizedBox(width: 8),
                      _buildCamionChip(
                        camionId: 'Camion #103',
                        label: 'Camion #103',
                        sousTitre: 'Jean-François Allie (TECH 3)',
                        icon: Icons.local_shipping,
                        badgeCount: service.getArticlesPourCamion('Camion #103', seulementEnStock: true).length,
                      ),
                      const SizedBox(width: 8),
                      _buildCamionChip(
                        camionId: 'Tous',
                        label: 'Tous les camions',
                        sousTitre: 'Vue globale catalogue',
                        icon: Icons.warehouse,
                        badgeCount: service.articlesEnStock.length,
                      ),
                    ],
                  ),
                ),
              ),

              // ─── 2. BANDEAU RÉSUMÉ DU CAMION SÉLECTIONNÉ ────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border(bottom: BorderSide(color: Colors.indigo.shade100)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.indigo.shade600,
                      child: const Icon(Icons.person, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _camionSelectionne == 'Tous'
                                    ? 'Tous les camions RaycoWylie'
                                    : '$_camionSelectionne • $nomTechAssigne',
                                style: TextStyle(
                                  color: Colors.indigo.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (_camionSelectionne != 'Tous') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tagTech,
                                    style: TextStyle(
                                      color: Colors.indigo.shade900,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '$nbEnStock pièces en stock (${articlesDuCamion.length} références au total)',
                            style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── 3. BARRE DE RECHERCHE ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher réf (11EMA, 11BFL...), description ou mot-clé...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // ─── 4. FILTRES D'ÉTAT DE STOCK (Chips) ─────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('En stock ($nbEnStock)'),
                      selected: _filtreStockIndex == 0,
                      selectedColor: Colors.green.shade100,
                      labelStyle: TextStyle(
                        color: _filtreStockIndex == 0 ? Colors.green.shade900 : Colors.black87,
                        fontWeight: _filtreStockIndex == 0 ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (val) => setState(() => _filtreStockIndex = 0),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Toutes (${articlesDuCamion.length})'),
                      selected: _filtreStockIndex == 1,
                      selectedColor: Colors.indigo.shade100,
                      labelStyle: TextStyle(
                        color: _filtreStockIndex == 1 ? Colors.indigo.shade900 : Colors.black87,
                        fontWeight: _filtreStockIndex == 1 ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (val) => setState(() => _filtreStockIndex = 1),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Rupture ($nbRupture)'),
                      selected: _filtreStockIndex == 2,
                      selectedColor: Colors.orange.shade100,
                      labelStyle: TextStyle(
                        color: _filtreStockIndex == 2 ? Colors.orange.shade900 : Colors.black87,
                        fontWeight: _filtreStockIndex == 2 ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (val) => setState(() => _filtreStockIndex = 2),
                    ),
                  ],
                ),
              ),

              // ─── 5. LISTE DES ARTICLES ──────────────────────────────────
              Expanded(
                child: filteredArticles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Aucun article trouvé pour "$_searchQuery"'
                                    : 'Aucun article dans cette catégorie pour $_camionSelectionne',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredArticles.length,
                        itemBuilder: (context, index) {
                          final item = filteredArticles[index];
                          final hasStock = item.quantite > 0;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  // Icône d'état
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: hasStock
                                        ? Colors.green.shade50
                                        : Colors.grey.shade100,
                                    child: Icon(
                                      hasStock ? Icons.inventory_2 : Icons.inventory_2_outlined,
                                      color: hasStock ? Colors.green.shade700 : Colors.grey,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Détails article
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 6,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.indigo.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.indigo.shade100),
                                              ),
                                              child: Text(
                                                item.ref,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.indigo.shade900,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.red.shade100),
                                              ),
                                              child: Text(
                                                item.camion,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade900,
                                                ),
                                              ),
                                            ),
                                            if (item.technicien.isNotEmpty)
                                              Text(
                                                item.technicien,
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.nom,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        if (item.cout > 0)
                                          Text(
                                            'Coût unit. ERP : ${item.cout.toStringAsFixed(2)} \$',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          ),
                                        if (item.notes.isNotEmpty)
                                          Text(
                                            item.notes,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade800,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Compteur et quantité
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
                                        onPressed: item.quantite > 0
                                            ? () => service.modifierQuantite(item.id, -1)
                                            : null,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 54),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        child: Column(
                                          children: [
                                            Text(
                                              '${item.quantite}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: hasStock ? Colors.green.shade800 : Colors.grey.shade700,
                                              ),
                                            ),
                                            Text(
                                              item.unite,
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 22),
                                        onPressed: () => service.modifierQuantite(item.id, 1),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCamionChip({
    required String camionId,
    required String label,
    required String sousTitre,
    required IconData icon,
    required int badgeCount,
  }) {
    final isSelected = _camionSelectionne == camionId;
    return InkWell(
      onTap: () => setState(() => _camionSelectionne = camionId),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD1001F) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFD1001F) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  sousTitre,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withAlpha(65) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _afficherStatistiques(BuildContext context, InventaireService service) {
    final t1 = service.getArticlesPourCamion('Camion #101');
    final t2 = service.getArticlesPourCamion('Camion #102');
    final t3 = service.getArticlesPourCamion('Camion #103');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2, color: Color(0xFFD1001F)),
            SizedBox(width: 8),
            Text('Inventaire Camions Rayco'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatLigne('Camion #101 (David Hestin)', t1),
            const SizedBox(height: 8),
            _buildStatLigne('Camion #102 (P-O Patry)', t2),
            const SizedBox(height: 8),
            _buildStatLigne('Camion #103 (J-F Allie)', t3),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total catalogue général :', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${service.articles.length} pièces', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Source : Fichiers ERP Visual / SAP RaycoWylie (INVENTAIRE TECH 1, 2, 3)',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatLigne(String titre, List<ArticleCamion> list) {
    final enStock = list.where((a) => a.quantite > 0).length;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$enStock articles en stock', style: const TextStyle(color: Colors.green, fontSize: 11)),
              Text('${list.length} références', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  void _afficherModalSynchroCloud(BuildContext context, InventaireService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool syncing = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: service.isCloudSync
                              ? Colors.green.shade50
                              : Colors.amber.shade50,
                          child: Icon(
                            service.isCloudSync ? Icons.cloud_done : Icons.cloud_queue,
                            color: service.isCloudSync
                                ? Colors.green.shade700
                                : Colors.amber.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gestion Inventaire Cloud',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Base de données Supabase • RaycoWylie',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: service.isCloudSync
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: service.isCloudSync
                              ? Colors.green.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            service.isCloudSync
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: service.isCloudSync
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              service.cloudStatusMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: service.isCloudSync
                                    ? Colors.green.shade900
                                    : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Fonctionnement Cloud :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Chaque technicien a son propre stock indépendant par camion (Camion #101, #102, #103).\n'
                      '• La déduction des pièces lors d\'une clôture de rapport s\'effectue en direct sur le Cloud.\n'
                      '• Si la connexion est indisponible, l\'application fonctionne hors-ligne avec le stockage local.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    if (syncing)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.sync, color: Colors.white),
                          label: const Text(
                            'Synchroniser / Téléverser vers le Cloud',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD1001F),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            setModalState(() => syncing = true);
                            final reussi = await service.synchroniserVersCloud(forcerTeleversement: true);
                            setModalState(() => syncing = false);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    reussi
                                        ? '✅ Synchronisation Cloud réussie !'
                                        : '⚠️ Échec sync Cloud (Consultez la table Supabase).',
                                  ),
                                  backgroundColor: reussi ? Colors.green : Colors.orange,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
