import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const HIPLApp());
}

class HIPLApp extends StatelessWidget {
  const HIPLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HIPL BSB CONTROL',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const LoginGate(),
    );
  }
}

// ============================================================
// LOGIN / BLOCK SYSTEM
// Firebase collection:
// app_users/{LOGIN_ID}
// fields: pin, active, name, role, can_start_download, allowed_districts
// Example:
// app_users/SOURAV_ADMIN = {
//   pin: "1234", active: true, name: "Sourav", role: "admin",
//   can_start_download: true, allowed_districts: ["ALL"]
// }
// To block any APK user: set active = false in Firebase.
// ============================================================

class AppUser {
  final String loginId;
  final String name;
  final String role;
  final bool canStartDownload;
  final List<String> allowedDistricts;

  const AppUser({
    required this.loginId,
    required this.name,
    required this.role,
    required this.canStartDownload,
    required this.allowedDistricts,
  });

  bool canUseDistrict(String district) {
    return allowedDistricts.contains('ALL') ||
        allowedDistricts.contains(district);
  }
}

class LoginGate extends StatefulWidget {
  const LoginGate({super.key});

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  final TextEditingController loginIdController = TextEditingController();
  final TextEditingController pinController = TextEditingController();
  bool loading = false;
  String message = '';

  @override
  void dispose() {
    loginIdController.dispose();
    pinController.dispose();
    super.dispose();
  }

  Future<void> doLogin() async {
    final loginId = loginIdController.text.trim().toUpperCase();
    final pin = pinController.text.trim();

    if (loginId.isEmpty || pin.isEmpty) {
      setState(() => message = 'Login ID and PIN required');
      return;
    }

    setState(() {
      loading = true;
      message = 'Checking access...';
    });

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('app_users')
              .doc(loginId)
              .get();
      if (!doc.exists) {
        setState(() => message = 'User not found / not approved');
        return;
      }

      final data = doc.data() ?? {};
      final active = data['active'] == true;
      final firebasePin = (data['pin'] ?? '').toString();

      if (!active) {
        setState(() => message = 'This APK access is blocked by admin');
        return;
      }

      if (pin != firebasePin) {
        setState(() => message = 'Wrong PIN');
        return;
      }

      final allowedRaw = data['allowed_districts'];
      final allowedDistricts =
          allowedRaw is List
              ? allowedRaw
                  .map((e) => e.toString().trim().toUpperCase())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : <String>['ALL'];

      await doc.reference.set({
        'last_login': FieldValue.serverTimestamp(),
        'last_login_text': DateTime.now().toString(),
      }, SetOptions(merge: true));

      final user = AppUser(
        loginId: loginId,
        name: (data['name'] ?? loginId).toString(),
        role: (data['role'] ?? 'user').toString(),
        canStartDownload: data['can_start_download'] != false,
        allowedDistricts: allowedDistricts.isEmpty ? ['ALL'] : allowedDistricts,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomePage(currentUser: user)),
      );
    } catch (e) {
      setState(() => message = 'Login error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget panel({required Widget child, Color color = Colors.greenAccent}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color, width: 1.4),
        boxShadow: [BoxShadow(color: color.withOpacity(0.22), blurRadius: 24)],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const MatrixBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: panel(
                  color: Colors.pinkAccent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'HIPL',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'BSB SECURE APK LOGIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: loginIdController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Login ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                        onSubmitted: (_) => doLogin(),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: loading ? null : doLogin,
                          icon:
                              loading
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.login),
                          label: Text(loading ? 'CHECKING...' : 'LOGIN'),
                        ),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Admin can block this app anytime from Firebase app_users collection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatefulWidget {
  final AppUser currentUser;
  const HomePage({super.key, required this.currentUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String selectedDistrict = 'DAKSHIN_DINAJPUR';
  String selectedSeason = 'RABI 2025-2026';
  String downloadMode = 'FULL_DISTRICT';

  final TextEditingController otpController = TextEditingController();
  final Set<String> selectedBlocks = {};

  final List<String> districts = const [
    'DAKSHIN_DINAJPUR',
    'UTTAR_DINAJPUR',
    'JALPAIGURI',
  ];

  final Map<String, List<String>> districtBlocks = const {
    'DAKSHIN_DINAJPUR': [
      'BALURGHAT',
      'BANSIHARI',
      'GANGARAMPUR',
      'HARIRAMPUR',
      'HILI',
      'KUMARGANJ',
      'KUSHMANDI',
      'TAPAN',
    ],
    'UTTAR_DINAJPUR': [
      'CHOPRA',
      'GOALPOKHAR_I',
      'GOALPOKHAR_II',
      'HEMTABAD',
      'ISLAMPUR',
      'ITAHAR',
      'KALIAGANJ',
      'KARANDIGHI',
      'RAIGANJ',
    ],
    'JALPAIGURI': [
      'ALIPURDUAR_I',
      'ALIPURDUAR_II',
      'DHUPGURI',
      'FALAKATA',
      'JALPAIGURI_SADAR',
      'KALCHINI',
      'KUMARGRAM',
      'MAL',
      'MAYNAGURI',
      'MADARIHAT',
      'NAGRAKATA',
      'RAJGANJ',
    ],
  };

  List<String> get currentBlocks => districtBlocks[selectedDistrict] ?? [];
  String seasonDoc(String season) =>
      season
          .replaceAll(' ', '_')
          .replaceAll('-', '_')
          .replaceAll('/', '_')
          .toUpperCase();
  String cleanName(String value) => value.replaceAll('_', ' ');

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  List<dynamic> asList(dynamic value) => value is List ? value : [];

  num readNum(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value;
      if (value is String) return num.tryParse(value.replaceAll('%', '')) ?? 0;
    }
    return 0;
  }

  @override
  void dispose() {
    otpController.dispose();
    super.dispose();
  }

  Future<void> checkUserStillActive() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('app_users')
            .doc(widget.currentUser.loginId)
            .get();
    final active = doc.exists && (doc.data()?['active'] == true);
    if (!active && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginGate()),
        (_) => false,
      );
    }
  }

  Future<void> openAnyDesk() async {
    final links = [
      Uri.parse('anydesk://'),
      Uri.parse('market://details?id=com.anydesk.anydeskandroid'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=com.anydesk.anydeskandroid',
      ),
    ];
    for (final uri in links) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AnyDesk open holo na')));
  }

  Future<void> sendOtp() async {
    final otp = otpController.text.trim();
    if (otp.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter OTP first')));
      return;
    }
    await checkUserStillActive();
    await FirebaseFirestore.instance.collection('otp_commands').add({
      'otp': otp,
      'processed': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': widget.currentUser.loginId,
    });
    otpController.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP injected to laptop node')),
    );
  }

  Future<void> checkAgent() async {
    await checkUserStillActive();
    await FirebaseFirestore.instance.collection('commands').add({
      'agent_id': 'HIPL_LAPTOP_01',
      'action': 'PING',
      'processed': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': widget.currentUser.loginId,
    });
  }

  Future<void> refreshNow() async {
    await checkUserStillActive();
    setState(() {});
    await checkAgent();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refreshing live status...')));
  }

  Future<void> stopDownload() async {
    await checkUserStillActive();
    await FirebaseFirestore.instance
        .collection('agents')
        .doc('HIPL_LAPTOP_01')
        .set({
          'status': 'STOP_REQUESTED',
          'download_status': 'STOP_REQUESTED',
          'message': 'Stop requested from APK',
          'last_update': DateTime.now().toString(),
        }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('commands').add({
      'agent_id': 'HIPL_LAPTOP_01',
      'action': 'STOP_DOWNLOAD',
      'processed': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': widget.currentUser.loginId,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop request sent to laptop agent')),
    );
  }

  Future<void> startDownload() async {
    await checkUserStillActive();

    if (!widget.currentUser.canStartDownload) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not allowed to start download')),
      );
      return;
    }
    if (!widget.currentUser.canUseDistrict(selectedDistrict)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This district is not allowed for your login'),
        ),
      );
      return;
    }
    if (downloadMode == 'SELECT_BLOCKS' && selectedBlocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one block')),
      );
      return;
    }

    // Instantly show OTP box in APK while laptop agent prepares portal.
    await FirebaseFirestore.instance
        .collection('agents')
        .doc('HIPL_LAPTOP_01')
        .set({
          'otp_required': true,
          'otp_consumed': false,
          'login_success': false,
          'current_district': selectedDistrict,
          'current_season': selectedSeason,
          'download_status': 'REQUEST_SENT',
          'message': 'Download command sent. OTP box ready in APK.',
          'last_update': DateTime.now().toString(),
        }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('commands').add({
      'agent_id': 'HIPL_LAPTOP_01',
      'action': 'START_DOWNLOAD',
      'district': selectedDistrict,
      'season': selectedSeason,
      'download_mode': downloadMode,
      'selected_blocks': selectedBlocks.toList(),
      'processed': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': widget.currentUser.loginId,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          downloadMode == 'FULL_DISTRICT'
              ? 'FULL DISTRICT JOB STARTED'
              : '${selectedBlocks.length} SELECTED BLOCK JOB STARTED',
        ),
      ),
    );
  }

  Widget cyberPanel({required Widget child, Color color = Colors.greenAccent}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget cyberButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Color color = Colors.greenAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 14)],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: color,
          disabledForegroundColor: Colors.white38,
          disabledBackgroundColor: Colors.black54,
          side: BorderSide(color: onPressed == null ? Colors.white24 : color),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget buildHeader() {
    return cyberPanel(
      color: Colors.greenAccent,
      child: Column(
        children: [
          const Text(
            'HIPL',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'HOOGHLY INFOTECH PRIVATE LIMITED',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Logged in: ${widget.currentUser.name} (${widget.currentUser.role})',
            style: const TextStyle(
              color: Colors.pinkAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'BSB CYBER OPERATIONS CONSOLE',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAgentStatus(Map<String, dynamic> agent) {
    final status = agent['status']?.toString() ?? 'OFFLINE';
    final message = agent['message']?.toString() ?? '-';
    final internet = agent['internet']?.toString() ?? '-';
    final downloadStatus = agent['download_status']?.toString() ?? '-';
    final progress = agent['progress_percent']?.toString() ?? '-';
    final speed = agent['speed']?.toString() ?? '-';
    final currentBlock = agent['current_block']?.toString() ?? '-';
    final completed = agent['completed_blocks']?.toString() ?? '0';
    final total = agent['total_blocks']?.toString() ?? '0';
    final failed = agent['failed_blocks']?.toString() ?? '0';
    final lastUpdate = agent['last_update']?.toString() ?? '-';

    Color statusColor = Colors.redAccent;
    if (status == 'ONLINE' ||
        status == 'READY' ||
        status == 'RUNNING' ||
        status == 'COMPLETED')
      statusColor = Colors.greenAccent;
    if (status == 'WARNING' || status == 'NO INTERNET')
      statusColor = Colors.orangeAccent;

    return cyberPanel(
      color: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'NODE STATUS : $status',
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MESSAGE : $message',
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            'INTERNET : $internet',
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            'DOWNLOAD : $downloadStatus  $progress',
            style: const TextStyle(color: Colors.greenAccent),
          ),
          Text(
            'CURRENT BLOCK : $currentBlock',
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            'BLOCKS : $completed / $total   FAILED : $failed',
            style: const TextStyle(color: Colors.white),
          ),
          Text('SPEED : $speed', style: const TextStyle(color: Colors.white)),
          Text(
            'LAST UPDATE : $lastUpdate',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: parseProgress(progress),
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  double? parseProgress(String progress) {
    final n = double.tryParse(progress.replaceAll('%', '').trim());
    if (n == null) return null;
    return (n / 100).clamp(0.0, 1.0);
  }

  Widget buildControls() {
    final allowedDistricts =
        districts.where((d) => widget.currentUser.canUseDistrict(d)).toList();
    if (!allowedDistricts.contains(selectedDistrict) &&
        allowedDistricts.isNotEmpty) {
      selectedDistrict = allowedDistricts.first;
      selectedBlocks.clear();
    }

    return cyberPanel(
      color: Colors.cyanAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MISSION CONTROL',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          cyberButton(
            label: 'UNLOCK LAPTOP / OPEN ANYDESK',
            icon: Icons.lock_open,
            onPressed: openAnyDesk,
            color: Colors.orangeAccent,
          ),
          DropdownButtonFormField<String>(
            value: selectedDistrict,
            dropdownColor: Colors.black,
            decoration: const InputDecoration(
              labelText: 'District',
              border: OutlineInputBorder(),
            ),
            items:
                allowedDistricts
                    .map(
                      (district) => DropdownMenuItem(
                        value: district,
                        child: Text(cleanName(district)),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null)
                setState(() {
                  selectedDistrict = value;
                  selectedBlocks.clear();
                });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedSeason,
            dropdownColor: Colors.black,
            decoration: const InputDecoration(
              labelText: 'Season',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'KHARIF 2025',
                child: Text('KHARIF 2025'),
              ),
              DropdownMenuItem(
                value: 'RABI 2025-2026',
                child: Text('RABI 2025-2026'),
              ),
            ],
            onChanged:
                (value) =>
                    value == null
                        ? null
                        : setState(() => selectedSeason = value),
          ),
          const SizedBox(height: 12),
          buildDownloadMode(),
          cyberButton(
            label: 'CHECK LAPTOP AGENT',
            icon: Icons.wifi,
            onPressed: checkAgent,
            color: Colors.purpleAccent,
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: refreshNow,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: stopDownload,
                    icon: const Icon(Icons.stop_circle, size: 18),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          cyberButton(
            label: 'VIEW FULL SUMMARY',
            icon: Icons.analytics,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => FullSummaryPage(
                          seasonId: seasonDoc(selectedSeason),
                          district: selectedDistrict,
                        ),
                  ),
                ),
            color: Colors.amberAccent,
          ),
          cyberButton(
            label:
                widget.currentUser.canStartDownload
                    ? (downloadMode == 'FULL_DISTRICT'
                        ? 'START FULL DISTRICT DOWNLOAD'
                        : 'START SELECTED BLOCK DOWNLOAD')
                    : 'DOWNLOAD BLOCKED FOR THIS LOGIN',
            icon: Icons.rocket_launch,
            onPressed:
                widget.currentUser.canStartDownload ? startDownload : null,
            color: Colors.greenAccent,
          ),
        ],
      ),
    );
  }

  Widget buildDownloadMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DOWNLOAD MODE',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        RadioListTile<String>(
          value: 'FULL_DISTRICT',
          groupValue: downloadMode,
          activeColor: Colors.greenAccent,
          title: const Text('FULL DISTRICT'),
          onChanged: (value) => setState(() => downloadMode = value!),
        ),
        RadioListTile<String>(
          value: 'SELECT_BLOCKS',
          groupValue: downloadMode,
          activeColor: Colors.greenAccent,
          title: const Text('SELECT BLOCKS'),
          onChanged: (value) => setState(() => downloadMode = value!),
        ),
        if (downloadMode == 'SELECT_BLOCKS') ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      () =>
                          setState(() => selectedBlocks.addAll(currentBlocks)),
                  child: const Text('SELECT ALL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => selectedBlocks.clear()),
                  child: const Text('CLEAR'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                currentBlocks.map((block) {
                  final selected = selectedBlocks.contains(block);
                  return FilterChip(
                    label: Text(cleanName(block)),
                    selected: selected,
                    selectedColor: Colors.green.shade700,
                    checkmarkColor: Colors.white,
                    onSelected:
                        (value) => setState(
                          () =>
                              value
                                  ? selectedBlocks.add(block)
                                  : selectedBlocks.remove(block),
                        ),
                  );
                }).toList(),
          ),
        ],
      ],
    );
  }

  Widget buildOtpOverlay(Map<String, dynamic> agent) {
    final otpRequired = agent['otp_required'] == true;
    final loginSuccess = agent['login_success'] == true;
    if (!otpRequired || loginSuccess) return const SizedBox.shrink();

    return Positioned(
      left: 14,
      right: 14,
      top: 78,
      child: CyberBlink(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.pinkAccent, width: 2.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.pinkAccent.withOpacity(0.55),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'OTP REQUIRED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'ENTER PORTAL OTP',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                cyberButton(
                  label: 'INJECT OTP TO PORTAL',
                  icon: Icons.password,
                  onPressed: sendOtp,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTerminal(Map<String, dynamic> agent) {
    final lines = [
      '[BOOT] HIPL CYBER NODE INITIALIZED',
      '[USER] ${widget.currentUser.loginId}',
      '[NODE] ${agent['status'] ?? 'OFFLINE'}',
      '[NET] ${agent['internet'] ?? '-'}',
      '[MISSION] ${agent['download_status'] ?? '-'} ${agent['progress_percent'] ?? ''}',
      '[TARGET] ${agent['current_district'] ?? selectedDistrict} / ${agent['current_season'] ?? selectedSeason}',
      '[BLOCK] ${agent['current_block'] ?? '-'}',
      '[FLOW] ${agent['completed_blocks'] ?? 0}/${agent['total_blocks'] ?? 0} FAILED:${agent['failed_blocks'] ?? 0}',
      if (agent['otp_required'] == true)
        '[AUTH] OTP REQUIRED - WAITING FOR MOBILE INPUT',
      if (agent['login_success'] == true) '[AUTH] LOGIN SUCCESSFULLY COMPLETED',
      '[HIPL] SECURE AUTOMATION ACTIVE',
    ];

    return cyberPanel(
      color: Colors.greenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE TERMINAL',
            style: TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 135,
            child: ListView.builder(
              reverse: true,
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines.reversed.toList()[index];
                return Text(
                  line,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAnalytics(Map<String, dynamic> agent) {
    final districtSummary = asMap(agent['district_summary']);
    final blockSummary = asMap(agent['block_summary']);
    final duplicateEpic = asList(agent['duplicate_epic_crop_location']);
    final duplicatePlot = asList(agent['duplicate_plot']);
    final duplicateBank = asList(agent['duplicate_bank']);
    final createdUserSummary = asMap(agent['created_user_summary']);
    final duplicateFallback = asList(agent['duplicate_summary']);

    final totalApplication = readNum(districtSummary, [
      'total_application',
      'total_applications',
      'application',
      'applications',
    ]);
    final totalHector = readNum(districtSummary, [
      'total_hector',
      'hector',
      'total_area_hector',
    ]);

    return cyberPanel(
      color: Colors.greenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FINAL SUMMARY / INTELLIGENCE',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: miniStat(
                  'APPLICATION',
                  totalApplication.toStringAsFixed(0),
                  Icons.description,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: miniStat(
                  'HECTOR',
                  totalHector.toStringAsFixed(2),
                  Icons.landscape,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          cyberButton(
            label: 'STATE SUMMARY (SCALABLE)',
            icon: Icons.public,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => StateSummaryPage(
                          seasonId: seasonDoc(selectedSeason),
                        ),
                  ),
                ),
            color: Colors.amberAccent,
          ),
          cyberButton(
            label: 'DISTRICT SUMMARY (SCALABLE)',
            icon: Icons.location_city,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => DistrictSummaryPage(
                          seasonId: seasonDoc(selectedSeason),
                        ),
                  ),
                ),
            color: Colors.blueAccent,
          ),
          cyberButton(
            label: 'BLOCK WISE REPORT',
            icon: Icons.table_chart,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlockReportPage(blockSummary: blockSummary),
                  ),
                ),
            color: Colors.cyanAccent,
          ),
          cyberButton(
            label: 'SCALABLE BLOCK COLLECTION',
            icon: Icons.grid_view,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => BlockCollectionPage(
                          seasonId: seasonDoc(selectedSeason),
                          district: selectedDistrict,
                        ),
                  ),
                ),
            color: Colors.lightBlueAccent,
          ),
          cyberButton(
            label:
                'DUPLICATE EPIC (${duplicateEpic.isNotEmpty ? duplicateEpic.length : duplicateFallback.length})',
            icon: Icons.person_search,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => DuplicateReportPage(
                          title: 'DUPLICATE EPIC + CROP + LOCATION',
                          items:
                              duplicateEpic.isNotEmpty
                                  ? duplicateEpic
                                  : duplicateFallback,
                        ),
                  ),
                ),
            color: Colors.orangeAccent,
          ),
          cyberButton(
            label: 'DUPLICATE PLOT (${duplicatePlot.length})',
            icon: Icons.map,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => DuplicateReportPage(
                          title: 'DUPLICATE MOUZA + JL + PLOT',
                          items: duplicatePlot,
                        ),
                  ),
                ),
            color: Colors.pinkAccent,
          ),
          cyberButton(
            label: 'DUPLICATE BANK (${duplicateBank.length})',
            icon: Icons.account_balance,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => DuplicateReportPage(
                          title: 'DUPLICATE BANK ACCOUNT + IFSC',
                          items: duplicateBank,
                        ),
                  ),
                ),
            color: Colors.deepPurpleAccent,
          ),
          cyberButton(
            label: 'CREATED USER PROFILE (${createdUserSummary.length})',
            icon: Icons.manage_accounts,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => CreatedUserReportPage(
                          userSummary: createdUserSummary,
                        ),
                  ),
                ),
            color: Colors.lightGreenAccent,
          ),
          cyberButton(
            label: 'EXPORT REPORT',
            icon: Icons.file_download,
            onPressed:
                () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Export folder: ${agent['export_folder'] ?? 'Laptop Downloads folder'}',
                    ),
                  ),
                ),
            color: Colors.tealAccent,
          ),
        ],
      ),
    );
  }

  Widget miniStat(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.greenAccent),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentStream =
        FirebaseFirestore.instance
            .collection('agents')
            .doc('HIPL_LAPTOP_01')
            .snapshots();

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: agentStream,
        builder: (context, snapshot) {
          Map<String, dynamic> agent = {};
          if (snapshot.hasData && snapshot.data!.exists)
            agent = snapshot.data!.data() as Map<String, dynamic>;

          return Stack(
            children: [
              const MatrixBackground(),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    buildHeader(),
                    buildAgentStatus(agent),
                    buildTerminal(agent),
                    buildControls(),
                    const SizedBox(height: 22),
                    const Text(
                      'Developed by HIPL',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.greenAccent),
                    ),
                  ],
                ),
              ),
              buildOtpOverlay(agent),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// FULL SUMMARY PAGE
// Home page stays light. Heavy summary/report buttons open here.
// ============================================================

class FullSummaryPage extends StatelessWidget {
  final String seasonId;
  final String district;
  const FullSummaryPage({
    super.key,
    required this.seasonId,
    required this.district,
  });

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  List<dynamic> asList(dynamic value) => value is List ? value : [];

  num readNum(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value;
      if (value is String)
        return num.tryParse(value.replaceAll('%', '').trim()) ?? 0;
    }
    return 0;
  }

  Widget panel({required Widget child, Color color = Colors.greenAccent}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.8), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget button({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.greenAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: color,
          side: BorderSide(color: color),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget miniStat(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.greenAccent),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream =
        FirebaseFirestore.instance
            .collection('agents')
            .doc('HIPL_LAPTOP_01')
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FULL SUMMARY'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          StreamBuilder<DocumentSnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final agent =
                  snapshot.data!.data() as Map<String, dynamic>? ?? {};

              final districtSummary = asMap(agent['district_summary']);
              final blockSummary = asMap(agent['block_summary']);
              final duplicateEpic = asList(
                agent['duplicate_epic_crop_location'],
              );
              final duplicatePlot = asList(agent['duplicate_plot']);
              final duplicateBank = asList(agent['duplicate_bank']);
              final createdUserSummary = asMap(agent['created_user_summary']);
              final duplicateFallback = asList(agent['duplicate_summary']);

              final totalApplication = readNum(districtSummary, [
                'total_application',
                'total_applications',
                'application',
                'applications',
              ]);
              final totalHector = readNum(districtSummary, [
                'total_hector',
                'hector',
                'total_area_hector',
              ]);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  panel(
                    color: Colors.amberAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FINAL SUMMARY / INTELLIGENCE',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'District: ${agent['current_district'] ?? district}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Season: ${agent['current_season'] ?? seasonId}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Updated: ${agent['last_update'] ?? '-'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: miniStat(
                          'APPLICATION',
                          totalApplication.toStringAsFixed(0),
                          Icons.description,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: miniStat(
                          'HECTOR',
                          totalHector.toStringAsFixed(2),
                          Icons.landscape,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  panel(
                    child: Column(
                      children: [
                        button(
                          context: context,
                          label: 'STATE SUMMARY (SCALABLE)',
                          icon: Icons.public,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) =>
                                          StateSummaryPage(seasonId: seasonId),
                                ),
                              ),
                          color: Colors.amberAccent,
                        ),
                        button(
                          context: context,
                          label: 'DISTRICT SUMMARY (SCALABLE)',
                          icon: Icons.location_city,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => DistrictSummaryPage(
                                        seasonId: seasonId,
                                      ),
                                ),
                              ),
                          color: Colors.blueAccent,
                        ),
                        button(
                          context: context,
                          label: 'BLOCK WISE REPORT',
                          icon: Icons.table_chart,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => BlockReportPage(
                                        blockSummary: blockSummary,
                                      ),
                                ),
                              ),
                          color: Colors.cyanAccent,
                        ),
                        button(
                          context: context,
                          label: 'SCALABLE BLOCK COLLECTION',
                          icon: Icons.grid_view,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => BlockCollectionPage(
                                        seasonId: seasonId,
                                        district: district,
                                      ),
                                ),
                              ),
                          color: Colors.lightBlueAccent,
                        ),
                        button(
                          context: context,
                          label:
                              'DUPLICATE EPIC (${duplicateEpic.isNotEmpty ? duplicateEpic.length : duplicateFallback.length})',
                          icon: Icons.person_search,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => DuplicateReportPage(
                                        title:
                                            'DUPLICATE EPIC + CROP + LOCATION',
                                        items:
                                            duplicateEpic.isNotEmpty
                                                ? duplicateEpic
                                                : duplicateFallback,
                                      ),
                                ),
                              ),
                          color: Colors.orangeAccent,
                        ),
                        button(
                          context: context,
                          label: 'DUPLICATE PLOT (${duplicatePlot.length})',
                          icon: Icons.map,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => DuplicateReportPage(
                                        title: 'DUPLICATE MOUZA + JL + PLOT',
                                        items: duplicatePlot,
                                      ),
                                ),
                              ),
                          color: Colors.pinkAccent,
                        ),
                        button(
                          context: context,
                          label: 'DUPLICATE BANK (${duplicateBank.length})',
                          icon: Icons.account_balance,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => DuplicateReportPage(
                                        title: 'DUPLICATE BANK ACCOUNT + IFSC',
                                        items: duplicateBank,
                                      ),
                                ),
                              ),
                          color: Colors.deepPurpleAccent,
                        ),
                        button(
                          context: context,
                          label:
                              'CREATED USER PROFILE (${createdUserSummary.length})',
                          icon: Icons.manage_accounts,
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => CreatedUserReportPage(
                                        userSummary: createdUserSummary,
                                      ),
                                ),
                              ),
                          color: Colors.lightGreenAccent,
                        ),
                        button(
                          context: context,
                          label: 'EXPORT REPORT PATH',
                          icon: Icons.file_download,
                          onPressed:
                              () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Export folder: ${agent['export_folder'] ?? 'Laptop Downloads folder'}',
                                  ),
                                ),
                              ),
                          color: Colors.tealAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCALABLE REPORT PAGES
// Reads new structure:
// bsb_reports/{SEASON}/state_summary/WEST_BENGAL
// bsb_reports/{SEASON}/districts/{DISTRICT}
// bsb_reports/{SEASON}/blocks/{DISTRICT_BLOCK}
// ============================================================

class StateSummaryPage extends StatelessWidget {
  final String seasonId;
  const StateSummaryPage({super.key, required this.seasonId});

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('bsb_reports')
        .doc(seasonId)
        .collection('state_summary')
        .doc('WEST_BENGAL');
    return Scaffold(
      appBar: AppBar(
        title: Text('STATE SUMMARY $seasonId'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          StreamBuilder<DocumentSnapshot>(
            stream: ref.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              if (!snapshot.data!.exists)
                return const Center(
                  child: Text('No scalable state summary found yet'),
                );
              final data = asMap(snapshot.data!.data());
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SummaryTile(
                    title: 'Total Application',
                    value:
                        '${data['total_application'] ?? data['total_applications'] ?? 0}',
                    icon: Icons.description,
                  ),
                  SummaryTile(
                    title: 'Total EPIC',
                    value: '${data['total_epic'] ?? 0}',
                    icon: Icons.person,
                  ),
                  SummaryTile(
                    title: 'Total Hector',
                    value: '${data['total_hector'] ?? 0}',
                    icon: Icons.landscape,
                  ),
                  SummaryTile(
                    title: 'District Count',
                    value: '${data['district_count'] ?? 0}',
                    icon: Icons.location_city,
                  ),
                  SummaryTile(
                    title: 'Block Count',
                    value: '${data['block_count'] ?? 0}',
                    icon: Icons.grid_view,
                  ),
                  SummaryTile(
                    title: 'Duplicate Count',
                    value: '${data['duplicate_count'] ?? 0}',
                    icon: Icons.warning,
                  ),
                  SummaryTile(
                    title: 'Updated',
                    value:
                        '${data['updated_at'] ?? data['last_update'] ?? '-'}',
                    icon: Icons.update,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class DistrictSummaryPage extends StatelessWidget {
  final String seasonId;
  const DistrictSummaryPage({super.key, required this.seasonId});

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  String clean(String s) => s.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('bsb_reports')
        .doc(seasonId)
        .collection('districts')
        .orderBy('district');
    return Scaffold(
      appBar: AppBar(
        title: Text('DISTRICT SUMMARY $seasonId'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: ref.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty)
                return const Center(
                  child: Text('No scalable district summary found yet'),
                );
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = asMap(docs[index].data());
                  final district =
                      (data['district'] ?? docs[index].id).toString();
                  return Card(
                    color: Colors.black.withOpacity(0.86),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.greenAccent),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      title: Text(
                        clean(district),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Hector: ${data['total_hector'] ?? data['hector'] ?? 0}\nDuplicate: ${data['duplicate_count'] ?? 0}',
                      ),
                      trailing: Text(
                        '${data['total_application'] ?? data['application'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class BlockCollectionPage extends StatelessWidget {
  final String seasonId;
  final String district;
  const BlockCollectionPage({
    super.key,
    required this.seasonId,
    required this.district,
  });

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  String clean(String s) => s.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('bsb_reports')
        .doc(seasonId)
        .collection('blocks')
        .where('district', isEqualTo: district);
    return Scaffold(
      appBar: AppBar(
        title: Text('SCALABLE BLOCKS ${clean(district)}'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: ref.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty)
                return const Center(
                  child: Text('No scalable block data found yet'),
                );
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = asMap(docs[index].data());
                  final block = (data['block'] ?? docs[index].id).toString();
                  return Card(
                    color: Colors.black.withOpacity(0.86),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.cyanAccent),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      title: Text(
                        clean(block),
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Hector: ${data['hector'] ?? data['total_hector'] ?? 0}\nDuplicate: ${data['duplicate_count'] ?? 0}',
                      ),
                      trailing: Text(
                        '${data['application'] ?? data['total_application'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const SummaryTile({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withOpacity(0.86),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.greenAccent),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.greenAccent),
        title: Text(title, style: const TextStyle(color: Colors.white70)),
        subtitle: Text(
          value,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// OLD REPORT PAGES - for current agent/HIPL_LAPTOP_01 live summary
// ============================================================

class BlockReportPage extends StatefulWidget {
  final Map<String, dynamic> blockSummary;
  const BlockReportPage({super.key, required this.blockSummary});

  @override
  State<BlockReportPage> createState() => _BlockReportPageState();
}

class _BlockReportPageState extends State<BlockReportPage> {
  String? selectedBlock;

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  String clean(String value) => value.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blockSummary.keys.toList()..sort();
    selectedBlock ??= blocks.isNotEmpty ? blocks.first : null;
    final data =
        selectedBlock == null
            ? <String, dynamic>{}
            : asMap(widget.blockSummary[selectedBlock]);
    final cropSummary = asMap(data['crop_summary']);
    final statusSummary = asMap(data['status_summary'] ?? data['status']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLOCK WISE REPORT'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (blocks.isEmpty)
                const Center(child: Text('No block report found'))
              else ...[
                DropdownButtonFormField<String>(
                  value: selectedBlock,
                  dropdownColor: Colors.black,
                  decoration: const InputDecoration(
                    labelText: 'Select Block',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      blocks
                          .map(
                            (block) => DropdownMenuItem(
                              value: block,
                              child: Text(clean(block)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => selectedBlock = value),
                ),
                const SizedBox(height: 16),
                Text(
                  clean(selectedBlock ?? ''),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'APPLICATION : ${data['application'] ?? data['applications'] ?? '-'}',
                ),
                Text('HECTOR : ${data['hector'] ?? '-'}'),
                const SizedBox(height: 18),
                const Text(
                  'CROP WISE',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...cropSummary.entries.map((e) {
                  final v = asMap(e.value);
                  return Card(
                    color: Colors.black.withOpacity(0.85),
                    child: ListTile(
                      title: Text(clean(e.key)),
                      subtitle: Text('Hector: ${v['hector'] ?? '-'}'),
                      trailing: Text('${v['application'] ?? '-'}'),
                    ),
                  );
                }),
                const SizedBox(height: 18),
                const Text(
                  'APPLICATION STATUS %',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...statusSummary.entries.map((e) {
                  final v = asMap(e.value);
                  return Card(
                    color: Colors.black.withOpacity(0.85),
                    child: ListTile(
                      title: Text(e.key),
                      subtitle: Text('Percent: ${v['percent'] ?? '-'}%'),
                      trailing: Text('${v['count'] ?? '-'}'),
                    ),
                  );
                }),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class DuplicateReportPage extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  const DuplicateReportPage({
    super.key,
    required this.title,
    required this.items,
  });

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  String cleanList(dynamic value) {
    if (value is List)
      return value.map((e) => e.toString().replaceAll('_', ' ')).join(', ');
    return '-';
  }

  String cleanFarmerDetails(dynamic value) {
    if (value is! List || value.isEmpty) return '-';
    final lines = <String>[];
    for (final row in value.take(6)) {
      final m = asMap(row);
      final farmer = m['farmer_name'] ?? '-';
      final epic = m['epic'] ?? '-';
      final block = (m['block'] ?? '-').toString().replaceAll('_', ' ');
      final gp = (m['gp'] ?? '-').toString().replaceAll('_', ' ');
      lines.add('$farmer | EPIC: $epic | Block: $block | GP: $gp');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$title (${items.length})'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = asMap(items[index]);
              return Card(
                color: Colors.black.withOpacity(0.88),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.greenAccent),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  title: Text(
                    'CASE #${index + 1}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'EPIC: ${item['epic'] ?? cleanList(item['epics'])}\n'
                    'Farmer: ${item['farmer_name'] ?? cleanList(item['farmers'])}\n'
                    'Farmer Details:\n${cleanFarmerDetails(item['farmer_details'])}\n'
                    'Crop: ${item['crop'] ?? '-'}\n'
                    'Mouza: ${item['mouza'] ?? cleanList(item['mouzas'])}\n'
                    'JL: ${item['jl_no'] ?? '-'}   Plot: ${item['plot_no'] ?? '-'}\n'
                    'Bank: ${item['bank_account'] ?? '-'}   IFSC: ${item['ifsc'] ?? '-'}\n'
                    'Blocks: ${cleanList(item['blocks'])}\n'
                    'GP: ${cleanList(item['gps'])}\n'
                    'Count: ${item['duplicate_count'] ?? '-'}',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class CreatedUserReportPage extends StatefulWidget {
  final Map<String, dynamic> userSummary;
  const CreatedUserReportPage({super.key, required this.userSummary});

  @override
  State<CreatedUserReportPage> createState() => _CreatedUserReportPageState();
}

class _CreatedUserReportPageState extends State<CreatedUserReportPage> {
  String? selectedUser;

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, val) => MapEntry(key.toString(), val));
    return {};
  }

  Widget line(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$label : ${value ?? '-'}',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.userSummary.keys.toList()..sort();
    selectedUser ??= users.isNotEmpty ? users.first : null;
    final data =
        selectedUser == null
            ? <String, dynamic>{}
            : asMap(widget.userSummary[selectedUser]);
    final statusBreakup = asMap(data['status_breakup']);
    final cropBreakup = asMap(data['crop_breakup']);
    final blockBreakup = asMap(data['block_breakup']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CREATED USER INTELLIGENCE'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          const MatrixBackground(),
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (users.isEmpty)
                const Center(child: Text('No created user data found'))
              else ...[
                DropdownButtonFormField<String>(
                  value: selectedUser,
                  dropdownColor: Colors.black,
                  decoration: const InputDecoration(
                    labelText: 'Select Created User',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      users
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => selectedUser = v),
                ),
                const SizedBox(height: 14),
                Card(
                  color: Colors.black.withOpacity(0.88),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.greenAccent),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedUser ?? '-',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 8),
                        line('Total Application', data['total_application']),
                        line('Total EPIC', data['total_epic']),
                        line('Hector', data['hector']),
                        line('ADA Approved', data['ada_approved']),
                        line('DDA Approved', data['dda_approved']),
                        line('SNO Approved', data['sno_approved']),
                        line('Rejected', data['rejected']),
                        line('Pending/Uploaded', data['pending_or_uploaded']),
                        line(
                          'Duplicate Application Count',
                          data['duplicate_application_count'],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'STATUS BREAKUP',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...statusBreakup.entries.map((e) {
                  final v = asMap(e.value);
                  return Card(
                    color: Colors.black.withOpacity(0.82),
                    child: ListTile(
                      title: Text(e.key),
                      subtitle: Text('Percent: ${v['percent'] ?? '-'}%'),
                      trailing: Text('${v['count'] ?? '-'}'),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text(
                  'CROP BREAKUP',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...cropBreakup.entries.map((e) {
                  final v = asMap(e.value);
                  return Card(
                    color: Colors.black.withOpacity(0.82),
                    child: ListTile(
                      title: Text(e.key),
                      subtitle: Text('Hector: ${v['hector'] ?? '-'}'),
                      trailing: Text('${v['application'] ?? '-'}'),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text(
                  'BLOCK BREAKUP',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...blockBreakup.entries.map(
                  (e) => Card(
                    color: Colors.black.withOpacity(0.82),
                    child: ListTile(
                      title: Text(e.key),
                      trailing: Text('${e.value}'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BACKGROUND / ANIMATION
// ============================================================

class CyberBlink extends StatefulWidget {
  final Widget child;
  const CyberBlink({super.key, required this.child});

  @override
  State<CyberBlink> createState() => _CyberBlinkState();
}

class _CyberBlinkState extends State<CyberBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.76, end: 1.0).animate(controller),
      child: widget.child,
    );
  }
}

class MatrixBackground extends StatefulWidget {
  const MatrixBackground({super.key});

  @override
  State<MatrixBackground> createState() => _MatrixBackgroundState();
}

class _MatrixBackgroundState extends State<MatrixBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder:
          (_, __) => CustomPaint(
            painter: MatrixPainter(controller.value),
            size: Size.infinite,
          ),
    );
  }
}

class MatrixPainter extends CustomPainter {
  final double t;
  MatrixPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    final paint = TextPainter(textDirection: TextDirection.ltr);
    final columns = max(12, (size.width / 26).floor());
    const chars = '01HIPLBSBMISDATA';

    for (int c = 0; c < columns; c++) {
      final x = c * 26.0 + random.nextDouble() * 8;
      final speed = 0.25 + random.nextDouble() * 0.7;
      final baseY =
          ((t * size.height * speed * 3) + random.nextDouble() * size.height) %
              (size.height + 200) -
          120;
      for (int r = 0; r < 18; r++) {
        final y = baseY + r * 20;
        if (y < -20 || y > size.height + 20) continue;
        final ch = chars[random.nextInt(chars.length)];
        final opacity = (1.0 - r / 22).clamp(0.05, 0.36);
        paint.text = TextSpan(
          text: ch,
          style: TextStyle(
            color: Colors.greenAccent.withOpacity(opacity),
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        );
        paint.layout();
        paint.paint(canvas, Offset(x, y));
      }
    }

    final hipPaint = TextPainter(
      text: TextSpan(
        text: 'HIPL',
        style: TextStyle(
          color: Colors.greenAccent.withOpacity(
            0.06 + 0.04 * sin(t * pi * 2).abs(),
          ),
          fontSize: 96,
          fontWeight: FontWeight.bold,
          letterSpacing: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hipPaint.paint(
      canvas,
      Offset((size.width - hipPaint.width) / 2, size.height * 0.42),
    );
  }

  @override
  bool shouldRepaint(covariant MatrixPainter oldDelegate) => oldDelegate.t != t;
}
