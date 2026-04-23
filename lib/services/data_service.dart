import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DataService {
  // 🔹 Contract List
  static List<Map<String, dynamic>> contracts = [];

  // 🔹 Receipt List
  static List<Map<String, dynamic>> receipts = [];

  // 🔹 Load Contracts from Firebase
  static Future<void> loadContractsFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('contracts')
          .orderBy('createdAt', descending: true)
          .get();

      contracts.clear();
      for (final doc in snapshot.docs) {
        contracts.add({...doc.data(), 'firestoreId': doc.id});
      }
    } catch (e) {
      debugPrint('Error loading contracts from Firebase: $e');
    }
  }

  // 🔹 Load Receipts from Firebase
  static Future<void> loadReceiptsFromFirebase() async {
    try {
      // Receipts are saved with 'timestamp' field (not 'createdAt')
      final snapshot = await FirebaseFirestore.instance
          .collection('receipts')
          .orderBy('timestamp', descending: true)
          .get();

      receipts.clear();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        receipts.add({
          'firestoreId': doc.id,
          'name': data['name'] ?? '',
          'mobile': data['mobile'] ?? '',
          'amount': data['amount'] ?? '',
          'date': data['date'] ?? '',
          'contractNo': data['contractNo'] ?? '',
          'receiptNo': data['receiptNo'] ?? '',
          'fullNo': data['fullNo'] ?? '',
          'bank': data['bank'] ?? '',
          'cheque': data['chequeNo'] ?? '',
          'beingFor': data['beingFor'] ?? '',
          'kd': data['amount'] ?? '',
          'fils': data['fils'] ?? '',
          'sum': data['sum'] ?? '',
          'no': (data['contractNo'] ?? '').toString().replaceAll('CT-', ''),
          'receiverName': data['receiverName'] ?? '',
        });
      }
    } catch (e) {
      debugPrint('Error loading receipts from Firebase: $e');
    }
  }

  // 🔹 Load All Data from Firebase
  static Future<void> loadAllFromFirebase() async {
    await Future.wait([
      loadContractsFromFirebase(),
      loadReceiptsFromFirebase(),
    ]);
  }

  // 🔹 Clear Local Data
  static void clearData() {
    contracts.clear();
    receipts.clear();
  }

  // 🔹 Add Contract
  static void addContract({
    required String name,
    required String date,
  }) {
    contracts.add({
      "name": name,
      "date": date,
    });
  }

  // 🔹 Add Receipt
  static void addReceipt({
    required String name,
    required String amount,
    required String date,
  }) {
    receipts.add({
      "name": name,
      "amount": amount,
      "date": date,
    });
  }
}
