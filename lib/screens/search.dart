import 'package:flutter/material.dart';

import '../services/data_service.dart';
import '../widgets/sidebar.dart';
import 'contract.dart';
import 'dashboard.dart';
import 'receipt.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _contractQueryController =
      TextEditingController();
  final TextEditingController _receiptQueryController = TextEditingController();

  @override
  void dispose() {
    _contractQueryController.dispose();
    _receiptQueryController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _contractResults(String query) {
    final normalized = query.trim().toLowerCase();
    final items = DataService.contracts.asMap().entries.toList().reversed;

    final results = <Map<String, dynamic>>[];
    for (final entry in items) {
      final index = entry.key;
      final contract = entry.value;
      final name = (contract['name'] ?? '').toString();
      final mobile = (contract['mobile'] ?? '').toString();
      final date = (contract['date'] ?? '').toString();
      final content = (contract['content'] ?? '').toString();

      if (normalized.isEmpty ||
          name.toLowerCase().contains(normalized) ||
          mobile.toLowerCase().contains(normalized) ||
          date.toLowerCase().contains(normalized) ||
          content.toLowerCase().contains(normalized)) {
        results.add({
          'index': index,
          'name': name,
          'mobile': mobile,
          'date': date,
          'preview': content,
        });
      }
    }
    return results;
  }

  List<Map<String, dynamic>> _receiptResults(String query) {
    final normalized = query.trim().toLowerCase();
    final items = DataService.receipts.asMap().entries.toList().reversed;

    final results = <Map<String, dynamic>>[];
    for (final entry in items) {
      final index = entry.key;
      final receipt = entry.value;
      final name = (receipt['name'] ?? '').toString();
      final mobile = (receipt['mobile'] ?? '').toString();
      final amount = (receipt['amount'] ?? '').toString();
      final date = (receipt['date'] ?? '').toString();

      if (normalized.isEmpty ||
          name.toLowerCase().contains(normalized) ||
          mobile.toLowerCase().contains(normalized) ||
          amount.toLowerCase().contains(normalized) ||
          date.toLowerCase().contains(normalized)) {
        results.add({
          'index': index,
          'name': name,
          'mobile': mobile,
          'amount': amount,
          'date': date,
        });
      }
    }
    return results;
  }

  void _openContractEditor(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Contract(initialHistoryIndex: index),
      ),
    );
  }

  void _openReceiptEditor(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Receipt(initialHistoryIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final contractQuery = _contractQueryController.text;
    final receiptQuery = _receiptQueryController.text;
    final contractResults = _contractResults(contractQuery);
    final receiptResults = _receiptResults(receiptQuery);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 180),
              pageBuilder: (_, __, ___) => const Dashboard(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          );
        }
      },
      child: Scaffold(
        drawer: isMobile
            ? const Drawer(
                child: SafeArea(
                  child: Sidebar(currentIndex: 3),
                ),
              )
            : null,
        body: isMobile
            ? _buildMobileView(contractResults, receiptResults)
            : Row(
                children: [
                  const Sidebar(currentIndex: 3),
                  Expanded(
                    child: Row(
                      children: [
                        // Left: Contracts
                        Expanded(
                          child: _buildContractsPanel(contractResults),
                        ),
                        // Right: Receipts
                        Expanded(
                          child: _buildReceiptsPanel(receiptResults),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMobileView(List<Map<String, dynamic>> contractResults,
      List<Map<String, dynamic>> receiptResults) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              ),
              const Expanded(
                child: Text(
                  'Search Contracts & Receipts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Contracts (${contractResults.length})'),
                const SizedBox(height: 8),
                _buildContractsList(contractResults),
                const SizedBox(height: 24),
                _sectionTitle('Receipts (${receiptResults.length})'),
                const SizedBox(height: 8),
                _buildReceiptsList(receiptResults),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContractsPanel(List<Map<String, dynamic>> contractResults) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.black12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contracts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contractQueryController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search contracts...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _contractQueryController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _contractQueryController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.blue.shade300, width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildContractsList(contractResults),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsPanel(List<Map<String, dynamic>> receiptResults) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.black12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Receipts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _receiptQueryController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search receipts...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _receiptQueryController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _receiptQueryController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.blue.shade300, width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildReceiptsList(receiptResults),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractsList(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.description_outlined,
                  size: 36, color: Colors.grey[300]),
              const SizedBox(height: 10),
              Text(
                'No contracts found',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: results.map((item) {
        final index = item['index'] as int;
        final name = (item['name'] ?? '').toString();
        final mobile = (item['mobile'] ?? '').toString();
        final date = (item['date'] ?? '').toString();

        return GestureDetector(
          onTap: () => _openContractEditor(index),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed Contract' : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mobile: ${mobile.isEmpty ? '-' : mobile}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Date: $date',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReceiptsList(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 36, color: Colors.grey[300]),
              const SizedBox(height: 10),
              Text(
                'No receipts found',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: results.map((item) {
        final index = item['index'] as int;
        final name = (item['name'] ?? '').toString();
        final mobile = (item['mobile'] ?? '').toString();
        final amount = (item['amount'] ?? '').toString();
        final date = (item['date'] ?? '').toString();

        return GestureDetector(
          onTap: () => _openReceiptEditor(index),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name.isEmpty ? 'Unnamed Receipt' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        amount.isEmpty ? '-' : amount,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Mobile: ${mobile.isEmpty ? '-' : mobile}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 4),
                Text(
                  'Date: ${date.isEmpty ? '-' : date}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0D47A1),
      ),
    );
  }
}
