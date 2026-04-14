class DataService {
  // 🔹 Contract List
  static List<Map<String, dynamic>> contracts = [];

  // 🔹 Receipt List
  static List<Map<String, dynamic>> receipts = [];

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
