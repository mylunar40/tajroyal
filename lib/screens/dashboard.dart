import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/sidebar.dart';
import '../services/data_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final TextEditingController _contractSearchController =
      TextEditingController();
  final TextEditingController _receiptSearchController =
      TextEditingController();
  String _contractSearchQuery = '';
  String _receiptSearchQuery = '';
  String? _selectedContractNo; // Track selected contract
  List<Map<String, dynamic>> _getContracts() {
    final List<Map<String, dynamic>> contracts = [];
    for (final c in DataService.contracts) {
      contracts.add({
        'name': c['name'] ?? '',
        'mobile': c['mobile'] ?? '',
        'contractNo': c['contractNo'] ?? '',
        'type': 'Contract',
        'amount': '-',
        'date': c['date'] ?? '',
      });
    }
    contracts.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
    return contracts;
  }

  List<Map<String, dynamic>> _getReceipts() {
    final List<Map<String, dynamic>> receipts = [];
    for (final r in DataService.receipts) {
      // If contract selected, only show receipts for that contract
      if (_selectedContractNo != null) {
        final contractNo = r['contractNo'] ?? r['no'] ?? '';
        if (contractNo != _selectedContractNo) continue;
      }
      receipts.add({
        'name': r['receivedFrom'] ?? r['name'] ?? '',
        'mobile': r['mobile'] ?? '',
        'receiptNo': r['receiptNo'] ?? r['no'] ?? '',
        'contractNo': r['contractNo'] ?? r['no'] ?? '',
        'type': 'Receipt',
        'amount': 'KD ${r['kd'] ?? r['amount'] ?? '0'}',
        'date': r['date'] ?? '',
      });
    }
    receipts.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
    return receipts;
  }

  List<Map<String, dynamic>> _filteredContracts() {
    final contracts = _getContracts();
    if (_contractSearchQuery.isEmpty) return contracts;
    final q = _contractSearchQuery.toLowerCase();
    return contracts.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final mobile = (item['mobile'] ?? '').toString().toLowerCase();
      final contractNo = (item['contractNo'] ?? '').toString().toLowerCase();
      return name.contains(q) || mobile.contains(q) || contractNo.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _filteredReceipts() {
    final receipts = _getReceipts();
    if (_receiptSearchQuery.isEmpty) return receipts;
    final q = _receiptSearchQuery.toLowerCase();
    return receipts.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final mobile = (item['mobile'] ?? '').toString().toLowerCase();
      final amount = (item['amount'] ?? '').toString().toLowerCase();
      final receiptNo = (item['receiptNo'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          mobile.contains(q) ||
          amount.contains(q) ||
          receiptNo.contains(q);
    }).toList();
  }

  String _todayTotal() {
    final today = DateTime.now();
    final todayStr =
        '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
    double total = 0;
    for (final r in DataService.receipts) {
      final date = (r['date'] ?? '').toString();
      if (date.startsWith(todayStr)) {
        final amt = double.tryParse((r['sum'] ?? r['amount'] ?? '0')
                .toString()
                .replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0;
        total += amt;
      }
    }
    return '${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 2)} KD';
  }

  String _monthTotal() {
    final now = DateTime.now();
    double total = 0;
    for (final r in DataService.receipts) {
      final date = (r['date'] ?? '').toString();
      // format: DD/MM/YYYY
      final parts = date.split('/');
      if (parts.length >= 3) {
        final month = int.tryParse(parts[1]) ?? 0;
        final year = int.tryParse(parts[2].split(' ').first) ?? 0;
        if (month == now.month && year == now.year) {
          final amt = double.tryParse((r['sum'] ?? r['amount'] ?? '0')
                  .toString()
                  .replaceAll(RegExp(r'[^0-9.]'), '')) ??
              0;
          total += amt;
        }
      }
    }
    return '${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 2)} KD';
  }

  List<String> _getLast6MonthNames() {
    final now = DateTime.now();
    final months = <String>[];
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    // Get last 6 months
    for (int i = 5; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add(monthNames[date.month - 1]);
    }
    return months;
  }

  List<int> _getMonthlyContractData() {
    final now = DateTime.now();
    final data = List<int>.filled(6, 0);

    for (final c in DataService.contracts) {
      final date = (c['date'] ?? '').toString();
      final parts = date.split('/');
      if (parts.length >= 3) {
        final month = int.tryParse(parts[1]) ?? 0;
        final year = int.tryParse(parts[2].split(' ').first) ?? 0;

        // Check if this contract is in the last 6 months
        for (int i = 0; i < 6; i++) {
          final checkDate = DateTime(now.year, now.month - (5 - i), 1);
          if (year == checkDate.year && month == checkDate.month) {
            data[i]++;
            break;
          }
        }
      }
    }
    return data;
  }

  List<int> _getMonthlyReceiptData() {
    final now = DateTime.now();
    final data = List<int>.filled(6, 0);

    for (final r in DataService.receipts) {
      final date = (r['date'] ?? '').toString();
      final parts = date.split('/');
      if (parts.length >= 3) {
        final month = int.tryParse(parts[1]) ?? 0;
        final year = int.tryParse(parts[2].split(' ').first) ?? 0;

        // Check if this receipt is in the last 6 months
        for (int i = 0; i < 6; i++) {
          final checkDate = DateTime(now.year, now.month - (5 - i), 1);
          if (year == checkDate.year && month == checkDate.month) {
            data[i]++;
            break;
          }
        }
      }
    }
    return data;
  }

  @override
  void initState() {
    super.initState();
    // Load data from Firebase when dashboard loads
    _loadData();
  }

  Future<void> _loadData() async {
    await DataService.loadAllFromFirebase();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _contractSearchController.dispose();
    _receiptSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    int contractCount = DataService.contracts.length;
    int receiptCount = DataService.receipts.length;

    // Calculate real data from Firebase
    List<int> contractData = _getMonthlyContractData();
    List<int> receiptData = _getMonthlyReceiptData();
    List<String> monthNames = _getLast6MonthNames();

    return Scaffold(
      drawer: isMobile
          ? const Drawer(
              child: SafeArea(
                child: Sidebar(currentIndex: 0),
              ),
            )
          : null,
      body: isMobile
          ? _dashboardContent(
              context,
              isMobile,
              contractCount,
              receiptCount,
              contractData,
              receiptData,
              monthNames,
            )
          : Row(
              children: [
                const Sidebar(currentIndex: 0),
                Expanded(
                  child: _dashboardContent(
                    context,
                    isMobile,
                    contractCount,
                    receiptCount,
                    contractData,
                    receiptData,
                    monthNames,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dashboardContent(
    BuildContext context,
    bool isMobile,
    int contractCount,
    int receiptCount,
    List<int> contractData,
    List<int> receiptData,
    List<String> monthNames,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          child: Row(
            children: [
              if (isMobile)
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu),
                  ),
                ),
              if (isMobile) const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Taj Royal Glass",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}",
                style: const TextStyle(color: Colors.grey),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 20),
                SizedBox(
                  width: 300,
                  height: 38,
                  child: TextField(
                    controller: _contractSearchController,
                    onChanged: (val) => setState(() {
                      _contractSearchQuery = val;
                      _receiptSearchQuery = val;
                    }),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: "Search by name or mobile...",
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey[500]),
                      prefixIcon:
                          Icon(Icons.search, size: 18, color: Colors.grey[500]),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: Colors.grey[100],
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            BorderSide(color: Colors.blue.shade300, width: 1.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.notifications_outlined, color: Colors.grey[600]),
                const SizedBox(width: 14),
                CircleAvatar(
                  backgroundColor: Colors.blue.shade700,
                  radius: 17,
                  child:
                      const Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: Column(
              children: [
                // Fixed top section with KPI cards and charts
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (isMobile)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cardWidth = (constraints.maxWidth - 12) / 2;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: _kpiCard(
                                    "Contracts",
                                    contractCount,
                                    Icons.description,
                                    Colors.blue,
                                    Colors.blueAccent,
                                    isCompact: true,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _kpiCard(
                                    "Receipts",
                                    receiptCount,
                                    Icons.receipt,
                                    Colors.green,
                                    Colors.greenAccent,
                                    isCompact: true,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _kpiCard(
                                    "Today",
                                    _todayTotal(),
                                    Icons.today,
                                    Colors.orange,
                                    Colors.deepOrange,
                                    isCompact: true,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _kpiCard(
                                    "Month",
                                    _monthTotal(),
                                    Icons.bar_chart,
                                    Colors.purple,
                                    Colors.deepPurple,
                                    isCompact: true,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _kpiCard(
                              "Contracts",
                              contractCount,
                              Icons.description,
                              Colors.blue,
                              Colors.blueAccent,
                            ),
                            _kpiCard(
                              "Receipts",
                              receiptCount,
                              Icons.receipt,
                              Colors.green,
                              Colors.greenAccent,
                            ),
                            _kpiCard(
                              "Today",
                              _todayTotal(),
                              Icons.today,
                              Colors.orange,
                              Colors.deepOrange,
                            ),
                            _kpiCard(
                              "Month",
                              _monthTotal(),
                              Icons.bar_chart,
                              Colors.purple,
                              Colors.deepPurple,
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      if (isMobile) ...[
                        SizedBox(
                          height: 250,
                          child: _overviewChart(contractCount, receiptCount),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 250,
                          child: _monthlyChart(
                              contractData, receiptData, monthNames),
                        ),
                      ] else
                        SizedBox(
                          height: 320,
                          child: Row(
                            children: [
                              Expanded(
                                child:
                                    _overviewChart(contractCount, receiptCount),
                              ),
                              Expanded(
                                child: _monthlyChart(
                                    contractData, receiptData, monthNames),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Scrollable Recent Activity section - Split into Contracts & Receipts
                Expanded(
                  child: isMobile
                      ? _mobileActivitySection()
                      : Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              // Left side - Contracts
                              Expanded(
                                child: _card(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            const Text(
                                              "Contracts",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: Color(0xFF1A1A2E)),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${_filteredContracts().length}',
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                "No.",
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                "Name",
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                "Mobile",
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 150,
                                              child: Text(
                                                "Date",
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Column(
                                            children: _filteredContracts()
                                                    .isEmpty
                                                ? [
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 32),
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .description_outlined,
                                                              size: 32,
                                                              color: Colors
                                                                  .grey[300]),
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(
                                                            "No contracts yet",
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey[400],
                                                                fontSize: 13),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ]
                                                : _filteredContracts()
                                                    .take(20)
                                                    .map((item) {
                                                    final contractNo =
                                                        item['contractNo'] ??
                                                            '';
                                                    final isSelected =
                                                        _selectedContractNo ==
                                                            contractNo;
                                                    return InkWell(
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedContractNo =
                                                              isSelected
                                                                  ? null
                                                                  : contractNo;
                                                        });
                                                      },
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 8),
                                                        child: Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isSelected
                                                                ? Colors.blue
                                                                    .withOpacity(
                                                                        0.1)
                                                                : Colors
                                                                    .transparent,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(4),
                                                          child: Row(
                                                            children: [
                                                              SizedBox(
                                                                width: 100,
                                                                child: Text(
                                                                  'CT-$contractNo',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      fontWeight: isSelected
                                                                          ? FontWeight
                                                                              .bold
                                                                          : FontWeight
                                                                              .w600,
                                                                      color: isSelected
                                                                          ? Colors
                                                                              .blue
                                                                          : Colors
                                                                              .black),
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 120,
                                                                child: Text(
                                                                  item['name'] ??
                                                                      '',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color: isSelected
                                                                          ? Colors
                                                                              .blue
                                                                          : Colors
                                                                              .black),
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 120,
                                                                child: Text(
                                                                  item['mobile'] ??
                                                                      '',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color: isSelected
                                                                          ? Colors
                                                                              .blue
                                                                          : Colors
                                                                              .black),
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 150,
                                                                child: Text(
                                                                  item['date'] ??
                                                                      '',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color: isSelected
                                                                          ? Colors
                                                                              .blue
                                                                          : Colors
                                                                              .black),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Right side - Receipts
                              Expanded(
                                child: _card(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Text(
                                                  "Receipts",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                      color: Color(0xFF1A1A2E)),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '${_filteredReceipts().length}',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12),
                                                ),
                                              ],
                                            ),
                                            if (_selectedContractNo != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4),
                                                child: Text(
                                                  'Contract: CT-$_selectedContractNo',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.blue,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                "Receipt No.",
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                "Name",
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                "Mobile",
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                "Amount",
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 150,
                                              child: Text(
                                                "Date",
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Column(
                                            children: _filteredReceipts()
                                                    .isEmpty
                                                ? [
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 32),
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .receipt_long_outlined,
                                                              size: 32,
                                                              color: Colors
                                                                  .grey[300]),
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(
                                                            "No receipts yet",
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey[400],
                                                                fontSize: 13),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ]
                                                : _filteredReceipts()
                                                    .take(20)
                                                    .map((item) {
                                                    return Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 8),
                                                      child: Row(
                                                        children: [
                                                          SizedBox(
                                                            width: 100,
                                                            child: Text(
                                                              '${item['contractNo'] ?? ''}/${item['receiptNo'] ?? ''}',
                                                              style: const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 120,
                                                            child: Text(
                                                              item['name'] ??
                                                                  '',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 120,
                                                            child: Text(
                                                              item['mobile'] ??
                                                                  '',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 120,
                                                            child: Text(
                                                              item['amount'] ??
                                                                  '-',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 150,
                                                            child: Text(
                                                              item['date'] ??
                                                                  '',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                          ),
                                        ),
                                      ),
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
          ),
        ),
      ],
    );
  }

  /// Mobile-only activity section with tabs
  Widget _mobileActivitySection() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              labelColor: Colors.blue.shade700,
              unselectedLabelColor: Colors.grey[500],
              indicatorColor: Colors.blue.shade700,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.description_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text('Contracts (${_filteredContracts().length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text('Receipts (${_filteredReceipts().length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Contracts tab
                _mobileContractsList(),
                // Receipts tab
                _mobileReceiptsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileContractsList() {
    final contracts = _filteredContracts();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: _card(
        child: contracts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 36, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Text('No contracts yet',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 13)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: contracts.take(20).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = contracts[i];
                  final contractNo = item['contractNo'] ?? '';
                  final isSelected = _selectedContractNo == contractNo;
                  return InkWell(
                    onTap: () => setState(() {
                      _selectedContractNo = isSelected ? null : contractNo;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.withOpacity(0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'CT-$contractNo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.blue.shade900,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              item['name'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              item['mobile'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              item['date'] ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _mobileReceiptsList() {
    final receipts = _filteredReceipts();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: _card(
        child: receipts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 36, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Text('No receipts yet',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 13)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: receipts.take(20).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = receipts[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${item['contractNo'] ?? ''}/${item['receiptNo'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0D47A1),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            item['name'] ?? '',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item['amount'] ?? '-',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            item['date'] ?? '',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _overviewChart(int contractCount, int receiptCount) {
    return _card(
      child: Column(
        children: [
          const Text(
            "Overview",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  swapAnimationDuration: const Duration(milliseconds: 800),
                  swapAnimationCurve: Curves.easeInOut,
                  PieChartData(
                    centerSpaceRadius: 52,
                    sectionsSpace: 2,
                    sections: [
                      PieChartSectionData(
                        value:
                            contractCount == 0 ? 1 : contractCount.toDouble(),
                        color: Colors.blue,
                        title: "",
                      ),
                      PieChartSectionData(
                        value: receiptCount == 0 ? 1 : receiptCount.toDouble(),
                        color: Colors.green,
                        title: "",
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${contractCount + receiptCount}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text("Total"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyChart(
      List<int> contractData, List<int> receiptData, List<String> monthNames) {
    return _card(
      child: Column(
        children: [
          const Text(
            "Monthly Report",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                alignment: BarChartAlignment.spaceAround,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 &&
                            value.toInt() < monthNames.length) {
                          return Text(monthNames[value.toInt()]);
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barGroups: List.generate(6, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: contractData[i].toDouble(),
                        color: Colors.blue,
                        width: 8,
                      ),
                      BarChartRodData(
                        toY: receiptData[i].toDouble(),
                        color: Colors.green,
                        width: 8,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// KPI CARD
  Widget _kpiCard(
    String title,
    dynamic value,
    IconData icon,
    Color c1,
    Color c2, {
    bool isCompact = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        width: isCompact ? double.infinity : 190,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c1, c2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: c1.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text("$value",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// CARD
  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
