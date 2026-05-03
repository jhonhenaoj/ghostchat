import 'package:flutter/material.dart';
import 'call_history_screen.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../utils/socket_manager.dart';

class CallScreen extends StatefulWidget {
  final String callType;
  final Function(Map<String, dynamic>) sendSignal;
  final String remoteUserId;
  final String? pendingOffer;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.callType,
    required this.sendSignal,
    required this.remoteUserId,
    this.pendingOffer,
    this.isVideo = false,
  });

  @override
  CallScreenState createState() => CallScreenState();
}

class CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  DateTime? _callStart;
  bool _isCameraOff = false;
  bool _isConnected = false;
  bool _isFrontCamera = true;
  bool _disposed = false;
  List<RTCIceCandidate> _pendingCandidates = [];
  String _status = "Conectando...";

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
      {
        'urls': 'turn:freestun.net:3478',
        'username': 'free',
        'credential': 'free',
      },
      {
        'urls': 'turns:freestun.net:5349',
        'username': 'free',
        'credential': 'free',
      },
    ]
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    SocketManager().addListener(_onSocketMessage);
    await Future.delayed(const Duration(milliseconds: 300));
    await _startCall();
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (_disposed || !mounted) return;
    final type = msg["type"]?.toString() ?? "";
    if (type == "answer") {
      final sdp = msg["sdp"]?.toString();
      if (sdp != null) handleAnswer(sdp);
    } else if (type == "ice") {
      handleIce(msg);
    } else if (type == "offer") {
      final sdp = msg["sdp"]?.toString();
      if (sdp != null) handleOffer(sdp);
    } else if (type == "hangup") {
      _saveCallHistory(answered: _isConnected);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } else if (type == "receiver_reconnected") {
      if (widget.callType == 'caller' && _peerConnection != null) {
        _resendOffer();
      }
    }
  }

  Future<void> _startCall() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });

      if (widget.isVideo && mounted) {
        setState(() => _localRenderer.srcObject = _localStream);
      }

      _peerConnection = await createPeerConnection(_iceServers);

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            _remoteStream = event.streams[0];
            if (widget.isVideo) {
              _remoteRenderer.srcObject = _remoteStream;
            }
          });
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && !_disposed) {
          widget.sendSignal({
            'type': 'ice',
            'to': widget.remoteUserId,
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        if (!mounted || _disposed) return;
        debugPrint("🧊 ICE state: $state");
        setState(() {
          if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
            _isConnected = true;
            _status = "En llamada ✅";
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
            _status = "Desconectado";
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            _status = "Error de conexión";
          }
        });
      };

      _peerConnection!.onConnectionState = (state) {
        if (!mounted || _disposed) return;
        setState(() {
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            _isConnected = true;
            _status = "En llamada ✅";
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            _status = "Desconectado";
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _status = "Error de conexión";
          }
        });
      };

      if (widget.callType == 'caller') {
        if (mounted) setState(() => _status = "Llamando...");
        final offer = await _peerConnection!.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': widget.isVideo,
        });
        await _peerConnection!.setLocalDescription(offer);
        widget.sendSignal({
          'type': 'offer',
          'to': widget.remoteUserId,
          'sdp': offer.sdp,
          'isVideo': widget.isVideo,
        });
      } else {
        if (mounted) setState(() => _status = "Conectando...");
        // Usar offer del widget, o el guardado globalmente en SocketManager
        final offer = widget.pendingOffer ?? SocketManager().pendingOffer;
        if (offer != null) {
          debugPrint("📞 Procesando offer pendiente");
          SocketManager().pendingOffer = null; // limpiar
          SocketManager().pendingOfferFrom = null;
          await handleOffer(offer);
        } else {
          debugPrint("📞 Esperando offer...");
          if (mounted) setState(() => _status = "Esperando conexión...");
        }
      }
    } catch (e) {
      debugPrint("❌ Error en llamada: $e");
      if (mounted) setState(() => _status = "Error: $e");
    }
  }

  Future<void> handleOffer(String sdp) async {
    try {
      if (_peerConnection == null) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
      // Aplicar candidatos pendientes
      for (final c in _pendingCandidates) {
        await _peerConnection!.addCandidate(c);
      }
      _pendingCandidates.clear();
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      widget.sendSignal({
        'type': 'answer',
        'to': widget.remoteUserId,
        'sdp': answer.sdp,
      });
      if (mounted) setState(() => _status = "En llamada ✅");
    } catch (e) {
      debugPrint("❌ Error handleOffer: $e");
    }
  }

  Future<void> handleAnswer(String sdp) async {
    try {
      if (_peerConnection == null) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );
      // Aplicar candidatos pendientes
      for (final c in _pendingCandidates) {
        await _peerConnection!.addCandidate(c);
      }
      _pendingCandidates.clear();
    } catch (e) {
      debugPrint("❌ Error handleAnswer: $e");
    }
  }

  Future<void> handleIce(Map<String, dynamic> data) async {
    try {
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      // Si aún no hay remote description, guardar candidato
      final remoteDesc = await _peerConnection?.getRemoteDescription();
      if (_peerConnection == null || remoteDesc == null) {
        _pendingCandidates.add(candidate);
        return;
      }
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      debugPrint("❌ Error handleIce: $e");
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleCamera() {
    setState(() => _isCameraOff = !_isCameraOff);
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isCameraOff;
    });
  }

  void _switchCamera() async {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
      setState(() => _isFrontCamera = !_isFrontCamera);
    }
  }

  Future<void> _resendOffer() async {
    debugPrint("📞 Receiver reconectó, reenviando offer...");
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
      });
      await _peerConnection!.setLocalDescription(offer);
      widget.sendSignal({
        'type': 'offer',
        'to': widget.remoteUserId,
        'sdp': offer.sdp,
        'isVideo': widget.isVideo,
      });
    } catch (e) {
      debugPrint("❌ Error reenviando offer: $e");
    }
  }

  void _hangUp() {
    widget.sendSignal({
      'type': 'hangup',
      'to': widget.remoteUserId,
    });
    _saveCallHistory(answered: true);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _saveCallHistory({required bool answered}) {
    final duration = _callStart != null ? DateTime.now().difference(_callStart!) : Duration.zero;
    // Obtener myUserId del socket
    final myUserId = widget.callType == 'caller' ? '' : '';
    CallHistoryScreen.saveCall(
      myUserId: SocketManager().currentUserId ?? '',
      remoteUserId: widget.remoteUserId,
      remoteName: 'Usuario \${widget.remoteUserId}',
      isVideo: widget.isVideo,
      isIncoming: widget.callType == 'receiver',
      answered: answered,
      duration: duration,
    );
  }

  void _cleanup() {
    _disposed = true;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    SocketManager().removeListener(_onSocketMessage);
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.isVideo)
              Positioned.fill(
                child: _remoteStream != null
                    ? RTCVideoView(_remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : Container(
                        color: Colors.black87,
                        child: const Center(
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.teal,
                            child: Icon(Icons.person, size: 60, color: Colors.white),
                          ),
                        ),
                      ),
              ),

            if (!widget.isVideo)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.person, size: 60, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Usuario ${widget.remoteUserId}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: TextStyle(
                          color: _isConnected ? Colors.greenAccent : Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (widget.isVideo)
              Positioned(
                top: 16,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _isCameraOff
                      ? Container(
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.videocam_off, color: Colors.white))
                      : RTCVideoView(_localRenderer,
                          mirror: _isFrontCamera,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),

            if (widget.isVideo)
              Positioned(
                top: 16,
                left: 16,
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _isConnected ? Colors.greenAccent : Colors.white70,
                    fontSize: 14,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),

            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? "Activar" : "Silenciar",
                    color: _isMuted ? Colors.white24 : Colors.white12,
                    onTap: _toggleMute,
                  ),
                  if (widget.isVideo)
                    _buildButton(
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      label: _isCameraOff ? "Activar" : "Cámara",
                      color: _isCameraOff ? Colors.white24 : Colors.white12,
                      onTap: _toggleCamera,
                    ),
                  _buildButton(
                    icon: Icons.call_end,
                    label: "Colgar",
                    color: Colors.red,
                    size: 36,
                    onTap: _hangUp,
                  ),
                  if (widget.isVideo)
                    _buildButton(
                      icon: Icons.flip_camera_android,
                      label: "Girar",
                      color: Colors.white12,
                      onTap: _switchCamera,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    double size = 32,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: size,
          backgroundColor: color,
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: size * 0.75),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
