import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:latlong2/latlong.dart';

class FakeLocationScreen extends StatefulWidget {
  const FakeLocationScreen({super.key});

  @override
  State<FakeLocationScreen> createState() => _FakeLocationScreenState();
}

class _FakeLocationScreenState extends State<FakeLocationScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  // Ubicaciones famosas predefinidas
  final List<Map<String, dynamic>> _presets = [
    {'name': '🗼 París, Francia', 'lat': 48.8584, 'lng': 2.2945},
    {'name': '🗽 Nueva York, USA', 'lat': 40.7128, 'lng': -74.0060},
    {'name': '🏯 Tokyo, Japón', 'lat': 35.6762, 'lng': 139.6503},
    {'name': '🌉 Londres, UK', 'lat': 51.5074, 'lng': -0.1278},
    {'name': '🏖️ Cancún, México', 'lat': 21.1619, 'lng': -86.8515},
    {'name': '🌆 Ciudad de México', 'lat': 19.4326, 'lng': -99.1332},
    {'name': '🎭 Buenos Aires', 'lat': -34.6037, 'lng': -58.3816},
    {'name': '🌴 Miami, USA', 'lat': 25.7617, 'lng': -80.1918},
  ];

  void _selectPreset(Map<String, dynamic> preset) {
    final lat = preset['lat'] as double;
    final lng = preset['lng'] as double;
    setState(() {
      _selectedLocation = LatLng(lat, lng);
      _latCtrl.text = lat.toString();
      _lngCtrl.text = lng.toString();
    });
    _mapController.move(_selectedLocation!, 12);
  }

  void _selectFromCoords() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordenadas inválidas'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _selectedLocation = LatLng(lat, lng));
    _mapController.move(_selectedLocation!, 12);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1321),
        foregroundColor: Colors.white,
        title: const Text('📍 Ubicación falsa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedLocation),
              child: const Text('Enviar', style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Mapa
          SizedBox(
            height: 300,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(19.4326, -99.1332),
                initialZoom: 5,
                onTap: (_, point) {
                  setState(() {
                    _selectedLocation = point;
                    _latCtrl.text = point.latitude.toStringAsFixed(6);
                    _lngCtrl.text = point.longitude.toStringAsFixed(6);
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.secureapp.ghost_client',
                  tileProvider: CachedTileProvider(
                    store: MemCacheStore(),
                  ),
                ),
                if (_selectedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Toca el mapa para seleccionar ubicación', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          // Coordenadas manuales
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Latitud',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Longitud',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectFromCoords,
                  style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.white),
                  child: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Ubicaciones predefinidas
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Lugares famosos:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _presets.length,
              itemBuilder: (_, i) {
                final preset = _presets[i];
                final isSelected = _selectedLocation?.latitude == preset['lat'] && _selectedLocation?.longitude == preset['lng'];
                return ListTile(
                  title: Text(preset['name'], style: TextStyle(color: isSelected ? _cyan : Colors.white)),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF00D4FF)) : null,
                  onTap: () => _selectPreset(preset),
                  tileColor: isSelected ? _cyan.withOpacity(0.1) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
