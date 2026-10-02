import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String projectId = 'car-tracking-5ef70';
const String apiKey = 'AIzaSyDn7mzRrWvCeEyCdq_O0p-Aq1aOGWsT8ok';

void main() => runApp(const DriverApp());

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سائق الباص',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const DriverPage(),
    );
  }
}

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  final TextEditingController _car = TextEditingController(text: 'car-001');
  StreamSubscription<Position>? _sub;
  bool _tracking = false;
  String _status = 'اضغط "ابدأ الرحلة" وبعدها تقدر تقفل الشاشة.';
  String _coords = '';
  int _sent = 0;

  Uri _docUri(String code, List<String> fields) {
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$projectId/databases/(default)/documents/tracking/$code',
      {'updateMask.fieldPaths': fields, 'key': apiKey},
    );
  }

  Future<bool> _send(String code, {double? lat, double? lng, required bool active}) async {
    try {
      final fields = <String, dynamic>{
        'active': {'booleanValue': active},
        'timestamp': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      };
      final mask = <String>['active', 'timestamp'];
      if (lat != null && lng != null) {
        fields['lat'] = {'doubleValue': lat};
        fields['lng'] = {'doubleValue': lng};
        mask.addAll(['lat', 'lng']);
      }
      final res = await http.patch(
        _docUri(code, mask),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': fields}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final code = _car.text.trim();
    if (code.isEmpty) {
      setState(() => _status = 'اكتب كود السيارة الأول.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = 'شغّل الـ GPS من إعدادات الموبايل وجرب تاني.');
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _status = 'لازم تسمح للتطبيق بالوصول للموقع. هفتحلك الإعدادات.');
      await openAppSettings();
      return;
    }
    await Permission.notification.request();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'تتبع الباص شغال',
        notificationText: 'جارٍ إرسال موقعك للركاب',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        final ok = await _send(code, lat: pos.latitude, lng: pos.longitude, active: true);
        if (!mounted) return;
        setState(() {
          if (ok) _sent++;
          _coords = '${pos.latitude.toStringAsFixed(5)} , ${pos.longitude.toStringAsFixed(5)}';
          _status = ok
              ? '✅ التتبع شغال. تقدر تقفل الشاشة.'
              : '⚠️ في مشكلة في الإرسال. اتأكد من النت.';
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _status = 'مشكلة في قراءة الموقع: $e');
      },
    );
    setState(() {
      _tracking = true;
      _status = 'جارٍ تحديد موقعك...';
    });
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _send(_car.text.trim(), active: false);
    if (!mounted) return;
    setState(() {
      _tracking = false;
      _coords = '';
      _status = 'الرحلة خلصت. التتبع اتوقف.';
    });
  }

  @override
  void dispose() {
    _car.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚌 سائق الباص'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _car,
              enabled: !_tracking,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: 'كود السيارة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: _tracking ? _stop : _start,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tracking ? Colors.red.shade700 : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _tracking ? 'إنهاء الرحلة' : 'ابدأ الرحلة',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (_coords.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_coords, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 4),
              Text('مرات الإرسال: $_sent', style: const TextStyle(color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }
}
