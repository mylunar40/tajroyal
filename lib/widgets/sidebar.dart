import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/dashboard.dart';
import '../screens/contract.dart';
import '../screens/receipt.dart';
import '../screens/search.dart';
import '../screens/login.dart'; // ✅ IMPORTANT

class Sidebar extends StatefulWidget {
  final int currentIndex;

  const Sidebar({super.key, this.currentIndex = 0});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late int selectedIndex;

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Ignore sign-out plugin issues and still return user to login screen.
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.currentIndex;
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      selectedIndex = widget.currentIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),

          _item(Icons.dashboard, "Dashboard", 0),
          _item(Icons.description, "Contract", 1),
          _item(Icons.receipt, "Receipt", 2),
          _item(Icons.search, "Search", 3),

          const Spacer(),

          /// 🔥 LOGOUT
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text("Logout"),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title, int index) {
    bool isSelected = selectedIndex == index;

    return InkWell(
      onTap: () {
        if (selectedIndex == index) {
          return;
        }

        setState(() {
          selectedIndex = index;
        });

        Widget page;
        switch (index) {
          case 0:
            page = const Dashboard();
            break;
          case 1:
            page = const Contract();
            break;
          case 2:
            page = const Receipt();
            break;
          case 3:
            page = const SearchPage();
            break;
          default:
            page = const Dashboard();
        }

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, __, ___) => page, // ✅ FIXED
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      },
      child: Container(
        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : Colors.black,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
