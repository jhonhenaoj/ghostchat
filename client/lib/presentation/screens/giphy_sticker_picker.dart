import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GiphyStickerPicker extends StatefulWidget {
  final Function(String url, String id) onStickerSelected;
  const GiphyStickerPicker({super.key, required this.onStickerSelected});

  @override
  State<GiphyStickerPicker> createState() => _GiphyStickerPickerState();
}

class _GiphyStickerPickerState extends State<GiphyStickerPicker> {
  static const String _apiKey = 'Jun0R40KxF0Be5dkPQWmTw9oRFSjGwMf';
  List<Map<String, dynamic>> _stickers = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = 'funny';

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    setState(() => _loading = true);
    try {
      final url = _query.isEmpty
          ? 'https://api.giphy.com/v1/stickers/trending?api_key=$_apiKey&limit=24&rating=g'
          : 'https://api.giphy.com/v1/stickers/search?api_key=$_apiKey&q=$_query&limit=24&rating=g';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = data['data'] as List;
        setState(() {
          _stickers = items.map((s) => {
            'id': s['id'],
            'url': s['images']['fixed_height_small']['url'],
            'original': s['images']['original']['url'],
          }).toList();
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      color: const Color(0xFF0D1321),
      child: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar stickers...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0A0E1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                  onPressed: () { _searchController.clear(); _query = 'funny'; _loadStickers(); },
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (val) {
                _query = val;
                _loadStickers();
              },
            ),
          ),
          // Grid de stickers
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _stickers.length,
                    itemBuilder: (_, i) {
                      final sticker = _stickers[i];
                      return GestureDetector(
                        onTap: () => widget.onStickerSelected(sticker['original']!, sticker['id']!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(imageUrl: 
                            sticker['url']!,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : Container(color: const Color(0xFF1A2035),
                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D4FF)))),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
