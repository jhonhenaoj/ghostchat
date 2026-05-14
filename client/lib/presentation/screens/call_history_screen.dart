import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallHistoryScreen extends StatefulWidget {
  final String myUserId;
  const CallHistoryScreen({super.key, required this.myUserId});

  static Future<void> saveCall({
    required String myUserId,
    required String remoteUserId,
    required String remoteName,
    required bool isVideo,
    required bool isIncoming,
    required bool answered,
    required Duration duration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('call_history_$myUserId') ?? [];
    raw.add(jsonEncode({
      'remote_id': remoteUserId,
      'remote_name': remoteName,
      'is_video': isVideo,
      'is_incoming': isIncoming,
      'answered': answered,
      'duration_seconds': duration.inSeconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
    if (raw.length > 50) raw.removeAt(0);
    await prefs.setStringList('call_history_$myUserId', raw);
  }

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<Map<String, dynamic>> _calls = [];

  static const Color _bg = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF0D1321);
  static const Color _cyan = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('call_history_${widget.myUserId}') ?? [];
    setState(() {
      _calls = raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList().reversed.toList();
    });
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return 'No contestada';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTime(int ms) {
    if (ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day && dt.month == yesterday.month && dt.year == yesterday.year) return 'Ayer';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Historial de llamadas', style: TextStyle(color: Colors.white)),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: _surface,
                  title: const Text('Borrar historial', style: TextStyle(color: Colors.white)),
                  content: const Text('¿Borrar todo el historial?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('call_history_${widget.myUserId}');
                _loadHistory();
              }
            },
          ),
        ],
      ),
      body: _calls.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.call_missed, size: 64, color: Colors.white.withOpacity(0.2)),
                const SizedBox(height: 16),
                Text('Sin historial de llamadas', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16)),
              ]),
            )
          : ListView.builder(
              itemCount: _calls.length,
              itemBuilder: (_, i) {
                final call = _calls[i];
                final isVideo = call['is_video'] == true;
                final isIncoming = call['is_incoming'] == true;
                final answered = call['answered'] == true;
                final duration = call['duration_seconds'] as int? ?? 0;
                final remoteName = call['remote_name'] as String? ?? 'Usuario';
                final timestamp = call['timestamp'] as int? ?? 0;

                Color statusColor;
                IconData statusIcon;
                if (!answered) {
                  statusColor = Colors.red;
                  statusIcon = isIncoming ? Icons.call_missed : Icons.call_missed_outgoing;
                } else {
                  statusColor = Colors.green;
                  statusIcon = isIncoming ? Icons.call_received : Icons.call_made;
                }

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withOpacity(0.15),
                        border: Border.all(color: statusColor.withOpacity(0.4)),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 22),
                    ),
                    title: Text(remoteName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Row(children: [
                      Icon(isVideo ? Icons.videocam : Icons.call, size: 12, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(
                        '${isVideo ? "Video" : "Voz"} · ${_formatDuration(duration)}',
                        style: TextStyle(color: answered ? Colors.white54 : Colors.red.withOpacity(0.7), fontSize: 12),
                      ),
                    ]),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_formatTime(timestamp), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        const SizedBox(height: 4),
                        Icon(isVideo ? Icons.videocam : Icons.call, color: _cyan, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
