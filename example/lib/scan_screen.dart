import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:recharge_card_ocr/recharge_card_ocr.dart';

/// Live camera preview with the card overlay. Pops a [CardReadResult] after
/// a capture, or null when cancelled.
class ScanScreen extends StatefulWidget {
  /// Creates the screen.
  const ScanScreen({super.key, required this.specs, required this.labels});

  /// Code spec per zone.
  final Map<String, DigitCodeSpec> specs;

  /// Overlay labels per zone.
  final Map<String, String> labels;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  static const _layout = ZoneLayout.rechargeCard;
  static const _geometry = CardScanGeometry(layout: _layout);

  CameraController? _controller;
  late final CardCodeReader _reader = CardCodeReader(
    recognizer: MlKitDigitReader(),
    layout: _layout,
    specs: widget.specs,
  );
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _reader.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setup();
    }
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera available');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  /// The camera reports its aspect ratio in sensor (landscape) orientation;
  /// in portrait the preview shows it rotated, so invert it.
  double _cameraAspect(CameraController c) {
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    return portrait ? 1 / c.value.aspectRatio : c.value.aspectRatio;
  }

  Future<void> _capture(Size previewSize) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final cardRegion = _geometry.cardRegionInImage(
        previewSize: previewSize,
        cameraAspect: _cameraAspect(c),
      );
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      final result = await _reader.read(bytes, cardRegion: cardRegion);
      if (mounted) Navigator.of(context).pop(result);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not read the card: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : c == null || !c.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final cameraAspect = _cameraAspect(c);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // BoxFit.cover, matching CardScanGeometry's mapping.
                      ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: size.height * cameraAspect,
                            height: size.height,
                            child: CameraPreview(c),
                          ),
                        ),
                      ),
                      CardScanOverlay(layout: _layout, labels: widget.labels),
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 28,
                        child: Center(
                          child: FloatingActionButton.large(
                            onPressed: _busy ? null : () => _capture(size),
                            child: _busy
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.camera_alt),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
