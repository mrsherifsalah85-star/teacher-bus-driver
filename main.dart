import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

const String projectId = 'car-tracking-5ef70';
const String apiKey = 'AIzaSyDn7mzRrWvCeEyCdq_O0p-Aq1aOGWsT8ok';
const String ridersCol = 'riders_69c0006e66edbeb4';

const Color kBlue = Color(0xFF1A237E);
const Color kGreen = Color(0xFF2E7D32);
const Color kBg = Color(0xFFF3F4FB);

void main() => runApp(const DriverApp());

class Rider {
  final String name;
  final double lat;
  final double lng;
  final double? stLat;
  final double? stLng;
  Rider(this.name, this.lat, this.lng, this.stLat, this.stLng);
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سائق الباص',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
        scaffoldBackgroundColor: kBg,
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
  final MapController _mapCtrl = MapController();
  StreamSubscription<Position>? _sub;
  Timer? _ridersTimer;
  Position? _pos;
  List<Rider> _riders = [];
  bool _tracking = false;
  bool _centered = false;
  String _status = 'اضغط "ابدأ الرحلة" وبعدها تقدر تقفل الشاشة.';
  int _sent = 0;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
    _ridersTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchRiders());
  }

  double? _num(dynamic v) {
    if (v == null) return null;
    final d = v['doubleValue'];
    if (d != null) return (d as num).toDouble();
    final i = v['integerValue'];
    if (i != null) return double.tryParse(i.toString());
    return null;
  }

  Future<void> _fetchRiders() async {
    try {
      final res = await http.get(Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/$projectId/databases/(default)/documents/$ridersCol',
        {'key': apiKey, 'pageSize': '100'},
      ));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = (body['documents'] as List?) ?? [];
      final now = DateTime.now().toUtc();
      final list = <Rider>[];
      for (final d in docs) {
        final f = ((d as Map<String, dynamic>)['fields'] as Map<String, dynamic>?) ?? {};
        final active = f['active']?['booleanValue'] == true;
        final lat = _num(f['lat']);
        final lng = _num(f['lng']);
        final updated = DateTime.tryParse((f['updated']?['timestampValue'] ?? '').toString());
        if (!active || lat == null || lng == null || updated == null) continue;
        if (now.difference(updated.toUtc()).inMinutes > 3) continue;
        final name = (f['name']?['stringValue'] ?? 'راكب').toString();
        list.add(Rider(name, lat, lng, _num(f['stLat']), _num(f['stLng'])));
      }
      if (!mounted) return;
      setState(() => _riders = list);
      if (!_centered && list.isNotEmpty && _pos == null) {
        _centered = true;
        try {
          _mapCtrl.move(LatLng(list.first.lat, list.first.lng), 14);
        } catch (_) {}
      }
    } catch (_) {}
  }

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
          _pos = pos;
          if (ok) _sent++;
          _status = ok
              ? '✅ التتبع شغال. تقدر تقفل الشاشة.'
              : '⚠️ في مشكلة في الإرسال. اتأكد من النت.';
        });
        if (!_centered) {
          _centered = true;
          try {
            _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15);
          } catch (_) {}
        }
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
      _pos = null;
      _status = 'الرحلة خلصت. التتبع اتوقف.';
    });
  }

  String _riderState(Rider r) {
    if (r.stLat == null || r.stLng == null) return 'من غير محطة محفوظة';
    final d = Geolocator.distanceBetween(r.lat, r.lng, r.stLat!, r.stLng!);
    if (d <= 100) return 'في المحطة ✅';
    if (d <= 500) return 'قريب من المحطة (${d.round()} م)';
    return 'بعيد عن المحطة (${(d / 1000).toStringAsFixed(1)} كم)';
  }

  @override
  void dispose() {
    _ridersTimer?.cancel();
    _sub?.cancel();
    _car.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (_pos != null) {
      markers.add(Marker(
        point: LatLng(_pos!.latitude, _pos!.longitude),
        width: 44,
        height: 44,
        child: const Text('🚌', style: TextStyle(fontSize: 34)),
      ));
    }
    for (final r in _riders) {
      if (r.stLat != null && r.stLng != null) {
        markers.add(Marker(
          point: LatLng(r.stLat!, r.stLng!),
          width: 34,
          height: 34,
          child: const Text('🚏', style: TextStyle(fontSize: 22)),
        ));
      }
      markers.add(Marker(
        point: LatLng(r.lat, r.lng),
        width: 90,
        height: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧍', style: TextStyle(fontSize: 26)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kBlue, width: 0.8),
              ),
              child: Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kBlue)),
            ),
          ],
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🚌 سائق الباص'),
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _car,
                        enabled: !_tracking,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'كود السيارة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _tracking ? _stop : _start,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tracking ? Colors.red.shade700 : kGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _tracking ? 'إنهاء الرحلة' : 'ابدأ الرحلة',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _tracking ? '$_status  (مرات الإرسال: $_sent)' : _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                mapController: _mapCtrl,
                options: const MapOptions(
                  initialCenter: LatLng(31.2, 29.95),
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.teacherbus.teacher_bus_driver',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          Container(
            height: 150,
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الركاب المتابعين (${_riders.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue)),
                const SizedBox(height: 4),
                Expanded(
                  child: _riders.isEmpty
                      ? const Center(child: Text('مفيش ركاب متابعين دلوقتي'))
                      : ListView.builder(
                          itemCount: _riders.length,
                          itemBuilder: (context, i) {
                            final r = _riders[i];
                            return InkWell(
                              onTap: () {
                                try {
                                  _mapCtrl.move(LatLng(r.lat, r.lng), 16);
                                } catch (_) {}
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Text('🧍 '),
                                    Expanded(
                                      child: Text(r.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    Text(_riderState(r), style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
