import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:latlong2/latlong.dart';

class LiveLocationMapScreen extends StatefulWidget {
  final String contactName;
  final Stream<Map<String, dynamic>> locationStream;
  final LatLng? myLocation;
  final LatLng? initialLocation;
  final bool isMe;

  const LiveLocationMapScreen({
    super.key,
    required this.contactName,
    required this.locationStream,
    this.myLocation,
    this.initialLocation,
    this.isMe = false,
  });

  @override
  State<LiveLocationMapScreen> createState() => _LiveLocationMapScreenState();
}

class _LiveLocationMapScreenState extends State<LiveLocationMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _contactLocation;
  LatLng? _myLocation;
  DateTime? _lastUpdate;
  StreamSubscription? _sub;
  bool _followContact = true;

  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _bg = Color(0xFF0A0E1A);

  @override
  void initState() {
    super.initState();
    _myLocation = widget.myLocation;
    // Mostrar ubicacion inicial inmediatamente sin esperar stream
    if (widget.initialLocation != null) {
      _contactLocation = widget.initialLocation;
      _lastUpdate = DateTime.now();
      // setState no es necesario en initState pero asegurar valor
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {
          _contactLocation = widget.initialLocation;
          _lastUpdate = DateTime.now();
        });
      });
    }
    // Escuchar actualizaciones posteriores
    _sub = widget.locationStream.listen((data) {
      final url = data['url']?.toString() ?? '';
      final coords = _parseCoords(url);
      if (coords != null && mounted) {
        setState(() {
          _contactLocation = coords;
          _lastUpdate = DateTime.now();
        });
        if (_followContact) {
          _mapController.move(coords, _mapController.camera.zoom);
        }
      }
    });
  }

  LatLng? _parseCoords(String url) {
    try {
      final q = url.replaceAll('https://maps.google.com/?q=', '');
      final parts = q.split(',');
      if (parts.length < 2) return null;
      final lat = double.parse(parts[0]);
      final lng = double.parse(parts[1]);
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return 'Esperando...';
    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inSeconds < 60) return 'Hace ${diff.inSeconds}s';
    return 'Hace ${diff.inMinutes}min';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📡 ${widget.contactName}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(_formatLastUpdate(), style: const TextStyle(fontSize: 11, color: Color(0xFF00D4FF))),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_followContact ? Icons.gps_fixed : Icons.gps_not_fixed, color: _followContact ? _cyan : Colors.white54),
            tooltip: 'Seguir contacto',
            onPressed: () => setState(() => _followContact = !_followContact),
          ),
        ],
      ),
      body: _contactLocation == null && widget.initialLocation == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: Color(0xFF00D4FF)),
                const SizedBox(height: 16),
                Text('Esperando ubicación de ${widget.contactName}...', style: const TextStyle(color: Colors.white54)),
              ]),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _contactLocation!,
                    initialZoom: 16,
                    onTap: (_, __) => setState(() => _followContact = false),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.secureapp.ghost_client',
                      tileProvider: CachedTileProvider(
                        store: MemCacheStore(),
                      ),
                    ),
                    MarkerLayer(
                      markers: [
                        // Marcador del contacto
                        if (_contactLocation != null)
                          Marker(
                            point: _contactLocation!,
                            width: 60,
                            height: 80,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00D4FF),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                                  ),
                                  child: Text(
                                    widget.contactName.length > 8 ? widget.contactName.substring(0, 8) : widget.contactName,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Icon(Icons.location_pin, color: Color(0xFF00D4FF), size: 32),
                              ],
                            ),
                          ),
                        // Marcador propio
                        if (_myLocation != null)
                          Marker(
                            point: _myLocation!,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Panel inferior con info
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1321).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cyan.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFF00D4FF), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_contactLocation?.latitude.toStringAsFixed(5)}, ${_contactLocation?.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Text(_formatLastUpdate(), style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.center_focus_strong, color: Color(0xFF00D4FF)),
                          onPressed: () {
                            if (_contactLocation != null) {
                              _mapController.move(_contactLocation!, 16);
                              setState(() => _followContact = true);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
