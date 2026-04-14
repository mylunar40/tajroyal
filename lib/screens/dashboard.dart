import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/sidebar.dart';
import '../services/data_service.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    int contractCount = DataService.contracts.length;
    int receiptCount = DataService.receipts.length;

    List<int> contractData = [2, 5, 3, 6, 4, 7];
    List<int> receiptData = [1, 3, 2, 5, 3, 6];

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
                  width: 220,
                  height: 36,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const TextField(
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: "Search...",
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                const Icon(Icons.notifications),
                const SizedBox(width: 15),
                const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                        isCompact: isMobile,
                      ),
                      _kpiCard(
                        "Receipts",
                        receiptCount,
                        Icons.receipt,
                        Colors.green,
                        Colors.greenAccent,
                        isCompact: isMobile,
                      ),
                      _kpiCard(
                        "Today",
                        "0 KD",
                        Icons.today,
                        Colors.orange,
                        Colors.deepOrange,
                        isCompact: isMobile,
                      ),
                      _kpiCard(
                        "Month",
                        "0 KD",
                        Icons.bar_chart,
                        Colors.purple,
                        Colors.deepPurple,
                        isCompact: isMobile,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isMobile) ...[
                    SizedBox(
                      height: 290,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 520,
                          child: _overviewChart(contractCount, receiptCount),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 290,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 520,
                          child: _monthlyChart(contractData, receiptData),
                        ),
                      ),
                    ),
                  ] else
                    SizedBox(
                      height: 320,
                      child: Row(
                        children: [
                          Expanded(
                            child: _overviewChart(contractCount, receiptCount),
                          ),
                          Expanded(
                            child: _monthlyChart(contractData, receiptData),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Recent Activity",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text("Name")),
                              DataColumn(label: Text("Type")),
                              DataColumn(label: Text("Amount")),
                              DataColumn(label: Text("Date")),
                            ],
                            rows: const [
                              DataRow(cells: [
                                DataCell(Text("Ali")),
                                DataCell(Text("Contract")),
                                DataCell(Text("-")),
                                DataCell(Text("Today")),
                              ]),
                              DataRow(cells: [
                                DataCell(Text("Ahmed")),
                                DataCell(Text("Receipt")),
                                DataCell(Text("500 KD")),
                                DataCell(Text("Today")),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _overviewChart(int contractCount, int receiptCount) {
    return _card(
      child: Column(
        children: [
          const Text(
            "Overview",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
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

  Widget _monthlyChart(List<int> contractData, List<int> receiptData) {
    return _card(
      child: Column(
        children: [
          const Text(
            "Monthly Report",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
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
                        const List<String> months = [
                          "Jan",
                          "Feb",
                          "Mar",
                          "Apr",
                          "May",
                          "Jun"
                        ];
                        if (value.toInt() >= 0 &&
                            value.toInt() < months.length) {
                          return Text(months[value.toInt()]);
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
        width: isCompact ? 150 : 180,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c1, c2]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white)),
                Text("$value",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 5),
        ],
      ),
      child: child,
    );
  }
}
