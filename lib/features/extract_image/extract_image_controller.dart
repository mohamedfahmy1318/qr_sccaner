import 'dart:io';
import 'dart:math' as Math;
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as imglib;
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/core/appStorage/scan_model.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

class ExtractImageController extends Cubit<ExtractImageStates> {
  ExtractImageController(this.scanType) : super(ExtractInitial());

  static ExtractImageController of(context) => BlocProvider.of(context);

  // ============== Controllers ==============
  TextEditingController pin = TextEditingController();
  TextEditingController serial = TextEditingController();

  // ============== Properties ==============
  final String? scanType;
  String scannedText = '';
  bool textScanned = false;
  File? image;
  File? scanImage;

  // حدود لتحسين الأداء
  final int _maxOcrPasses = 3; // 🎯 3 محاولات للتوازن بين السرعة والدقة
  final double _earlyStopConfidence = 0.90; // ثقة عالية للإيقاف المبكر
  final bool _debugOcr = false; // تقليل اللوغات افتراضياً

  // كاش لقوالب الأرقام كمصفوفات Mat جاهزة (لتفادي I/O والتكرار)
  final Map<String, List<String>> _templatePaths = {
    '0': ['assets/digit_templates/template_0.jpeg'],
    '3': ['assets/digit_templates/template_3.jpeg'],
    '5': ['assets/digit_templates/template_5.jpeg'],
    '6': [
      'assets/digit_templates/template_6_A.jpeg',
      'assets/digit_templates/template_6_B.jpeg',
      'assets/digit_templates/template_6_C.jpeg',
    ],
    '8': ['assets/digit_templates/template_8.jpeg'],
    '9': ['assets/digit_templates/template_9.jpeg'],
  };
  final Map<String, List<dynamic>> _templateMatsCache = {}; // key -> List<Mat>
  bool _templatesLoaded = false;

  Future<void> _ensureTemplatesLoaded() async {
    if (_templatesLoaded) return;

    print('🔄 Loading digit templates from assets...');

    for (final entry in _templatePaths.entries) {
      final list = <dynamic>[]; // Mat
      for (final path in entry.value) {
        try {
          // قراءة الملف من assets باستخدام rootBundle
          final ByteData data = await rootBundle.load(path);
          final bytes = data.buffer.asUint8List();

          // تحويل إلى OpenCV Mat
          final mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);

          if (mat.isEmpty) {
            print('⚠️ Failed to decode template: $path');
            continue;
          }

          list.add(mat);
          print('✅ Loaded template: $path (${mat.width}x${mat.height})');
        } catch (e) {
          print('❌ Error loading template $path: $e');
        }
      }
      if (list.isNotEmpty) {
        _templateMatsCache[entry.key] = list;
        print('✅ Digit "${entry.key}" has ${list.length} template(s)');
      } else {
        print('⚠️ No templates loaded for digit "${entry.key}"');
      }
    }

    _templatesLoaded = true;
    print(
      '✅ Template loading complete. Total digits: ${_templateMatsCache.keys.length}',
    );
  }

  // تخزين البدائل للاختيار اليدوي
  List<String> pinAlternatives = [];
  List<String> serialAlternatives = [];

  // ============== Image Capture ==============
  Future<void> getImage() async {
    try {
      if (!await Permission.camera.request().isGranted) {
        emit(ImagePickedError());
        return;
      }

      print('AUTO Scanner...');
      dynamic result = await FlutterDocScanner().getScannedDocumentAsImages(
        page: 1,
      );
      print('Result: $result');

      // استخراج الـ path من الـ toString() بـ Regex
      String resultStr = result.toString();
      RegExp regex = RegExp(r'file:///([^}]+)');
      Match? match = regex.firstMatch(resultStr);

      if (match == null) {
        print('Failed to extract path');
        emit(ImagePickedError());
        return;
      }

      String fullPath = '/${match.group(1)!}';
      print('Extracted Path: $fullPath');

      // نسخ الصورة إلى مكان آمن
      final dir = await getApplicationDocumentsDirectory();
      final safePath =
          '${dir.path}/zain_card_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(fullPath).copy(safePath);

      if (!await File(safePath).exists()) {
        print('File not copied!');
        emit(ImagePickedError());
        return;
      }

      image = File(safePath);
      scanImage = File(safePath);
      print('READY for OCR: $safePath');
      emit(ImagePickedSuccess());

      // ⚠️ إضافة تأخير بسيط للسماح للـ UI بالتحديث وتحرير الذاكرة
      await Future.delayed(Duration(milliseconds: 300));

      // معالجة الصورة في background
      try {
        final processedPath = await _processImageForOcr(safePath);

        // تأخير آخر قبل بدء OCR
        await Future.delayed(Duration(milliseconds: 200));

        await getText(processedPath);
      } catch (e) {
        print('❌ Error processing/OCR: $e');
        // محاولة مع الصورة الأصلية إذا فشلت المعالجة
        try {
          await getText(safePath);
        } catch (e2) {
          print('❌ Error with original image: $e2');
          emit(ScanError());
        }
      }
    } catch (e) {
      print('❌ Error in getImage: $e');
      emit(ImagePickedError());
    }
  }

  Future<String> _processImageForOcr(String imagePath) async {
    try {
      print(
        '🔄 Starting enhanced image processing for accurate digit recognition...',
      );
      final bytes = await File(imagePath).readAsBytes();
      imglib.Image? img = imglib.decodeImage(bytes);

      if (img != null) {
        // تحسين الدقة - حجم أمثل للتعرف على الأرقام الدقيقة
        if (img.width > 1200) {
          img = imglib.copyResize(img, width: 1200);
        } else if (img.width < 800) {
          img = imglib.copyResize(img, width: 800);
        }

        // معالجة متوازنة للأرقام - مش قوية أوي عشان متمحيش الأرقام
        imglib.Image gray = imglib.grayscale(img);

        // إزالة المراجع غير الضرورية لتحرير الذاكرة
        img = null;

        // 1. تقليل الضوضاء بشكل خفيف
        gray = imglib.gaussianBlur(gray, radius: 1);

        // 2. تحسين التباين المتوسط (مش قوي أوي)
        gray = imglib.contrast(gray, contrast: 150);

        // 3. Sharpening مرة واحدة بس
        gray = _sharpenImage(gray);

        // 4. تطبيع للحصول على نطاق كامل
        gray = imglib.normalize(gray, max: 255, min: 0);

        // استخدام جودة عالية للحفاظ على التفاصيل
        final processedBytes = imglib.encodeJpg(gray, quality: 95);

        final tempDir = Directory.systemTemp;
        final tempPath =
            '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(tempPath).writeAsBytes(processedBytes);

        print('✅ Image processed with digit-optimized enhancements: $tempPath');
        return tempPath;
      }
    } catch (e) {
      print('⚠️ Error processing image: $e - using original');
    }
    return imagePath;
  }

  // معالجة morphological خفيفة لتحسين الأرقام
  imglib.Image _lightMorphology(imglib.Image gray) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);

    // Erosion خفيف جداً لإزالة الضوضاء الصغيرة فقط
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int minVal = 255;
        // استخدام kernel صغير 3x3
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            int val = imglib.getLuminance(gray.getPixel(x + i, y + j)).toInt();
            if (val < minVal) minVal = val;
          }
        }
        out.setPixelRgba(x, y, minVal, minVal, minVal, 255);
      }
    }

    return out;
  } // تطبيق CLAHE يدوياً (Contrast Limited Adaptive Histogram Equalization)

  imglib.Image _applyCLAHE(imglib.Image gray) {
    // تقسيم الصورة إلى مربعات صغيرة وتطبيق histogram equalization على كل مربع
    const int tileSize = 8;
    final w = gray.width, h = gray.height;
    final result = gray.clone();

    for (int ty = 0; ty < h; ty += tileSize) {
      for (int tx = 0; tx < w; tx += tileSize) {
        int tw = Math.min(tileSize, w - tx);
        int th = Math.min(tileSize, h - ty);

        // حساب الهيستوجرام للمربع
        List<int> hist = List.filled(256, 0);
        for (int y = ty; y < ty + th; y++) {
          for (int x = tx; x < tx + tw; x++) {
            int val = imglib.getLuminance(gray.getPixel(x, y)).toInt();
            hist[val]++;
          }
        }

        // حساب CDF (Cumulative Distribution Function)
        List<int> cdf = List.filled(256, 0);
        cdf[0] = hist[0];
        for (int i = 1; i < 256; i++) {
          cdf[i] = cdf[i - 1] + hist[i];
        }

        // تطبيع CDF
        int cdfMin = cdf.firstWhere((v) => v > 0);
        int totalPixels = tw * th;

        for (int y = ty; y < ty + th; y++) {
          for (int x = tx; x < tx + tw; x++) {
            int val = imglib.getLuminance(gray.getPixel(x, y)).toInt();
            int newVal = ((cdf[val] - cdfMin) * 255 / (totalPixels - cdfMin))
                .clamp(0, 255)
                .toInt();
            result.setPixelRgba(x, y, newVal, newVal, newVal, 255);
          }
        }
      }
    }

    return result;
  }

  // تطبيق Sharpening filter
  imglib.Image _sharpenImage(imglib.Image gray) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);

    // Sharpening kernel
    const List<List<int>> kernel = [
      [0, -1, 0],
      [-1, 5, -1],
      [0, -1, 0],
    ];

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int sum = 0;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            final p = gray.getPixel(x + i, y + j);
            final int v = imglib.getLuminance(p).toInt();
            sum += kernel[j + 1][i + 1] * v;
          }
        }
        int val = sum.clamp(0, 255).toInt();
        out.setPixelRgba(x, y, val, val, val, 255);
      }
    }

    return out;
  }

  // تطبيق Morphological operations (Dilation + Erosion)
  imglib.Image _applyMorphology(imglib.Image gray) {
    final w = gray.width, h = gray.height;

    // Erosion (تقليل السُمك) لإزالة الضوضاء الصغيرة
    var temp = imglib.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int minVal = 255;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            int val = imglib.getLuminance(gray.getPixel(x + i, y + j)).toInt();
            if (val < minVal) minVal = val;
          }
        }
        temp.setPixelRgba(x, y, minVal, minVal, minVal, 255);
      }
    }

    // Dilation (زيادة السُمك) لتوضيح الأرقام
    final out = imglib.Image(width: w, height: h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int maxVal = 0;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            int val = imglib.getLuminance(temp.getPixel(x + i, y + j)).toInt();
            if (val > maxVal) maxVal = val;
          }
        }
        out.setPixelRgba(x, y, maxVal, maxVal, maxVal, 255);
      }
    }

    return out;
  }

  // 🎯 Adaptive Thresholding - أفضل من Manual threshold للإضاءة غير المتساوية
  imglib.Image _adaptiveThreshold(imglib.Image gray, int blockSize, double c) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);
    final halfBlock = blockSize ~/ 2;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // حساب متوسط المنطقة المحيطة
        int sum = 0;
        int count = 0;

        for (
          int j = Math.max(0, y - halfBlock);
          j < Math.min(h, y + halfBlock + 1);
          j++
        ) {
          for (
            int i = Math.max(0, x - halfBlock);
            i < Math.min(w, x + halfBlock + 1);
            i++
          ) {
            sum += imglib.getLuminance(gray.getPixel(i, j)).toInt();
            count++;
          }
        }

        int mean = sum ~/ count;
        int threshold = (mean - c).toInt();
        int pixel = imglib.getLuminance(gray.getPixel(x, y)).toInt();
        int value = pixel > threshold ? 255 : 0;

        out.setPixelRgba(x, y, value, value, value, 255);
      }
    }

    return out;
  }

  // 🎯 Bilateral Filter - يحافظ على الحواف مع تنعيم الضوضاء
  imglib.Image _bilateralFilter(
    imglib.Image gray,
    int radius,
    double sigmaColor,
    double sigmaSpace,
  ) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double totalWeight = 0;
        double filteredValue = 0;
        int centerVal = imglib.getLuminance(gray.getPixel(x, y)).toInt();

        for (int j = -radius; j <= radius; j++) {
          for (int i = -radius; i <= radius; i++) {
            int nx = x + i;
            int ny = y + j;

            if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
              int neighborVal = imglib
                  .getLuminance(gray.getPixel(nx, ny))
                  .toInt();

              // وزن المسافة
              double spatialWeight = Math.exp(
                -(i * i + j * j) / (2 * sigmaSpace * sigmaSpace),
              );

              // وزن اللون
              double colorDiff = (centerVal - neighborVal).abs().toDouble();
              double colorWeight = Math.exp(
                -(colorDiff * colorDiff) / (2 * sigmaColor * sigmaColor),
              );

              double weight = spatialWeight * colorWeight;
              filteredValue += neighborVal * weight;
              totalWeight += weight;
            }
          }
        }

        int result = (filteredValue / totalWeight).round().clamp(0, 255);
        out.setPixelRgba(x, y, result, result, result, 255);
      }
    }

    return out;
  }

  // Note: استخدمنا فلترة خفيفة متوافقة مع الحزمة الحالية لتفادي أخطاء البناء

  // توليد عدة نسخ معالجة للصورة لتحسين دقة القراءة
  Future<List<String>> _generateProcessingVariants(String imagePath) async {
    final List<String> outputs = [];
    try {
      final bytes = await File(imagePath).readAsBytes();
      imglib.Image? base = imglib.decodeImage(bytes);

      if (base == null) return [imagePath];

      if (base.width > 1024) {
        base = imglib.copyResize(base, width: 1024);
      }

      final List<imglib.Image> variants = [];

      // v0: رمادي + حواف خفيفة + كونتراست قوي
      {
        var g = imglib.grayscale(base);
        final edges = _sobelEdges(g);
        g = _blendGrayAndEdges(g, edges, 0.30);
        g = imglib.contrast(g, contrast: 170);
        variants.add(g);
      }

      // v1: Normalize + تباين عالي
      {
        var g = imglib.grayscale(base);
        g = imglib.normalize(g, max: 255, min: 0);
        g = imglib.contrast(g, contrast: 180);
        variants.add(g);
      }

      // 🔥 v2: threshold يدوي متوسط
      {
        var g = imglib.grayscale(base);
        g = manualThreshold(g, 120);
        variants.add(g);
      }

      // 🔥 v3: CLAHE + contrast قوي
      {
        var g = imglib.grayscale(base);
        g = _applyCLAHE(g);
        g = imglib.contrast(g, contrast: 240);
        variants.add(g);
      }

      // 🔥 v4: Morphology + sharpen
      {
        var g = imglib.grayscale(base);
        g = _applyMorphology(g);
        g = _sharpenImage(g);
        g = imglib.contrast(g, contrast: 210);
        variants.add(g);
      }

      // 🔥 v5: threshold أعلى
      {
        var g = imglib.grayscale(base);
        g = manualThreshold(g, 145);
        variants.add(g);
      }

      // تدوير بسيط ±2 درجات على أول نسختين فقط
      List<imglib.Image> rotated = [];
      for (int i = 0; i < variants.length && i < 2; i++) {
        rotated.add(imglib.copyRotate(variants[i], angle: -2));
        rotated.add(imglib.copyRotate(variants[i], angle: 2));
      }
      variants.addAll(rotated);

      // حفظ إلى ملفات مؤقتة
      for (final img in variants) {
        final path =
            '${Directory.systemTemp.path}/ocr_var_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path).writeAsBytes(imglib.encodeJpg(img, quality: 85));
        outputs.add(path);
      }
    } catch (e) {
      print('⚠️ Error generating variants: $e');
    }
    if (outputs.isEmpty) return [imagePath];
    return outputs;
  }

  Future<List<String>> _enhanceAndReOcrSixes(
    String originalImagePath,
    List<TextBlock> blocks,
    TextRecognizer textRecognizer,
  ) async {
    final List<String> results = [];
    final bytes = await File(originalImagePath).readAsBytes();
    imglib.Image? base = imglib.decodeImage(bytes);
    int ix = 0;

    // توسيع القائمة لتشمل جميع الأرقام الملتبسة: 6, 5, 8, 0, 9, 3
    final ambiguousDigits = ['6', '5', '8', '0', '9', '3'];

    for (final block in blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final txt = element.text.trim();

          // فحص إذا كان النص يحتوي على أي رقم ملتبس
          if (ambiguousDigits.contains(txt)) {
            final rect = element.boundingBox;
            if (rect.left >= 0 && rect.top >= 0) {
              // توسيع المنطقة المقصوصة لضمان التقاط الرقم كاملاً
              int x = (rect.left - 12).toInt();
              int y = (rect.top - 12).toInt();
              int w = (rect.width + 24).toInt();
              int h = (rect.height + 24).toInt();

              x = x.clamp(0, base!.width - 1);
              y = y.clamp(0, base.height - 1);
              if (x + w > base.width) w = base.width - x;
              if (y + h > base.height) h = base.height - y;

              if (w > 5 && h > 5) {
                final crop = imglib.copyCrop(
                  base,
                  x: x,
                  y: y,
                  width: w,
                  height: h,
                );

                // تطبيق معالجة متقدمة على الرقم المقصوص
                var enhanced = imglib.grayscale(crop);
                enhanced = _sharpenImage(enhanced);
                enhanced = imglib.contrast(enhanced, contrast: 300);
                enhanced = imglib.normalize(enhanced, max: 255, min: 0);

                final tempPath =
                    '${Directory.systemTemp.path}/ocr_digit_${txt}_${DateTime.now().microsecondsSinceEpoch}_$ix.jpg';
                await File(
                  tempPath,
                ).writeAsBytes(imglib.encodeJpg(enhanced, quality: 100));

                // إجراء template matching
                final digitBytes = await File(tempPath).readAsBytes();
                final (bestDigit, score) = await matchDigitWithTemplates(
                  digitBytes,
                );

                if (bestDigit != txt && score >= 1.2) {
                  print(
                    '   🔧 Digit correction: OCR said "$txt" but template matching says "$bestDigit" (score: ${score.toStringAsFixed(2)})',
                  );
                }

                results.add(tempPath);
                ix++;
              }
            }
          }
        }
      }
    }
    return results;
  }

  imglib.Image _sobelEdges(imglib.Image gray) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);
    // مصفوفات Sobel
    const List<List<int>> gx = [
      [-1, 0, 1],
      [-2, 0, 2],
      [-1, 0, 1],
    ];
    const List<List<int>> gy = [
      [1, 2, 1],
      [0, 0, 0],
      [-1, -2, -1],
    ];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int sx = 0, sy = 0;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            final p = gray.getPixel(x + i, y + j);
            final int v = imglib.getLuminance(p).toInt();
            sx += gx[j + 1][i + 1] * v;
            sy += gy[j + 1][i + 1] * v;
          }
        }
        final double magnitude = Math.sqrt((sx * sx + sy * sy).toDouble());
        int mag = magnitude.clamp(0, 255).toInt();
        out.setPixelRgba(x, y, mag, mag, mag, 255);
      }
    }
    return out;
  }

  imglib.Image _blendGrayAndEdges(
    imglib.Image gray,
    imglib.Image edges,
    double alpha,
  ) {
    final w = gray.width, h = gray.height;
    final out = imglib.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pg = gray.getPixel(x, y);
        final pe = edges.getPixel(x, y);
        final vg = imglib.getLuminance(pg);
        final ve = imglib.getLuminance(pe);
        final double blend = vg * (1 - alpha) + ve * alpha;
        int v = blend.clamp(0, 255).toInt();
        out.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return out;
  }

  // ============== Manual Threshold ==============
  imglib.Image manualThreshold(imglib.Image gray, int thresh) {
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final color = gray.getPixel(x, y);
        final l = imglib.getLuminance(color).toInt();
        final v = l > thresh ? 255 : 0;
        gray.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return gray;
  }

  // ============== Text Recognition ==============
  Future<void> getText(String imagePath) async {
    try {
      print('🔍 Starting enhanced OCR for precise digit recognition...');
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      // توليد نسخ معالجة محسّنة للأرقام 0,6,8,9
      final originalBytes = await File(imagePath).readAsBytes();
      imglib.Image? img = imglib.decodeImage(originalBytes);
      final List<String> variantPaths = [];

      if (img != null) {
        print('📸 Generating 5 optimized variants (fast + accurate)...');

        // 🎯 النسخة 1: Contrast متوسط (الأساس)
        var img1 = imglib.grayscale(img.clone());
        img1 = imglib.contrast(img1, contrast: 150);
        final path1 =
            '${Directory.systemTemp.path}/v1_medium_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path1).writeAsBytes(imglib.encodeJpg(img1, quality: 95));
        variantPaths.add(path1);

        // 🎯 النسخة 2: High Contrast + Sharpen
        var img2 = imglib.grayscale(img.clone());
        img2 = imglib.contrast(img2, contrast: 190);
        img2 = _sharpenImage(img2);
        final path2 =
            '${Directory.systemTemp.path}/v2_highcon_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path2).writeAsBytes(imglib.encodeJpg(img2, quality: 95));
        variantPaths.add(path2);

        // 🎯 النسخة 3: Morphology - لتوضيح الأرقام
        var img3 = imglib.grayscale(img.clone());
        img3 = imglib.contrast(img3, contrast: 160);
        img3 = _applyMorphology(img3);
        final path3 =
            '${Directory.systemTemp.path}/v3_morph_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path3).writeAsBytes(imglib.encodeJpg(img3, quality: 95));
        variantPaths.add(path3);

        // 🎯 النسخة 4: CLAHE + Sharpen
        var img4 = imglib.grayscale(img.clone());
        img4 = _applyCLAHE(img4);
        img4 = _sharpenImage(img4);
        img4 = imglib.contrast(img4, contrast: 155);
        final path4 =
            '${Directory.systemTemp.path}/v4_clahe_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path4).writeAsBytes(imglib.encodeJpg(img4, quality: 95));
        variantPaths.add(path4);

        // 🎯 النسخة 5: Normalize + Double Sharpen (للحواف القوية)
        var img5 = imglib.grayscale(img.clone());
        img5 = imglib.normalize(img5, max: 255, min: 0);
        img5 = imglib.contrast(img5, contrast: 180);
        img5 = _sharpenImage(img5);
        img5 = _sharpenImage(img5); // double sharpen
        final path5 =
            '${Directory.systemTemp.path}/v5_sharp2_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path5).writeAsBytes(imglib.encodeJpg(img5, quality: 95));
        variantPaths.add(path5);

        // تحرير المتغيرات
        img = null;
      }

      List<Map<String, dynamic>> pinCandidates = [];
      List<Map<String, dynamic>> serialCandidates = [];

      print('\n═══════════════════════════════════════════════════════');
      print('🔍 Starting OCR Analysis...');
      print('═══════════════════════════════════════════════════════');

      bool earlyStop = false;
      int passCount = 0;

      for (final path in variantPaths) {
        if (passCount >= _maxOcrPasses) break;

        print('\n🖼️ OCR pass ${passCount + 1} on: ${path.split('/').last}');

        try {
          // 🚀 استخدام Google ML Kit
          final inputImage = InputImage.fromFilePath(path);
          final RecognizedText recognizedText = await textRecognizer
              .processImage(inputImage);

          String fullText = recognizedText.text;
          if (fullText.trim().isEmpty) {
            print('⚠️ No text found in this variant');
            continue;
          }

          print(
            '✅ Google ML Kit found ${recognizedText.blocks.length} text blocks',
          );

          for (TextBlock block in recognizedText.blocks) {
            for (TextLine line in block.lines) {
              scannedText += "${line.text}\n";
              String cleanText = cleanNumericText(line.text);

              if (isNumeric(cleanText) &&
                  cleanText.length >= 11 &&
                  !_containsTextMarkers(line.text)) {
                print(
                  '� Google ML Kit: "$cleanText" (${cleanText.length} digits)',
                );

                double conf = _calculateConfidence(line);
                print('💯 Confidence: ${(conf * 100).toStringAsFixed(1)}%');

                _analyzeAndClassify(
                  line,
                  cleanText,
                  conf,
                  pinCandidates,
                  serialCandidates,
                );

                // إيقاف مبكر إذا وجدنا PIN بثقة عالية
                if (isLikelyPin(cleanText) &&
                    conf >= _earlyStopConfidence &&
                    cleanText.length >= 14) {
                  print('✨ Found high-confidence PIN, stopping early');
                  earlyStop = true;
                  break;
                }
              }
            }
            if (earlyStop) break;
          }

          passCount++;
          if (earlyStop) break;

          // تأخير بسيط بين التمريرات
          await Future.delayed(Duration(milliseconds: 150));
        } catch (e) {
          print('❌ Error in OCR pass: $e');
          continue;
        }
      }

      print('\n📊 Analysis complete:');
      print('   PIN candidates: ${pinCandidates.length}');
      print('   Serial candidates: ${serialCandidates.length}');

      // إزالة المكررات مع الحفاظ على أعلى سكور
      pinCandidates = _dedupeByTextKeepBest(pinCandidates);
      serialCandidates = _dedupeByTextKeepBest(serialCandidates);

      // اختيار الأفضل
      _selectBestPin(pinCandidates);
      _selectBestSerial(serialCandidates);

      textScanned = false;
      emit(Scanning());
      await textRecognizer.close();

      print('✅ OCR process completed successfully');
    } catch (e) {
      print('❌ Error in getText: $e');
      emit(ScanError());
    }
  }

  List<Map<String, dynamic>> _dedupeByTextKeepBest(
    List<Map<String, dynamic>> list,
  ) {
    final Map<String, Map<String, dynamic>> best = {};
    for (final item in list) {
      final t = item['text'] as String;
      if (!best.containsKey(t) ||
          (item['confidence'] as double) > (best[t]!['confidence'] as double)) {
        best[t] = item;
      }
    }
    return best.values.toList();
  }

  void _postProcessCandidates(List<Map<String, dynamic>> candidates) {
    List<Map<String, dynamic>> additional = [];
    for (var candidate in candidates) {
      String text = candidate['text'];
      double baseConfidence = candidate['confidence'];

      // تم إزالة توليد بدائل 5→6 لضمان عدم استبدال الأرقام تلقائياً

      // إضافة variants لـ ? → 7
      List<int> questionPositions = [];
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '?') {
          questionPositions.add(i);
        }
      }

      for (int pos in questionPositions) {
        String variant = text.substring(0, pos) + '7' + text.substring(pos + 1);
        additional.add({
          'text': variant,
          'confidence': baseConfidence * 0.98,
          'length': variant.length,
        });
        print('   🔧 Added variant for ?->7 at position $pos: $variant');
      }

      // تصحيح 9→0 عندما تكون محاطة بأصفار (لبس شائع للصفر)
      List<int> ninePositions = [];
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '9') ninePositions.add(i);
      }
      for (int pos in ninePositions) {
        String prev = pos > 0 ? text[pos - 1] : ' ';
        String next = pos + 1 < text.length ? text[pos + 1] : ' ';
        if (prev == '0' || next == '0') {
          String variant =
              text.substring(0, pos) + '0' + text.substring(pos + 1);
          additional.add({
            'text': variant,
            'confidence': baseConfidence * 0.98,
            'length': variant.length,
          });
          print(
            '   🔧 Added variant for 9->0 near zeros at position $pos: $variant',
          );
        }
      }
    }
    candidates.addAll(additional);
  }

  double _calculateConfidence(TextLine line) {
    double confidence = 0.0;
    for (TextElement element in line.elements) {
      confidence += element.confidence ?? 0.0;
    }
    return line.elements.isNotEmpty ? confidence / line.elements.length : 0.5;
  }

  double _calculateScore(TextLine line, String cleanText, double confidence) {
    double score = confidence * 2.0; // زيادة وزن الثقة

    // عقوبات بناءً على مستوى الثقة
    if (confidence < 0.80) score *= 0.90;
    if (confidence < 0.75) score *= 0.85;
    if (confidence < 0.70) score *= 0.75;
    if (confidence < 0.65) score *= 0.65;
    if (confidence < 0.60) score *= 0.50;
    if (confidence < 0.50) score *= 0.30;

    // مكافأة للطول المناسب
    score += (cleanText.length / 60.0);

    // مكافأة لقلة الرموز (نص نظيف)
    int symbolCount = line.text.length - cleanText.length;
    if (symbolCount == 0) score += 0.25;
    if (symbolCount <= 2) score += 0.15;
    if (symbolCount > 5) score *= 0.6;

    // عقوبة شديدة لوجود نصوص (كلمات)
    if (_containsTextMarkers(line.text)) {
      score *= 0.1;
      print('   ⚠️  Contains text/words - heavily penalized');
    }

    // مكافآت خاصة للطول المثالي
    if (isLikelyPin(cleanText)) {
      if (cleanText.length == 14)
        score += 0.35; // الطول المثالي للـ PIN
      else if (cleanText.length >= 15 && cleanText.length <= 16)
        score += 0.20;
      else if (cleanText.length >= 17 && cleanText.length <= 19)
        score += 0.10;
    }

    if (isLikelySerial(cleanText)) {
      if (cleanText.length == 12)
        score += 0.35; // الطول المثالي للـ Serial
      else if (cleanText.length == 11)
        score += 0.15;
    }

    // مكافأة للأنماط المتوقعة في بداية الأرقام
    if (cleanText.length >= 3) {
      String firstThree = cleanText.substring(0, 3);
      // أنماط شائعة في بطاقات زين
      if (firstThree.startsWith('6') ||
          firstThree.startsWith('2') ||
          firstThree.startsWith('1') ||
          firstThree.startsWith('0')) {
        score += 0.10;
      }
    }

    // فحص عدم وجود أرقام مشبوهة متكررة بشكل غير طبيعي
    if (_hasAbnormalRepetition(cleanText)) {
      score *= 0.85;
      print('   ⚠️  Abnormal digit repetition detected');
    }

    return score;
  }

  // فحص التكرار غير الطبيعي للأرقام
  bool _hasAbnormalRepetition(String text) {
    if (text.length < 4) return false;

    // فحص إذا كان هناك رقم متكرر أكثر من 5 مرات متتالية
    for (int i = 0; i <= text.length - 5; i++) {
      if (text[i] == text[i + 1] &&
          text[i] == text[i + 2] &&
          text[i] == text[i + 3] &&
          text[i] == text[i + 4]) {
        return true;
      }
    }

    return false;
  }

  bool _containsTextMarkers(String text) {
    String upperText = text.toUpperCase();
    return upperText.contains('VAT') ||
        upperText.contains('NO.') ||
        upperText.contains('NO ') ||
        upperText.contains('NUMBER') ||
        upperText.contains('SERIAL') ||
        upperText.contains('PIN') ||
        upperText.contains(RegExp(r'[A-Z]{3,}'));
  }

  void _analyzeAndClassify(
    TextLine line,
    String cleanText,
    double confidence,
    List<Map<String, dynamic>> pinCandidates,
    List<Map<String, dynamic>> serialCandidates,
  ) {
    bool hasTextMarkers = _containsTextMarkers(line.text);
    double score = _calculateScore(line, cleanText, confidence);
    if (isLikelyPin(cleanText)) {
      double pinBonus = hasTextMarkers ? 0.0 : 0.3;
      if ((scanType == 'Mob' &&
              cleanText.length >= 15 &&
              cleanText.length <= 21) ||
          (scanType != 'Mob' &&
              cleanText.length >= 15 &&
              cleanText.length <= 19)) {
        pinBonus += 0.2;
      }
      if (cleanText.startsWith('6') ||
          cleanText.startsWith('2') ||
          cleanText.startsWith('1') ||
          cleanText.startsWith('0')) {
        pinBonus += 0.05;
      }
      pinCandidates.add({
        'text': cleanText,
        'confidence': confidence,
        'score': score + pinBonus,
        'length': cleanText.length,
      });
      if (_debugOcr)
        print(
          '   ✅ Possible PIN (score: ${score.toStringAsFixed(3)}, conf: ${(confidence * 100).toStringAsFixed(1)}%)',
        );
    }
    if (isLikelySerial(cleanText)) {
      serialCandidates.add({
        'text': cleanText,
        'confidence': confidence,
        'score': score,
        'length': cleanText.length,
      });
      if (_debugOcr)
        print(
          '   ✅ Possible Serial (score: ${score.toStringAsFixed(3)}, conf: ${(confidence * 100).toStringAsFixed(1)}%)',
        );
    }
  }

  void _tryCombiningLines(
    RecognizedText recognizedText,
    List<Map<String, dynamic>> pinCandidates,
  ) {
    print('\n🔄 Trying to combine lines for PIN...');

    for (TextBlock block in recognizedText.blocks) {
      for (int i = 0; i < block.lines.length - 1; i++) {
        String line1 = cleanNumericText(block.lines[i].text);
        String line2 = cleanNumericText(block.lines[i + 1].text);
        String combined = line1 + line2;

        if (isNumeric(combined) && isLikelyPin(combined)) {
          print('   🔗 Found by combining: "$line1" + "$line2" = "$combined"');

          double confidence = 0.4;
          double score = confidence * 1.5 + (combined.length / 80.0);

          pinCandidates.add({
            'text': combined,
            'confidence': confidence,
            'length': combined.length,
          });
        }
      }
    }
  }

  void _selectBestPin(List<Map<String, dynamic>> pinCandidates) {
    if (pinCandidates.isEmpty) {
      pinAlternatives = [];
      print('\n⚠️  No valid PIN detected');
      _printPinTips();
      return;
    }

    // فلترة صارمة: الطول 14 فقط وبدون رموز
    final valid = pinCandidates
        .where(
          (c) =>
              (c['text'] as String).length == 14 &&
              RegExp(r'^\d{14} *$').hasMatch(c['text'] as String),
        )
        .toList();
    valid.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    final mainList = valid.isNotEmpty ? valid : pinCandidates;

    // 🗳️ تطبيق التصويت الجماعي على كل رقم
    if (valid.length >= 2) {
      String votedPin = _voteOnDigits(
        valid.map((c) => c['text'] as String).toList(),
        14,
      );
      if (votedPin.isNotEmpty) {
        print('🗳️ Consensus PIN via voting: $votedPin');
        // إضافة النتيجة المصوت عليها بأعلى ثقة
        mainList.insert(0, {
          'text': votedPin,
          'confidence': 0.99,
          'length': votedPin.length,
          'score': 10.0, // أعلى سكور
        });
      }
    }

    // ترتيب الكل وعرض أعلى 3
    final ranked = List<Map<String, dynamic>>.from(mainList);
    ranked.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    pinAlternatives = ranked.take(3).map((c) => c['text'] as String).toList();

    if (pinAlternatives.isNotEmpty) {
      pin.text = pinAlternatives.first;
      print("\n📋 All PIN options found:");
      for (int i = 0; i < pinAlternatives.length; ++i) {
        final c = ranked[i];
        print(
          '   → ${i + 1}. ${c['text']}\n      Conf: ${((c['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%, Len: ${c['length']}',
        );
      }
    }

    if (pinAlternatives.isEmpty) {
      print('\n⚠️  No valid PIN with required length detected');
      _printPinTips();
    }

    emit(ScanPinSuccess());
  }

  void _selectBestSerial(List<Map<String, dynamic>> serialCandidates) {
    if (serialCandidates.isEmpty) {
      serialAlternatives = [];
      print('\n⚠️  No valid Serial detected\n');
      return;
    }
    // فلترة صارمة: الطول 12 فقط وبدون رموز
    final valid = serialCandidates
        .where(
          (c) =>
              (c['text'] as String).length == 12 &&
              RegExp(r'^\d{12} *$').hasMatch(c['text'] as String),
        )
        .toList();
    valid.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    final mainList = valid.isNotEmpty ? valid : serialCandidates;

    // 🗳️ تطبيق التصويت الجماعي على كل رقم
    if (valid.length >= 2) {
      // 🔧 تطبيق التصحيح التلقائي على كل الـ candidates قبل الـ voting
      List<String> correctedCandidates = valid
          .map((c) => _correctAmbiguousDigits(c['text'] as String))
          .toList();

      String votedSerial = _voteOnDigits(correctedCandidates, 12);
      if (votedSerial.isNotEmpty) {
        print('🗳️ Consensus Serial via voting: $votedSerial');
        // إضافة النتيجة المصوت عليها بأعلى ثقة
        mainList.insert(0, {
          'text': votedSerial,
          'confidence': 0.99,
          'length': votedSerial.length,
          'score': 10.0, // أعلى سكور
        });
      }
    }

    final ranked = List<Map<String, dynamic>>.from(mainList);
    ranked.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    serialAlternatives = ranked
        .take(3)
        .map((c) => c['text'] as String)
        .toList();
    if (serialAlternatives.isNotEmpty) {
      serial.text = serialAlternatives.first;
      print("\n📋 All Serial options found:");
      for (int i = 0; i < serialAlternatives.length; ++i) {
        final c = ranked[i];
        print(
          '   → ${i + 1}. ${c['text']}\n      Conf: ${((c['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%, Len: ${c['length']}',
        );
      }
    }
    if (serialAlternatives.isEmpty) {
      print('\n⚠️  No valid Serial with required length detected');
    }
  }

  /// 🔧 تصحيح الأرقام الملتبسة بناءً على patterns شائعة
  /// يعالج الأخطاء الشائعة: 0↔3, 0↔5, 6↔8, 9↔8
  String _correctAmbiguousDigits(String number) {
    // Serial numbers عادة تبدأ بـ 600... (Zain pattern)
    if (number.length == 12 && number.startsWith('600')) {
      // 🔍 Positions 4-7 عادة تكون بنمط معين في Zain serials
      // Pattern الشائع: 6000xxxxx (4 أصفار في البداية شائع جداً)

      // Check position 4: إذا كان 3 والباقي zeros، غالباً المفروض يكون 0
      if (number[3] == '3' && number[4] == '0' && number[5] == '0') {
        String corrected = number.substring(0, 3) + '0' + number.substring(4);
        print('   🔧 Auto-corrected serial position 4: 3→0 (Zain pattern)');
        return corrected;
      }

      // Check position 7: إذا كان 0 بعد صف zeros، قد يكون 5
      if (number[6] == '0' && number[5] == '0' && number[4] == '0') {
        String corrected = number.substring(0, 6) + '5' + number.substring(7);
        print('   🔧 Auto-corrected serial position 7: 0→5 (Zain pattern)');
        return corrected;
      }
    }
    return number;
  }

  void _printPinResults(
    Map<String, dynamic> selected,
    List<Map<String, dynamic>> all,
  ) {
    print('\n═══════════════════════════════════════════════════════');
    print('🎯 SELECTED PIN: ${pin.text}');
    print(
      '   💯 Confidence: ${(selected['confidence'] * 100).toStringAsFixed(1)}%',
    );
    print('   📏 Length: ${selected['length']}');

    if (selected['confidence'] < 0.7) {
      print('   ⚠️  LOW CONFIDENCE - Please verify manually!');
    }

    if (all.length > 1) {
      print('   📋 All PIN options found:');
      for (int i = 0; i < all.length && i < 5; i++) {
        String marker = i == 0 ? '→' : ' ';
        print('      $marker ${i + 1}. ${all[i]['text']}');
        print(
          '         Conf: ${(all[i]['confidence'] * 100).toStringAsFixed(1)}%, ' +
              'Len: ${all[i]['length']}',
        );
      }
      print('\n   💡 Use controller.selectPinAlternative(index) to change');
    }
    print('═══════════════════════════════════════════════════════');
  }

  void _printSerialResults(
    Map<String, dynamic> selected,
    List<Map<String, dynamic>> all,
  ) {
    print('\n═══════════════════════════════════════════════════════');
    print('🎯 SELECTED SERIAL: ${serial.text}');
    print(
      '   💯 Confidence: ${(selected['confidence'] * 100).toStringAsFixed(1)}%',
    );
    print('   📏 Length: ${selected['length']}');

    if (all.length > 1) {
      print('   📋 All Serial options:');
      for (int i = 0; i < all.length && i < 3; i++) {
        String marker = i == 0 ? '→' : ' ';
        print(
          '      $marker ${i + 1}. ${all[i]['text']} ' +
              '(${(all[i]['confidence'] * 100).toStringAsFixed(1)}%)',
        );
      }
      print('\n   💡 Use controller.selectSerialAlternative(index) to change');
    }
    print('═══════════════════════════════════════════════════════\n');
  }

  void _printPinTips() {
    print('💡 Tips:');
    print('   - Make sure the card is well-lit');
    print('   - Hold camera steady and perpendicular');
    print('   - Focus on the PIN area only');
    print('   - Avoid capturing text labels (VAT, Serial, etc.)');
    print('   - Try different angles if digits like 5/6 are misread');
  }

  // ============== Voting System ==============

  /// 🎯 Tesseract OCR مخصص للأرقام فقط مع تنظيف ذكي
  Future<List<String>> _runTesseractOCR(String imagePath) async {
    try {
      print('   🔍 Running Tesseract OCR on digits...');

      // 🔥 جرب PSM modes مختلفة للحصول على أفضل نتيجة
      List<String> allCandidates = [];

      // PSM 6 = Assume single uniform block of text (الأفضل للأرقام المنظمة)
      try {
        String text = await FlutterTesseractOcr.extractText(
          imagePath,
          language: 'eng',
          args: {
            "psm": "6", // Single uniform block
            "tessedit_char_whitelist": "0123456789",
            "preserve_interword_spaces": "0",
          },
        );

        String cleaned = text.replaceAll(RegExp(r'[^\d]'), '');
        if (cleaned.isNotEmpty) {
          print('   📝 Tesseract PSM 6: "$cleaned"');
          _extractNumberCandidates(cleaned, allCandidates);
        }
      } catch (e) {
        print('   ⚠️ PSM 6 failed: $e');
      }

      // PSM 11 = Sparse text (احتياطي)
      if (allCandidates.isEmpty) {
        try {
          String text = await FlutterTesseractOcr.extractText(
            imagePath,
            language: 'eng',
            args: {
              "psm": "11", // Sparse text
              "tessedit_char_whitelist": "0123456789",
              "preserve_interword_spaces": "0",
            },
          );

          String cleaned = text.replaceAll(RegExp(r'[^\d]'), '');
          if (cleaned.isNotEmpty) {
            print('   📝 Tesseract PSM 11: "$cleaned"');
            _extractNumberCandidates(cleaned, allCandidates);
          }
        } catch (e) {
          print('   ⚠️ PSM 11 failed: $e');
        }
      }

      if (allCandidates.isEmpty) {
        print('   ⚠️ Tesseract found no valid candidates');
      } else {
        print('   ✅ Tesseract found ${allCandidates.length} candidates');
      }

      return allCandidates;
    } catch (e) {
      print('   ❌ Tesseract OCR error: $e');
      return [];
    }
  }

  /// استخراج أرقام PIN (14) و Serial (12) من النص
  void _extractNumberCandidates(String cleaned, List<String> candidates) {
    // بحث عن 14 رقم متتالي (PIN)
    RegExp pinPattern = RegExp(r'\d{14,}');
    var pinMatches = pinPattern.allMatches(cleaned);
    for (var match in pinMatches) {
      String number = match.group(0)!;
      // خد أول 14 رقم
      if (number.length >= 14) {
        String pin = number.substring(0, 14);
        if (!candidates.contains(pin)) {
          candidates.add(pin);
          print('   📌 PIN: $pin');
        }
      }
    }

    // بحث عن 12 رقم متتالي (Serial)
    RegExp serialPattern = RegExp(r'\d{12,}');
    var serialMatches = serialPattern.allMatches(cleaned);
    for (var match in serialMatches) {
      String number = match.group(0)!;
      // خد أول 12 رقم
      if (number.length >= 12 && number.length < 14) {
        String serial = number.substring(0, 12);
        if (!candidates.contains(serial)) {
          candidates.add(serial);
          print('   📌 Serial: $serial');
        }
      }
    }
  }

  /// 🗳️ نظام التصويت الجماعي المحسّن - يصوت على كل رقم في موضعه
  /// 🎯 تصويت ذكي موزون بالثقة - كل رقم ياخد وزن حسب confidence
  /// يأخذ عدة قراءات ويختار الرقم الأكثر وزناً في كل موضع
  String _voteOnDigits(List<String> candidates, int expectedLength) {
    if (candidates.isEmpty) return '';
    if (candidates.length == 1) return candidates.first;

    print('\n🗳️ Starting Enhanced Weighted Voting...');
    print('   📊 ${candidates.length} candidates:');
    for (var c in candidates) {
      print('      - $c');
    }

    // تصفية: نبقي فقط على الأرقام بالطول الصحيح
    final validCandidates = candidates
        .where(
          (c) => c.length == expectedLength && RegExp(r'^\d+$').hasMatch(c),
        )
        .toList();

    if (validCandidates.isEmpty) {
      print('   ❌ No valid candidates for voting');
      return '';
    }
    if (validCandidates.length == 1) return validCandidates.first;

    print('   ✅ ${validCandidates.length} valid candidates for voting');

    // 🔥 نظام تصويت موزون محسّن - كل vote لها وزن متساوي بس نحسب الأغلبية
    List<String> votedDigits = [];
    List<int> lowConfidencePositions = []; // المواضع اللي محتاجة تأكيد

    for (int pos = 0; pos < expectedLength; pos++) {
      Map<String, double> weightedVotes = {};

      // كل candidate يدي vote بوزن 1.0
      for (String candidate in validCandidates) {
        String digit = candidate[pos];
        weightedVotes[digit] = (weightedVotes[digit] ?? 0) + 1.0;
      }

      // اختيار الرقم بأعلى وزن مجموع
      String winnerDigit = '';
      double maxWeight = 0;
      double totalWeight = validCandidates.length.toDouble();

      weightedVotes.forEach((digit, weight) {
        if (weight > maxWeight) {
          maxWeight = weight;
          winnerDigit = digit;
        }
      });

      // 🔍 كشف المواضع ضعيفة الثقة (لو الأوزان متقاربة)
      double winRate = maxWeight / totalWeight;
      bool isLowConfidence = winRate < 0.7; // لو أقل من 70% أغلبية

      if (isLowConfidence) {
        lowConfidencePositions.add(pos);
      }

      // عرض الأوزان للأرقام المتنازع عليها فقط
      if (weightedVotes.length > 1 || isLowConfidence) {
        String voteStr = weightedVotes.entries
            .map((e) => '${e.key}:${e.value.toInt()}')
            .join(', ');
        String confidenceMarker = isLowConfidence ? ' ⚠️ LOW CONFIDENCE' : '';
        print(
          '   📍 Position $pos → Winner: "$winnerDigit" ($voteStr) Win Rate: ${(winRate * 100).toStringAsFixed(1)}%$confidenceMarker',
        );
      }

      votedDigits.add(winnerDigit);
    }

    String result = votedDigits.join('');
    print('   ✅ Final voted result: $result');

    // ⚠️ تحذير إذا فيه مواضع ضعيفة الثقة
    if (lowConfidencePositions.isNotEmpty) {
      print(
        '   ⚠️ Low confidence at positions: ${lowConfidencePositions.join(", ")}',
      );
      print('   💡 Tip: These digits might need manual verification');
    }

    print('');
    return result;
  }

  // ============== Validation Methods ==============

  bool isNumeric(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[0-9?]+$').hasMatch(s); // دعم ? مؤقتًا
  }

  String cleanNumericText(String text) {
    text = text.toUpperCase();
    // تحويل الأرقام العربية-الهندية إلى لاتينية
    text = _normalizeArabicIndicDigits(text);

    // تصحيحات ذكية للأحرف الشبيهة بالأرقام
    text = text
        .replaceAll('D', '0')
        .replaceAll('O', '0')
        .replaceAll('Q', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('Z', '2')
        .replaceAll('S', '5')
        .replaceAll('B', '8')
        .replaceAll('A', '4')
        .replaceAll('?', '7');

    // إزالة الرموز والمسافات
    text = text.replaceAll(RegExp(r'\s'), '').replaceAll(RegExp(r'[-_.]'), '');

    // تطبيق قواعد منطقية للتصحيح بناءً على السياق
    text = _applyContextualCorrections(text);

    // إزالة أي شيء ليس رقماً
    return text.replaceAll(RegExp(r'[^\d]'), '');
  }

  // تطبيق تصحيحات بناءً على السياق المحيط
  String _applyContextualCorrections(String text) {
    String corrected = '';

    for (int i = 0; i < text.length; i++) {
      String current = text[i];
      String prev = i > 0 ? text[i - 1] : '';
      String next = i < text.length - 1 ? text[i + 1] : '';

      // قاعدة 1: إذا كان 'G' محاط بأرقام، فهو غالباً '6'
      if (current == 'G' &&
          (RegExp(r'\d').hasMatch(prev) || RegExp(r'\d').hasMatch(next))) {
        corrected += '6';
        continue;
      }

      // قاعدة 2: إذا كان '5' في نهاية مجموعة من الأصفار، فهو غالباً '5' صحيح
      if (current == '5' && prev == '0' && next == '0') {
        corrected += '5';
        continue;
      }

      // قاعدة 3: إذا كان 'S' محاط بأرقام، فهو غالباً '5'
      if (current == 'S' &&
          (RegExp(r'\d').hasMatch(prev) || RegExp(r'\d').hasMatch(next))) {
        corrected += '5';
        continue;
      }

      // قاعدة 4: نمط متكرر من الأصفار (000) يجب أن يبقى كما هو
      if (current == '0' && prev == '0' && next == '0') {
        corrected += '0';
        continue;
      }

      // قاعدة 5: إذا كان '9' في بداية السلسلة وبعده أرقام صغيرة، قد يكون '0'
      if (current == '9' &&
          i < 3 &&
          (next == '0' || next == '1' || next == '2')) {
        // احتفظ بـ 9 لأنه قد يكون صحيحاً في البطاقات
        corrected += current;
        continue;
      }

      corrected += current;
    }

    return corrected;
  }

  String _normalizeArabicIndicDigits(String input) {
    const Map<String, String> map = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  bool isLikelyPin(String text) {
    if (scanType == 'Mob') {
      return text.length >= 14 && text.length <= 22;
    } else {
      return text.length >= 14 && text.length <= 20;
    }
  }

  bool isLikelySerial(String text) {
    if (scanType == 'Mob') {
      return text.length >= 11 && text.length <= 14; // دعم 11 للحالات الناقصة
    } else {
      return text.length >= 11 && text.length <= 13;
    }
  }

  List<String> filterSerials(List<String> options) =>
      options.where((s) => s.length == 12).toList();

  List<String> filterPins(List<String> options) =>
      options.where((p) => p.length == 14).toList();

  // ============== Alternative Selection ==============

  void selectPinAlternative(int index) {
    if (index >= 0 && index < pinAlternatives.length) {
      pin.text = pinAlternatives[index];
      print('✓ PIN changed to alternative $index: ${pin.text}');
      emit(ScanPinSuccess());
    }
  }

  void selectSerialAlternative(int index) {
    if (index >= 0 && index < serialAlternatives.length) {
      serial.text = serialAlternatives[index];
      print('✓ Serial changed to alternative $index: ${serial.text}');
      emit(Scanning());
    }
  }

  // ============== API Methods ==============

  ScanModel? scanModel;

  Future<void> scan() async {
    emit(ScanLoading());

    try {
      final body = {
        'pin': pin.text.replaceAll(' ', ''),
        'serial': serial.text.replaceAll(' ', ''),
        'phone_type': 'iphone',
        'category_id': '1',
      };

      FormData formData = FormData.fromMap(body);

      if (image != null && await image!.exists()) {
        formData.files.add(
          MapEntry('image', await MultipartFile.fromFile(image!.path)),
        );
      }

      print('📤 Sending data: $body');

      DioHelper.post('scan', true, body: body, formData: formData)
          .then((value) {
            final data = value.data as Map<String, dynamic>;
            if (data['status'] == 1) {
              showSnackBar('تم الارسال بنجاح');
              emit(ScanSuccess());
            } else {
              showSnackBar('خطأ في الارسال');
              emit(ScanError());
            }
          })
          .catchError((error) {
            print('❌ Scan error: ${error.toString()}');
            showSnackBar('حدث خطأ في الاتصال');
            emit(ScanError());
          });
    } catch (e) {
      print('❌ Exception in scan: $e');
      showSnackBar('حدث خطأ غير متوقع');
      emit(ScanError());
    }
  }

  // ============== Cleanup ==============

  @override
  Future<void> close() {
    pin.dispose();
    serial.dispose();
    return super.close();
  }

  // دالة جديدة لتصحيح الأرقام المشكوك فيها في رقم كامل
  Future<String> _correctAmbiguousDigitsInNumber(
    String number,
    TextLine line,
    String imagePath,
  ) async {
    // نُصحح جميع الأرقام المتاحة في templates
    final ambiguousDigits = _templatePaths.keys.toSet(); // 0,3,5,6,8,9

    // فحص إذا كان الرقم يحتوي على أرقام مشكوك فيها
    bool hasAmbiguous = false;
    for (int i = 0; i < number.length; i++) {
      if (ambiguousDigits.contains(number[i])) {
        hasAmbiguous = true;
        break;
      }
    }

    if (!hasAmbiguous) {
      return number; // لا يوجد أرقام مشكوك فيها
    }

    try {
      final bytes = await File(imagePath).readAsBytes();
      imglib.Image? baseImage = imglib.decodeImage(bytes);

      if (baseImage == null) return number;

      final rect = line.boundingBox;

      // قص المنطقة التي تحتوي على السطر الكامل
      int x = (rect.left - 5).toInt().clamp(0, baseImage.width - 1);
      int y = (rect.top - 5).toInt().clamp(0, baseImage.height - 1);
      int w = (rect.width + 10).toInt();
      int h = (rect.height + 10).toInt();

      if (x + w > baseImage.width) w = baseImage.width - x;
      if (y + h > baseImage.height) h = baseImage.height - y;

      if (w < 20 || h < 10) return number; // المنطقة صغيرة جداً

      final lineCrop = imglib.copyCrop(
        baseImage,
        x: x,
        y: y,
        width: w,
        height: h,
      );

      // تقسيم السطر إلى أرقام فردية تقريبياً
      final numDigits = number.length;
      final digitWidth = (w / numDigits).round();

      StringBuffer corrected = StringBuffer();

      for (int i = 0; i < numDigits; i++) {
        final currentDigit = number[i];

        // فقط نصحح الأرقام المشكوك فيها
        if (!ambiguousDigits.contains(currentDigit)) {
          corrected.write(currentDigit);
          continue;
        }

        // قص الرقم الفردي
        int digitX = (i * digitWidth).clamp(0, w - 10);
        int digitW = (digitWidth + 4).clamp(10, w - digitX);

        if (digitX + digitW > w) digitW = w - digitX;

        try {
          final digitCrop = imglib.copyCrop(
            lineCrop,
            x: digitX,
            y: 0,
            width: digitW,
            height: h,
          );

          // معالجة قوية للرقم
          var enhanced = imglib.grayscale(digitCrop);
          enhanced = _sharpenImage(enhanced);
          enhanced = imglib.contrast(enhanced, contrast: 250);
          enhanced = imglib.normalize(enhanced, max: 255, min: 0);

          // تحويل إلى bytes
          final digitBytes = imglib.encodeJpg(enhanced, quality: 100);

          // استخدام template matching
          final (matchedDigit, score) = await matchDigitWithTemplates(
            Uint8List.fromList(digitBytes),
          );

          // نستبدل فقط إذا:
          // 1. OCR غير واثق (confidence منخفضة)
          // 2. وtemplate واثق جداً (score >= 1.3)
          // 3. والرقم المطابق مختلف
          // هذا يمنع التصحيح الخاطئ للأرقام الصحيحة
          if (matchedDigit != '?' &&
              matchedDigit != currentDigit &&
              score >= 1.3) {
            print(
              '   🔧 Digit $i: OCR="$currentDigit" → Template="$matchedDigit" (score: ${score.toStringAsFixed(2)})',
            );
            corrected.write(matchedDigit);
          } else {
            corrected.write(currentDigit);
          }
        } catch (e) {
          print('   ⚠️ Error processing digit $i: $e');
          corrected.write(currentDigit);
        }
      }

      return corrected.toString();
    } catch (e) {
      print('❌ Error in _correctAmbiguousDigitsInNumber: $e');
      return number;
    }
  }

  Future<(String, double)> matchDigitWithTemplates(Uint8List digitBytes) async {
    await _ensureTemplatesLoaded();

    // التحقق من أن القوالب تم تحميلها
    if (_templateMatsCache.isEmpty) {
      print('❌ ERROR: No templates loaded! Cannot perform template matching.');
      return ('?', 0.0);
    }

    const int imreadGray = 0;

    final digitMat = cv.imdecode(digitBytes, imreadGray);

    // توليد variants متعددة للرقم المدخل لزيادة فرص المطابقة الدقيقة
    final variants = <dynamic>[]; // List of Mat

    // 1. الأصلي
    variants.add(digitMat);

    // 2. تطبيق عدة threshold values (أكثر تنوعاً للتعامل مع 0,6,8,9)
    for (double thresh in [100.0, 120.0, 135.0, 150.0, 165.0, 180.0, 200.0]) {
      var (_, threshMat) = cv.threshold(
        digitMat,
        thresh,
        255,
        cv.THRESH_BINARY,
      );
      variants.add(threshMat);
    }

    // 3. تطبيق Adaptive threshold (مهم للأرقام في ظروف إضاءة متفاوتة)
    var adaptThresh = cv.adaptiveThreshold(
      digitMat,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      11,
      2,
    );
    variants.add(adaptThresh);

    // 4. تطبيق Otsu's threshold
    var (_, otsuMat) = cv.threshold(
      digitMat,
      0,
      255,
      cv.THRESH_BINARY + cv.THRESH_OTSU,
    );
    variants.add(otsuMat);

    // 5. Inverted threshold للتعامل مع أرقام بخلفية داكنة
    var (_, invMat) = cv.threshold(digitMat, 140, 255, cv.THRESH_BINARY_INV);
    variants.add(invMat);

    // حساب النتائج مع استخدام عدة طرق للمقارنة
    final results = <String, double>{};
    final methods = [
      cv.TM_CCOEFF_NORMED, // Method 5 - الأفضل للأرقام
      cv.TM_CCORR_NORMED, // Method 3
      cv.TM_SQDIFF_NORMED, // Method 1 (inverted score)
    ];

    for (final entry in _templateMatsCache.entries) {
      final digit = entry.key;
      double bestScore = 0.0;

      for (final templMat in entry.value) {
        for (final v in variants) {
          final templResized = cv.resize(templMat, (v.width, v.height));

          for (int methodIdx = 0; methodIdx < methods.length; methodIdx++) {
            final method = methods[methodIdx];
            final resultMat = cv.matchTemplate(v, templResized, method);
            final (minVal, maxVal, _, __) = cv.minMaxLoc(resultMat);

            double score;
            if (method == cv.TM_SQDIFF_NORMED) {
              // For SQDIFF, lower is better, so invert
              score = 1.0 - minVal;
            } else {
              score = maxVal;
            }

            // وزن أعلى للطريقة الأولى (TM_CCOEFF_NORMED) - الأفضل للأرقام
            double weight = methodIdx == 0 ? 2.0 : 1.0;
            score *= weight;

            // NO BIAS - Let template matching decide fairly

            if (score > bestScore) bestScore = score;
          }
        }
      }

      results[digit] = bestScore;
    }

    print('🔍 Template matching scores: $results');

    final sorted = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) return ('?', 0.0);

    // تحليل النتائج وتطبيق قواعد ذكية
    final first = sorted.first;
    final second = sorted.length > 1 ? sorted[1] : null;

    // early stop مع ثقة عالية جداً
    if (first.value >= 1.5 &&
        (second == null || first.value - second.value >= 0.40)) {
      print(
        '   ✅ Very high confidence: ${first.key} (score: ${first.value.toStringAsFixed(3)})',
      );
      return (first.key, first.value);
    }

    // حالة الثقة العالية
    if (first.value >= 1.2 &&
        (second == null || first.value - second.value >= 0.30)) {
      print(
        '   ✅ High confidence match: ${first.key} (score: ${first.value.toStringAsFixed(3)})',
      );
      return (first.key, first.value);
    }

    // حالة الشك المتوسط: تدوير ومحاولات إضافية
    if (first.value >= 0.85 && first.value < 1.2) {
      print(
        '   ⚠️ Medium confidence: ${first.key} vs ${second?.key ?? "?"} - applying rotation tests...',
      );

      final topDigits = sorted.take(3).map((e) => e.key).toList();

      // تدوير بزوايا مختلفة (مهم للتمييز بين 6 و 9)
      for (int angle in [-4, -3, -2, -1, 1, 2, 3, 4]) {
        var (ok, rotBytes) = cv.imencode('.jpg', cv.rotate(digitMat, angle));
        if (ok) {
          final rotMat = cv.imdecode(rotBytes, imreadGray);

          for (final d in topDigits) {
            double best = results[d] ?? 0.0;
            final templList = _templateMatsCache[d] ?? [];

            for (final templMat in templList) {
              final templResized = cv.resize(templMat, (
                rotMat.width,
                rotMat.height,
              ));
              final resultMat = cv.matchTemplate(
                rotMat,
                templResized,
                cv.TM_CCOEFF_NORMED,
              );
              final (_, maxVal, _, __) = cv.minMaxLoc(resultMat);

              if (maxVal > best) best = maxVal;
            }

            if (best > (results[d] ?? 0.0)) {
              results[d] = best * 1.1; // مكافأة للمطابقة بعد التدوير
            }
          }
        }
      }

      final finalSorted = results.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      print('   🔄 After rotation - scores: $finalSorted');

      if (finalSorted.first.value >= 1.0 &&
          (finalSorted.length == 1 ||
              finalSorted.first.value - finalSorted[1].value >= 0.25)) {
        print('   ✅ Confirmed after rotation: ${finalSorted.first.key}');
        return (finalSorted.first.key, finalSorted.first.value);
      }
    }

    // إذا لم نتأكد بنسبة كافية، نطبق قواعد منطقية للأرقام الملتبسة
    if (first.value < 1.0 ||
        (second != null && first.value - second.value < 0.20)) {
      print(
        '   ⚠️ Ambiguous: ${first.key} (${first.value.toStringAsFixed(3)}) vs ${second?.key ?? "?"} (${second?.value.toStringAsFixed(3) ?? "N/A"})',
      );

      // قواعد منطقية للأرقام الملتبسة الشائعة
      final ambiguous = _resolveAmbiguousDigits(
        first.key,
        second?.key,
        first.value,
        second?.value ?? 0.0,
      );
      if (ambiguous != null) {
        print('   🔧 Resolved ambiguity: $ambiguous');
        return (ambiguous, first.value);
      }
    }

    print(
      '   ✅ Best match: ${first.key} (score: ${first.value.toStringAsFixed(3)})',
    );
    return (first.key, first.value);
  }

  // دالة لحل التباس الأرقام المتشابهة - محسّنة للأرقام 0,6,8,9
  String? _resolveAmbiguousDigits(
    String first,
    String? second,
    double firstScore,
    double secondScore,
  ) {
    if (second == null) return first;

    // الفارق بين النتيجتين
    final diff = firstScore - secondScore;

    // ====== قواعد خاصة مُحسّنة للأرقام المتشابهة جداً ======

    // 1. حالة 6 vs 9: دوران 180 درجة - اختر الأعلى score
    if ((first == '6' && second == '9') || (first == '9' && second == '6')) {
      print('      📌 6/9 ambiguity - choosing based on score');
      return firstScore > secondScore ? first : second;
    }

    // 2. حالة 6 vs 8: اختر الأعلى score
    if ((first == '6' && second == '8') || (first == '8' && second == '6')) {
      print('      📌 6/8 ambiguity - choosing based on score');
      return firstScore > secondScore ? first : second;
    }

    // 3. حالة 6 vs 5: اختر الأعلى score
    if ((first == '6' && second == '5') || (first == '5' && second == '6')) {
      print('      📌 5/6 ambiguity - choosing based on score');
      return firstScore > secondScore ? first : second;
    }

    // 4. حالة 6 vs 0: اختر الأعلى score
    if ((first == '6' && second == '0') || (first == '0' && second == '6')) {
      print('      📌 0/6 ambiguity - choosing based on score');
      return firstScore > secondScore ? first : second;
    }

    // 5. حالة 0 vs 8: اختر الأعلى score
    if ((first == '0' && second == '8') || (first == '8' && second == '0')) {
      print('      📌 0/8 ambiguity - choosing based on score');
      return firstScore > secondScore ? first : second;
    }

    // 6. حالة 0 vs 5: نفضّل الأعلى score
    if ((first == '0' && second == '5') || (first == '5' && second == '0')) {
      if (diff.abs() < 0.15) {
        print('      📌 0/5 ambiguity - choosing based on score');
        return firstScore > secondScore ? first : second;
      }
    }

    // 7. حالة 9 vs 8: تمييز صعب
    if ((first == '9' && second == '8') || (first == '8' && second == '9')) {
      if (diff.abs() < 0.15) {
        print('      📌 9/8 ambiguity - choosing based on higher score');
        return firstScore > secondScore ? first : second;
      }
    }

    // 8. حالة 8 vs 5: نفضّل الأعلى score
    if ((first == '8' && second == '5') || (first == '5' && second == '8')) {
      if (diff.abs() < 0.15) {
        print('      📌 8/5 ambiguity - choosing based on score');
        return firstScore > secondScore ? first : second;
      }
    }

    // 9. حالة 3 vs 8: نادرة
    if ((first == '3' && second == '8') || (first == '8' && second == '3')) {
      if (diff.abs() < 0.15) {
        print('      📌 3/8 ambiguity - choosing based on score');
        return firstScore > secondScore ? first : second;
      }
    }

    // 8. حالة 9 vs 0: دوران 180 درجة
    if ((first == '9' && second == '0') || (first == '0' && second == '9')) {
      if (diff.abs() < 0.12) {
        // إذا الفارق صغير جداً، نفضّل الأعلى score
        print('      📌 9/0 ambiguity - choosing based on score');
        return firstScore > secondScore ? first : second;
      }
    }

    // في حالة وجود فارق معقول (> 0.12)، نختار الأعلى
    if (diff >= 0.12) {
      print(
        '      ✅ Clear difference (${diff.toStringAsFixed(3)}) - choosing ${first}',
      );
      return first;
    }

    if (diff <= -0.12) {
      print(
        '      ✅ Clear difference (${(-diff).toStringAsFixed(3)}) - choosing ${second}',
      );
      return second;
    }

    // غير قادر على الحسم - نرجع الأعلى score
    print('      ⚠️ Unable to resolve confidently - choosing higher score');
    return firstScore >= secondScore ? first : second;
  }

  void correctDigitAmbiguity({
    required List<Map<String, dynamic>> candidates,
    required String originalImagePath,
    required Function(String) onCorrected,
  }) async {
    if (candidates.length < 2) return;
    final base = candidates[0]['text'] as String;
    final other = candidates[1]['text'] as String;
    if (base.length != other.length) return;
    // استخراج أول موضع اختلاف (أو كلها)
    for (int i = 0; i < base.length; i++) {
      if (base[i] != other[i]) {
        // قصّ منطقة حول الرقم المختلف للصورة كاملة
        final bytes = await File(originalImagePath).readAsBytes();
        imglib.Image? img = imglib.decodeImage(bytes);
        if (img == null) continue;
        // اعتبار block واحد وخط واحد، نقيس تقريبياً ...
        int numDigits = base.length;
        int x = (img.width * (i / numDigits)).toInt();
        int w = (img.width ~/ numDigits).clamp(16, 56);
        int h = (img.height ~/ 15).clamp(20, img.height ~/ 3);
        int y = (img.height ~/ 2) - h ~/ 2;
        x = x.clamp(0, img.width - w);
        y = y.clamp(0, img.height - h);
        var crop = imglib.copyCrop(img, x: x, y: y, width: w, height: h);
        crop = imglib.contrast(crop, contrast: 290);
        final path =
            '${Directory.systemTemp.path}/fixdigit_crop_${i}_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path).writeAsBytes(imglib.encodeJpg(crop, quality: 97));
        final input = InputImage.fromFilePath(path);
        final textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );
        final res = await textRecognizer.processImage(input);
        String bestDigit = base[i];
        double bestConf = 0.0;
        for (final block in res.blocks) {
          for (final line in block.lines) {
            String txt = cleanNumericText(line.text);
            if (txt.isNotEmpty && txt.length == 1) {
              // حساب ثقة تقديري (OCR لا يعطي لكل رقم ثقة لكن نقدرها)
              double conf = _calculateConfidence(line);
              if (conf > bestConf) {
                bestDigit = txt;
                bestConf = conf;
              }
            }
          }
        }
        print(
          'تصحيح الخانة $i، قُرئت: ${base[i]}, البديل: ${other[i]}, النتيجة: $bestDigit, ثقة: ${(bestConf * 100).toStringAsFixed(2)}%',
        );
        // دمج الـdigit المصحح مع النتيجة
        String corrected =
            base.substring(0, i) + bestDigit + base.substring(i + 1);
        onCorrected(corrected);
        break;
      }
    }
  }

  List<Map<String, dynamic>> filterValidSerialCandidates(
    List<Map<String, dynamic>> candidates,
  ) {
    // فقط بطول 12 ولا تُقبل نتائج أصغر حتى لو score عالي
    final valid = candidates
        .where((c) => (c['text'] as String).length == 12)
        .toList();
    // إذا أكتر من بنتيجة 12 رقم، اختار الأعلى Score فقط
    if (valid.length > 1) {
      valid.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );
      return [valid.first];
    }
    return valid;
  }
}
