import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isVideo = false;
  bool _isFront = false;
  XFile? _capturedFile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    await _setupController(_cameras[0]);
  }

  Future<void> _setupController(CameraDescription camera) async {
    _controller = CameraController(camera, ResolutionPreset.high, enableAudio: true);
    await _controller!.initialize();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() { _loading = true; _isFront = !_isFront; });
    await _setupController(_cameras[_isFront ? 1 : 0]);
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final file = await _controller!.takePicture();
    if (mounted) Navigator.pop(context, {'file': file, 'isVideo': false});
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.startVideoRecording();
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final file = await _controller!.stopVideoRecording();
    setState(() => _isRecording = false);
    if (mounted) Navigator.pop(context, {'file': file, 'isVideo': true});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Stack(
                children: [
                  // Preview de cámara
                  Positioned.fill(
                    child: CameraPreview(_controller!),
                  ),

                  // Botón cerrar
                  Positioned(
                    top: 16,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  // Botón cambiar cámara
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 30),
                      onPressed: _switchCamera,
                    ),
                  ),

                  // Selector foto/video
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isVideo = false),
                          child: Text("FOTO", style: TextStyle(
                            color: _isVideo ? Colors.white54 : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          )),
                        ),
                        const SizedBox(width: 32),
                        GestureDetector(
                          onTap: () => setState(() => _isVideo = true),
                          child: Text("VIDEO", style: TextStyle(
                            color: _isVideo ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          )),
                        ),
                      ],
                    ),
                  ),

                  // Botón captura
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _isVideo
                            ? (_isRecording ? _stopRecording : _startRecording)
                            : _takePicture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: _isRecording ? Colors.red : (_isVideo ? Colors.red.shade300 : Colors.white),
                          ),
                          child: _isRecording
                              ? const Icon(Icons.stop, color: Colors.white, size: 32)
                              : _isVideo
                                  ? const Icon(Icons.videocam, color: Colors.white, size: 32)
                                  : null,
                        ),
                      ),
                    ),
                  ),

                  // Indicador grabando
                  if (_isRecording)
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, color: Colors.white, size: 10),
                              SizedBox(width: 6),
                              Text("GRABANDO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
