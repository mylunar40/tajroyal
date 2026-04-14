import 'package:flutter/material.dart';

import '../services/data_service.dart';
import '../widgets/sidebar.dart';
import 'contract.dart';
import 'receipt.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
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
      final date = (contract['date'] ?? '').toString();
      final content = (contract['content'] ?? '').toString();

      if (normalized.isEmpty ||
          name.toLowerCase().contains(normalized) ||
          date.toLowerCase().contains(normalized) ||
          content.toLowerCase().contains(normalized)) {
        results.add({
          'index': index,
          'name': name,
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
    final query = _queryController.text;
    final contractResults = _contractResults(query);
    final receiptResults = _receiptResults(query);

    return Scaffold(
      drawer: isMobile
          ? const Drawer(
              child: SafeArea(
                child: Sidebar(currentIndex: 3),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) const Sidebar(currentIndex: 3),
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      children: [
                        if (isMobile)
                          Builder(
                            builder: (context) => IconButton(
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              icon: const Icon(Icons.menu),
                            ),
                          ),
                        const SizedBox(width: 8),
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
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: _queryController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by name, mobile, amount, date...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                              'Contracts (${contractResults.length})'),
                          const SizedBox(height: 8),
                          if (contractResults.isEmpty)
                            _emptyCard('No contract matches found.')
                          else
                            ...contractResults.map((item) {
                              final index = item['index'] as int;
                              final name = (item['name'] ?? '').toString();
                              final date = (item['date'] ?? '').toString();
                              final preview =
                                  (item['preview'] ?? '').toString();

                              return _resultCard(
                                title: name.isEmpty ? 'Unnamed Contract' : name,
                                subtitle1: 'Date: $date',
                                subtitle2: preview.isEmpty ? '-' : preview,
                                onOpen: () => _openContractEditor(index),
                                onEdit: () => _openContractEditor(index),
                              );
                            }),
                          const SizedBox(height: 16),
                          _sectionTitle('Receipts (${receiptResults.length})'),
                          const SizedBox(height: 8),
                          if (receiptResults.isEmpty)
                            _emptyCard('No receipt matches found.')
                          else
                            ...receiptResults.map((item) {
                              final index = item['index'] as int;
                              final name = (item['name'] ?? '').toString();
                              final mobile = (item['mobile'] ?? '').toString();
                              final amount = (item['amount'] ?? '').toString();
                              final date = (item['date'] ?? '').toString();

                              return _resultCard(
                                title: name.isEmpty ? 'Unnamed Receipt' : name,
                                subtitle1:
                                    'Mobile: ${mobile.isEmpty ? '-' : mobile}',
                                subtitle2:
                                    'Amount: ${amount.isEmpty ? '-' : amount}    Date: ${date.isEmpty ? '-' : date}',
                                onOpen: () => _openReceiptEditor(index),
                                onEdit: () => _openReceiptEditor(index),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }

  Widget _resultCard({
    required String title,
    required String subtitle1,
    required String subtitle2,
    required VoidCallback onOpen,
    required VoidCallback onEdit,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle1),
          const SizedBox(height: 2),
          Text(
            subtitle2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
