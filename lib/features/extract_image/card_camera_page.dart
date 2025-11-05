import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

class CardCameraPage extends StatefulWidget {
  const CardCameraPage({super.key});

  // دالة ثابتة لفتح الكاميرا
  static Future<XFile?> capture(BuildContext context) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<XFile?>(MaterialPageRoute(builder: (_) => const CardCameraPage()));
  }

  @override
  State<CardCameraPage> createState() => _CardCameraPageState();
}

class _CardCameraPageState extends State<CardCameraPage> {
  CameraController? _controller;
  bool _isLoading = true;
  String? _error;
  bool _isFlashOn = false; // حالة الفلاش

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      // طلب إذن الكاميرا
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _error = 'يرجى السماح باستخدام الكاميرا';
          _isLoading = false;
        });
        return;
      }

      print('Camera permission granted');

      // قفل الشاشة Portrait
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // الحصول على الكاميرات المتاحة
      final cameras = await availableCameras();
      print('Available cameras: ${cameras.length}');

      if (cameras.isEmpty) {
        setState(() {
          _error = 'لا توجد كاميرا متاحة';
          _isLoading = false;
        });
        return;
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      print('Using camera: ${camera.name}');

      // إعداد Controller بأعلى جودة ممكنة
      final controller = CameraController(
        camera,
        ResolutionPreset.high, // أعلى جودة متاحة
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      print('Initializing camera...');
      await controller.initialize();

      print('Setting camera modes...');
      // تفعيل التركيز التلقائي المستمر لأفضل وضوح
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(FlashMode.off);

      // تفعيل ميزات إضافية لتحسين الجودة (إن وجدت)
      try {
        // محاولة قفل البياض الأبيض للحصول على ألوان أفضل
        await controller.lockCaptureOrientation();
      } catch (e) {
        print('Some advanced features not available: $e');
      }

      if (!mounted) {
        print('Widget not mounted, disposing controller');
        await controller.dispose();
        return;
      }

      print('Camera ready!');
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('❌ Camera setup error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = 'خطأ في تشغيل الكاميرا: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      // تفعيل الفلاش مؤقتاً إذا كان مفعلاً
      if (_isFlashOn) {
        await controller.setFlashMode(FlashMode.torch);
      }

      // الانتظار قليلاً للتركيز والتعرض المثالي
      await Future.delayed(const Duration(milliseconds: 100));

      // التقاط الصورة بأعلى جودة
      final XFile image = await controller.takePicture();

      // إطفاء الفلاش بعد التصوير
      if (_isFlashOn) {
        await controller.setFlashMode(FlashMode.off);
      }

      // قراءة الصورة وتحسينها
      final File imageFile = File(image.path);
      final imageBytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        if (mounted) {
          Navigator.of(context).pop(image);
        }
        return;
      }

      // حساب حجم المربع في الصورة الفعلية
      final imageWidth = originalImage.width;
      final imageHeight = originalImage.height;

      // استخدام أصغر بعد لضمان المربع
      final minDimension = imageWidth < imageHeight ? imageWidth : imageHeight;
      final cropSize = (minDimension * 0.85).toInt();

      // مركز الصورة
      final cropX = (imageWidth - cropSize) ~/ 2;
      final cropY = (imageHeight - cropSize) ~/ 2;

      // قص الصورة للمربع فقط
      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropSize,
        height: cropSize,
      );

      // تحسين جودة الصورة
      croppedImage = _enhanceImage(croppedImage);

      // حفظ الصورة المحسنة بأعلى جودة (100%)
      final croppedBytes = img.encodeJpg(croppedImage, quality: 100);
      await imageFile.writeAsBytes(croppedBytes);

      print('✅ Image cropped and enhanced: ${cropSize}x$cropSize');

      if (mounted) {
        Navigator.of(context).pop(image);
      }
    } catch (e) {
      print('Error taking/cropping picture: $e');
      // في حالة فشل القص، نرجع الصورة الأصلية
      try {
        final XFile image = await controller.takePicture();
        if (mounted) {
          Navigator.of(context).pop(image);
        }
      } catch (e2) {
        print('Error in fallback: $e2');
      }
    }
  }

  // دالة لتحسين جودة الصورة
  img.Image _enhanceImage(img.Image image) {
    // زيادة الحدة (Sharpen) لوضوح أفضل
    image = img.adjustColor(
      image,
      contrast: 1.1, // زيادة التباين قليلاً
      brightness: 1.05, // تفتيح خفيف
    );

    // تطبيق sharpen filter لوضوح أكثر
    image = img.gaussianBlur(image, radius: 1);

    return image;
  }

  Future<void> _setFocusPoint(Offset point) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      print('Error setting focus: $e');
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });

      // تفعيل أو إطفاء الفلاش
      await controller.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      print('Error toggling flash: $e');
      setState(() {
        _isFlashOn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // معاينة الكاميرا مع Tap للتركيز
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: GestureDetector(
                onTapUp: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;

                  final offset = box.globalToLocal(details.globalPosition);
                  final point = Offset(
                    offset.dx / box.size.width,
                    offset.dy / box.size.height,
                  );
                  _setFocusPoint(point);
                },
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // Overlay مع مربع التحديد
          const Positioned.fill(child: _CardFrameOverlay()),

          // زر الإغلاق
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // زر الفلاش
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              icon: Icon(
                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
                size: 32,
              ),
              onPressed: _toggleFlash,
            ),
          ),

          // تعليمات
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'ضع الكارت داخل المربع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'اضغط على الشاشة للتركيز • ${_isFlashOn ? "الفلاش مفعل" : "استخدم الفلاش للإضاءة"}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // زر التصوير
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
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

// Widget للإطار المربع
class _CardFrameOverlay extends StatelessWidget {
  const _CardFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CardFramePainter());
  }
}

class _CardFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // خلفية شفافة داكنة حول المربع
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    // حجم المربع (Square - نفس العرض والطول)
    final squareSize = size.width * 0.85;

    final left = (size.width - squareSize) / 2;
    final top = (size.height - squareSize) / 2;

    // رسم الخلفية مع فتحة للمربع
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, squareSize, squareSize),
          const Radius.circular(20),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, backgroundPaint);

    // رسم الإطار المربع
    final framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, squareSize, squareSize),
      const Radius.circular(20),
    );

    canvas.drawRRect(frameRect, framePaint);

    // رسم الزوايا المميزة
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const cornerLength = 35.0;

    // الزاوية العلوية اليسرى
    canvas.drawLine(
      Offset(left, top + 20),
      Offset(left, top + 20 + cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + 20, top),
      Offset(left + 20 + cornerLength, top),
      cornerPaint,
    );

    // الزاوية العلوية اليمنى
    canvas.drawLine(
      Offset(left + squareSize, top + 20),
      Offset(left + squareSize, top + 20 + cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + squareSize - 20, top),
      Offset(left + squareSize - 20 - cornerLength, top),
      cornerPaint,
    );

    // الزاوية السفلية اليسرى
    canvas.drawLine(
      Offset(left, top + squareSize - 20),
      Offset(left, top + squareSize - 20 - cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + 20, top + squareSize),
      Offset(left + 20 + cornerLength, top + squareSize),
      cornerPaint,
    );

    // الزاوية السفلية اليمنى
    canvas.drawLine(
      Offset(left + squareSize, top + squareSize - 20),
      Offset(left + squareSize, top + squareSize - 20 - cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + squareSize - 20, top + squareSize),
      Offset(left + squareSize - 20 - cornerLength, top + squareSize),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
