import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Un composant d'en-tête haut de gamme pour RaycoFieldService
/// Couleurs officielles RaycoWylie : Rouge industriel (#D1001F / #B71C1C)
/// Silhouette vectorielle d'une flèche de grue conventionnelle en treillis (Lattice Boom)
class RaycoWylieHeaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onFeuilleDeTemps;
  final VoidCallback? onGestionTechniciens;
  final VoidCallback? onInventaire;
  final VoidCallback? onDepenses;
  final VoidCallback? onArchives;
  final VoidCallback? onBilletsService;
  final VoidCallback? onNouvelleIntervention;
  final VoidCallback? onActualiser;
  final String? sousTitre;
  final int nbArchives;

  const RaycoWylieHeaderAppBar({
    super.key,
    this.onFeuilleDeTemps,
    this.onGestionTechniciens,
    this.onInventaire,
    this.onDepenses,
    this.onArchives,
    this.onBilletsService,
    this.onNouvelleIntervention,
    this.onActualiser,
    this.sousTitre,
    this.nbArchives = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7A000F), // Rouge foncé industriel
            Color(0xFF9E0B1F),
            Color(0xFFBA0C24),
            Color(0xFFD1001F), // Rouge officiel RaycoWylie
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ─── 1. SILHOUETTE FLÈCHE DE GRUE CONVENTIONNELLE (TREILLIS) ────────
          Positioned.fill(
            child: CustomPaint(
              painter: LatticeCraneBoomPainter(),
            ),
          ),

          // ─── 2. LUEUR LUMINEUSE EN DÉGRADÉ SUBTIL ──────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 2,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0xFFFF5252),
                    Colors.white,
                    Color(0xFFFF5252),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ─── 3. CONTENU (LOGO RAYCOWYLIE + ACTIONS) ─────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  // ─── LOGO OFFICIEL RAYCOWYLIE ISOLÉ ANTI-SCINTILLEMENT ──────────
                  const RaycoLogoCapsule(),

                  const SizedBox(width: 8),

                  // ─── TITRE DU MODULE & SOUS-TITRE CHANTIER ─────────────────
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'RaycoFieldService',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD54F),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ROUTE',
                                style: TextStyle(
                                  color: Color(0xFF212121),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          sousTitre ?? 'Systèmes de contrôle & sécurité pour grues',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // ─── BOUTONS D'ACTIONS DU HEADER ────────────────────────────
                  if (onFeuilleDeTemps != null)
                    _buildActionButton(
                      icon: Icons.punch_clock,
                      tooltip: 'Feuille de Temps & Paie',
                      onPressed: onFeuilleDeTemps!,
                    ),
                  if (onGestionTechniciens != null)
                    _buildActionButton(
                      icon: Icons.people_alt,
                      tooltip: 'Équipe & Camions',
                      onPressed: onGestionTechniciens!,
                    ),
                  if (onInventaire != null)
                    _buildActionButton(
                      icon: Icons.local_shipping,
                      tooltip: 'Inventaire Camion',
                      onPressed: onInventaire!,
                    ),
                  if (onDepenses != null)
                    _buildActionButton(
                      icon: Icons.receipt_long,
                      tooltip: 'Comptes de Dépenses',
                      onPressed: onDepenses!,
                    ),
                  if (onArchives != null)
                    _buildActionButton(
                      icon: Icons.inventory_2,
                      tooltip: nbArchives > 0
                          ? 'Archives & Rapports clôturés ($nbArchives)'
                          : 'Archives & Rapports clôturés',
                      onPressed: onArchives!,
                    ),
                  if (onBilletsService != null)
                    _buildActionButton(
                      icon: Icons.support_agent,
                      tooltip: 'Billets de Service Téléphonique (Flowchart)',
                      onPressed: onBilletsService!,
                    ),
                  if (onNouvelleIntervention != null)
                    _buildActionButton(
                      icon: Icons.add_circle,
                      tooltip: 'Ajouter une intervention (Chantier)',
                      onPressed: onNouvelleIntervention!,
                      isHighlight: true,
                    ),
                  if (onActualiser != null)
                    _buildActionButton(
                      icon: Icons.refresh,
                      tooltip: 'Actualiser',
                      onPressed: onActualiser!,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isHighlight
              ? const Color(0xFFFFD54F) // Or haute visibilité industrielle
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onPressed,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: isHighlight
                      ? Colors.amber.shade200
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: isHighlight ? const Color(0xFF1B1B1B) : Colors.white,
                size: isHighlight ? 18 : 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dessinateur vectoriel pour la silhouette d'une flèche de grue conventionnelle
/// en treillis (Lattice Boom Crane) avec haubans, poulies, câble et moufle de levage.
class LatticeCraneBoomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Définition des pinceaux
    final boomSteelPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final chordThickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final cablePaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final hookBlockPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    // ─── GÉOMÉTRIE DE LA FLÈCHE EN TREILLIS (LATTICE BOOM) ────────────────
    // La flèche démarre du pied (en bas vers le centre-droit) et s'élève vers le coin supérieur droit
    final double footX = w * 0.52;
    final double footY = h * 1.05;

    final double tipX = w * 0.94;
    final double tipY = h * 0.12;

    // Épaisseur de la flèche (truss depth) : plus large au milieu, s'amincit au pied et à la tête
    const int segments = 14;

    final List<Offset> upperChord = [];
    final List<Offset> lowerChord = [];

    // Angle directeur de la flèche
    final double angle = math.atan2(tipY - footY, tipX - footX);
    final double perpAngle = angle - (math.pi / 2);

    for (int i = 0; i <= segments; i++) {
      final double t = i / segments;
      final double cx = footX + (tipX - footX) * t;
      final double cy = footY + (tipY - footY) * t;

      // Profil de flèche de grue conventionnelle : bombée au centre (poissonnière)
      final double profileTaper = math.sin(t * math.pi);
      final double halfDepth = (8.0 + 14.0 * profileTaper);

      final double ux = cx + math.cos(perpAngle) * halfDepth;
      final double uy = cy + math.sin(perpAngle) * halfDepth;

      final double lx = cx - math.cos(perpAngle) * halfDepth;
      final double ly = cy - math.sin(perpAngle) * halfDepth;

      upperChord.add(Offset(ux, uy));
      lowerChord.add(Offset(lx, ly));
    }

    // 1. Membrure supérieure (Upper main chord)
    final Path upperPath = Path()..moveTo(upperChord.first.dx, upperChord.first.dy);
    for (int i = 1; i < upperChord.length; i++) {
      upperPath.lineTo(upperChord[i].dx, upperChord[i].dy);
    }
    canvas.drawPath(upperPath, chordThickPaint);

    // 2. Membrure inférieure (Lower main chord)
    final Path lowerPath = Path()..moveTo(lowerChord.first.dx, lowerChord.first.dy);
    for (int i = 1; i < lowerChord.length; i++) {
      lowerPath.lineTo(lowerChord[i].dx, lowerChord[i].dy);
    }
    canvas.drawPath(lowerPath, chordThickPaint);

    // 3. Treillis diagonal en croix (Lattice diagonal lacing & struts)
    for (int i = 0; i < segments; i++) {
      final p1 = upperChord[i];
      final p2 = lowerChord[i];
      final p3 = upperChord[i + 1];
      final p4 = lowerChord[i + 1];

      // Barreau transversal (strut)
      canvas.drawLine(p1, p2, boomSteelPaint);

      // Croisillons en X ou zigzag (lacing)
      canvas.drawLine(p1, p4, boomSteelPaint);
      if (i % 2 == 0) {
        canvas.drawLine(p2, p3, boomSteelPaint);
      }
    }
    // Dernier barreau à la tête
    canvas.drawLine(upperChord.last, lowerChord.last, chordThickPaint);

    // 4. Tête de flèche avec poulies multiples (Sheave head)
    final sheaveCenter = Offset(tipX + 4, tipY - 2);
    canvas.drawCircle(sheaveCenter, 7.0, chordThickPaint);
    canvas.drawCircle(sheaveCenter, 4.0, boomSteelPaint);
    canvas.drawCircle(sheaveCenter, 1.5, chordThickPaint);

    // 5. Câble de retenue / tirant de flèche (Boom hoist pendant lines)
    final aFrameOrigin = Offset(w * 0.40, h * 0.85);
    canvas.drawLine(aFrameOrigin, Offset(tipX - 10, tipY + 4), cablePaint);
    canvas.drawLine(Offset(aFrameOrigin.dx + 4, aFrameOrigin.dy - 6), Offset(tipX - 6, tipY + 6), cablePaint);

    // Structure du portique arrière / A-frame
    canvas.drawLine(aFrameOrigin, Offset(footX, footY), boomSteelPaint);
    canvas.drawLine(Offset(aFrameOrigin.dx + 4, aFrameOrigin.dy - 6), Offset(footX - 12, footY), boomSteelPaint);

    // 6. Câbles de levage verticaux (Hoisting lines) descendant de la tête
    final double hookX = tipX + 5;
    final double hookY = h * 0.68;

    canvas.drawLine(Offset(sheaveCenter.dx - 2, sheaveCenter.dy + 4), Offset(hookX - 2, hookY), cablePaint);
    canvas.drawLine(Offset(sheaveCenter.dx + 2, sheaveCenter.dy + 4), Offset(hookX + 2, hookY), cablePaint);

    // 7. Moufle et crochet de levage lourd (Heavy crane hook block)
    final hookBlockRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(hookX, hookY + 6), width: 14, height: 10),
      const Radius.circular(2),
    );
    canvas.drawRRect(hookBlockRect, hookBlockPaint);

    // Rayures d'avertissement de sécurité sur la moufle
    final stripePaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(hookX - 4, hookY + 2), Offset(hookX - 1, hookY + 10), stripePaint);
    canvas.drawLine(Offset(hookX + 1, hookY + 2), Offset(hookX + 4, hookY + 10), stripePaint);

    // Crochet de grue
    final hookPath = Path()
      ..moveTo(hookX, hookY + 11)
      ..lineTo(hookX, hookY + 15)
      ..cubicTo(hookX, hookY + 21, hookX - 7, hookY + 21, hookX - 7, hookY + 16)
      ..cubicTo(hookX - 7, hookY + 13, hookX - 3, hookY + 13, hookX - 3, hookY + 14);

    final hookOutline = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(hookPath, hookOutline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RaycoLogoCapsule extends StatelessWidget {
  const RaycoLogoCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/images/RaycoWylie-Logo.svg',
          height: 18,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

