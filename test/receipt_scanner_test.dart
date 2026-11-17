import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/depenses_service.dart';
import 'package:rayco_field_service/receipt_scanner_service.dart';

void main() {
  group('Scanner Factures & Reçus Tests', () {
    final scanner = ReceiptScannerService.instance;

    test('1. Reçu Pétro-Canada : Essence, taxes, total, fournisseur, date', () {
      final petroExemple = ReceiptScannerService.exemplesRecus[0];
      final res = scanner.parseReceiptText(petroExemple.texte);

      expect(res.isReadable, isTrue);
      expect(res.confidence, greaterThanOrEqualTo(0.8));
      expect(res.fournisseur, equals('Petro-Canada'));
      expect(res.categorie, equals(CategorieDepense.essence));
      expect(res.montantTotal, equals(164.95));
      expect(res.sousTotal, equals(143.47));
      expect(res.tps, equals(7.17));
      expect(res.tvq, equals(14.31));
      expect(res.date, equals(DateTime(2026, 9, 28)));
      expect(res.numeroCommande, equals('TX-849204'));
      expect(res.description, contains('Petro-Canada'));
    });

    test('2. Reçu St-Hubert : Repas, ventilation pourboire et repas', () {
      final stHubertExemple = ReceiptScannerService.exemplesRecus[1];
      final res = scanner.parseReceiptText(stHubertExemple.texte);

      expect(res.isReadable, isTrue);
      expect(res.fournisseur, equals('St-Hubert'));
      expect(res.categorie, equals(CategorieDepense.repas));
      expect(res.pourboire, equals(5.50));
      expect(res.montantTotal, equals(35.59)); // Repas déduit du grand total
      expect(res.date, equals(DateTime(2026, 9, 28)));
      expect(res.numeroCommande, equals('SH-2026-9912'));
    });

    test('3. Reçu Canadian Tire : Outillage, total, date', () {
      final ctExemple = ReceiptScannerService.exemplesRecus[2];
      final res = scanner.parseReceiptText(ctExemple.texte);

      expect(res.isReadable, isTrue);
      expect(res.fournisseur, equals('Canadian Tire'));
      expect(res.categorie, equals(CategorieDepense.outillage));
      expect(res.montantTotal, equals(87.93));
      expect(res.date, equals(DateTime(2026, 9, 27)));
      expect(res.numeroCommande, equals('CT-481920'));
      expect(res.description, contains('Canadian Tire'));
    });

    test('4. Reçu NAPA Pièces d\'auto : Pièces urgentes', () {
      final napaExemple = ReceiptScannerService.exemplesRecus[4];
      final res = scanner.parseReceiptText(napaExemple.texte);

      expect(res.isReadable, isTrue);
      expect(res.fournisseur, equals('NAPA Pièces d\'auto'));
      expect(res.categorie, equals(CategorieDepense.pieces));
      expect(res.montantTotal, equals(117.85));
      expect(res.date, equals(DateTime(2026, 9, 26)));
    });

    test('5. Reçu flou ou illisible : Alerte et demande de saisie manuelle', () {
      final flouExemple = ReceiptScannerService.exemplesRecus[5];
      final res = scanner.parseReceiptText(flouExemple.texte);

      expect(res.isReadable, isFalse);
      expect(res.confidence, lessThan(0.45));
      expect(res.messageStatut, contains('difficile à lire'));
    });
  });
}
