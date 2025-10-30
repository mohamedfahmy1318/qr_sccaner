import 'dart:io';
import 'dart:math' as Math;
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  final int _maxOcrPasses = 2; // أقصى عدد تمريرات OCR (تقليل للتسريع)
  final double _earlyStopConfidence =
      0.82; // ثقة لإيقاف مبكر (رفع بسيط لزيادة الدقة)
  final bool _debugOcr = false; // تقليل اللوغات افتراضياً

  // كاش لقوالب الأرقام كمصفوفات Mat جاهزة (لتفادي I/O والتكرار)
  Map<String, List<String>> _templatePaths = {
    '0': ['assets/digit_templates/template_0.jpeg'],
    '3': ['assets/digit_templates/template_3.jpeg'],
    '5': ['assets/digit_templates/template_5.jpeg'],
    '6': [
      'assets/digit_templates/template_6.jpeg',
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
    for (final entry in _templatePaths.entries) {
      final list = <dynamic>[]; // Mat
      for (final path in entry.value) {
        try {
          if (await File(path).exists()) {
            final bytes = await File(path).readAsBytes();
            final mat = cv.imdecode(bytes, 0); // gray
            list.add(mat);
          }
        } catch (_) {}
      }
      if (list.isNotEmpty) _templateMatsCache[entry.key] = list;
    }
    _templatesLoaded = true;
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

      final processedPath = await _processImageForOcr(safePath);
      await getText(processedPath);
    } catch (e) {
      print('Error: $e');
      emit(ImagePickedError());
    }
  }

  Future<String> _processImageForOcr(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      imglib.Image? img = imglib.decodeImage(bytes);

      if (img != null) {
        if (img.width > 1024) {
          img = imglib.copyResize(img, width: 1024);
        }

        imglib.Image gray = imglib.grayscale(img);
        gray = imglib.gaussianBlur(gray, radius: 1);
        // خريطة الحواف (Sobel) ثم مزجها لزيادة وضوح الحروف
        final edges = _sobelEdges(gray);
        gray = _blendGrayAndEdges(gray, edges, 0.35);
        gray = imglib.contrast(gray, contrast: 170);
        gray = imglib.normalize(gray, max: 255, min: 0);

        final processedBytes = imglib.encodeJpg(gray, quality: 100);

        final tempDir = Directory.systemTemp;
        final tempPath =
            '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(tempPath).writeAsBytes(processedBytes);

        print('✅ Image processed for better OCR: $tempPath');
        return tempPath;
      }
    } catch (e) {
      print('⚠️ Error processing image: $e');
    }
    return imagePath;
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

      // تدوير بسيط ±2 درجات على أول نسخة فقط لتقليل الزمن
      List<imglib.Image> rotated = [];
      for (int i = 0; i < variants.length && i < 1; i++) {
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
    for (final block in blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final txt = element.text.trim();
          if (txt == '6' || txt == '8' || txt == '0' || txt == '5') {
            final rect = element.boundingBox;
            if (rect != null) {
              int x = (rect.left - 8).toInt();
              int y = (rect.top - 8).toInt();
              int w = (rect.width + 16).toInt();
              int h = (rect.height + 16).toInt();
              x = x.clamp(0, base!.width - 1);
              y = y.clamp(0, base.height - 1);
              if (x + w > base.width) w = base.width - x;
              if (y + h > base.height) h = base.height - y;
              final crop = imglib.copyCrop(
                base,
                x: x,
                y: y,
                width: w,
                height: h,
              );
              final enhanced = imglib.contrast(crop!, contrast: 290);
              final tempPath =
                  '${Directory.systemTemp.path}/ocr_digit_${txt}_${DateTime.now().microsecondsSinceEpoch}_$ix.jpg';
              await File(
                tempPath,
              ).writeAsBytes(imglib.encodeJpg(enhanced, quality: 95));

              // إجراء template matching
              final digitBytes = await File(tempPath).readAsBytes();
              final bestDigit = await matchDigitWithTemplates(digitBytes);
              print('Digit ($txt) matched as: $bestDigit');
              // يمكن تخزين النتيجة أو استخدامها لاحقاً هنا أو عند التصحيح
              results.add(tempPath);
              ix++;
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
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      // توليد نسخ معالجة متنوعة للصورة الكاملة
      final originalBytes = await File(imagePath).readAsBytes();
      imglib.Image? img = imglib.decodeImage(originalBytes);
      final List<String> variantPaths = [];
      if (img != null) {
        // النسخة 1: contrast قوي
        final img1 = imglib.contrast(img.clone(), contrast: 220);
        final path1 =
            '${Directory.systemTemp.path}/pre_contrast_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path1).writeAsBytes(imglib.encodeJpg(img1, quality: 95));
        variantPaths.add(path1);
        // النسخة 2: normalize + contrast
        final img2 = imglib.normalize(img.clone(), max: 255, min: 0);
        final c2 = imglib.contrast(img2, contrast: 230);
        final path2 =
            '${Directory.systemTemp.path}/pre_norm_contrast_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path2).writeAsBytes(imglib.encodeJpg(c2, quality: 95));
        variantPaths.add(path2);
        // النسخة 3: Gaussian blur خفيف + contrast متوسط
        var gaussian = imglib.gaussianBlur(img.clone(), radius: 1);
        gaussian = imglib.contrast(gaussian, contrast: 180);
        final path3 =
            '${Directory.systemTemp.path}/pre_blur_contrast_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path3).writeAsBytes(imglib.encodeJpg(gaussian, quality: 95));
        variantPaths.add(path3);
        // النسخة 4: threshold قوي
        final img4 = imglib.grayscale(img.clone());
        final t = manualThreshold(img4, 115);
        final path4 =
            '${Directory.systemTemp.path}/pre_thresh_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await File(path4).writeAsBytes(imglib.encodeJpg(t, quality: 95));
        variantPaths.add(path4);
      }

      List<Map<String, dynamic>> pinCandidates = [];
      List<Map<String, dynamic>> serialCandidates = [];

      print('\n═══════════════════════════════════════════════════════');
      print('🔍 Starting Multi-pass OCR Analysis...');
      print('═══════════════════════════════════════════════════════');

      bool earlyStop = false;
      bool sixEnhanceRun = false;
      for (final path in variantPaths) {
        if (_debugOcr) print('\n🖼️ OCR pass on: $path');
        final inputImage = InputImage.fromFilePath(path);
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );

        String fullText = recognizedText.text;
        if (fullText.trim().isEmpty) continue;
        if (_debugOcr) print('Raw OCR Text (len=${fullText.length})');

        // تحسين موضعي حول العناصر '6'
        if (!sixEnhanceRun) {
          final enhancedSixPaths = await _enhanceAndReOcrSixes(
            imagePath,
            recognizedText.blocks,
            textRecognizer,
          );
          for (final enhPath in enhancedSixPaths) {
            final img = InputImage.fromFilePath(enhPath);
            final ocr = await textRecognizer.processImage(img);
            for (final block in ocr.blocks) {
              for (final line in block.lines) {
                String cleanText = cleanNumericText(line.text);
                if (cleanText.contains('6') ||
                    cleanText.contains('8') ||
                    cleanText.contains('0')) {
                  double conf = _calculateConfidence(line);
                  _analyzeAndClassify(
                    line,
                    cleanText,
                    conf,
                    pinCandidates,
                    serialCandidates,
                  );
                }
              }
            }
          }
          sixEnhanceRun = true;
        }

        for (TextBlock block in recognizedText.blocks) {
          for (TextLine line in block.lines) {
            scannedText += "${line.text}\n";
            String cleanText = cleanNumericText(line.text);

            if (isNumeric(cleanText) &&
                cleanText.length >= 11 &&
                !_containsTextMarkers(line.text)) {
              if (_debugOcr) {
                print(
                  '\n─────────────────────────────────────────────────────',
                );
                print('📝 Original: "${line.text}"');
                print('✨ Cleaned:  "$cleanText"');
                print('📏 Length:   ${cleanText.length}');
              }
              double conf = _calculateConfidence(line);
              if (_debugOcr)
                print('💯 Confidence: ${(conf * 100).toStringAsFixed(1)}%');

              _analyzeAndClassify(
                line,
                cleanText,
                conf,
                pinCandidates,
                serialCandidates,
              );

              // بدائل ذكية (بدون 5→6)
              if (isLikelyPin(cleanText) &&
                  conf >= _earlyStopConfidence &&
                  cleanText.length >= 14) {
                earlyStop = true;
                break;
              }
            }
          }
          if (earlyStop) break;
        }
        if (earlyStop) break;
      }

      // لو ما وقفنا مبكراً من الصورة الأصلية، نولد نسخاً محدودة ونعيد المحاولة
      if (!earlyStop) {
        final generated = await _generateProcessingVariants(imagePath);
        final extraPaths = generated.take(_maxOcrPasses - 1).toList();
        for (final path in extraPaths) {
          if (_debugOcr) print('\n🖼️ OCR pass on: $path');
          final inputImage = InputImage.fromFilePath(path);
          final RecognizedText recognizedText = await textRecognizer
              .processImage(inputImage);

          String fullText = recognizedText.text;
          if (fullText.trim().isEmpty) continue;
          if (_debugOcr) print('Raw OCR Text (len=${fullText.length})');

          for (TextBlock block in recognizedText.blocks) {
            for (TextLine line in block.lines) {
              String cleanText = cleanNumericText(line.text);
              if (isNumeric(cleanText) &&
                  cleanText.length >= 11 &&
                  !_containsTextMarkers(line.text)) {
                double conf = _calculateConfidence(line);
                _analyzeAndClassify(
                  line,
                  cleanText,
                  conf,
                  pinCandidates,
                  serialCandidates,
                );
                if (isLikelyPin(cleanText) &&
                    conf >= _earlyStopConfidence &&
                    cleanText.length >= 14) {
                  earlyStop = true;
                  break;
                }
              }
            }
            if (earlyStop) break;
          }
          if (earlyStop) break;
        }
      }

      // دمج السطور للـ PIN إذا لزم الأمر
      if (pinCandidates.isEmpty) {
        // استخدم آخر recognizedText من آخر تمرير فقط لهذه المحاولة
        // في حال الحاجة المتقدمة يمكننا إعادة الدمج عبر كل التمريرات
        // لكن غالباً آخر تمرير يكون الأفضل بعد التحسينات
      }

      // معالجة ما بعد لتصحيح الأخطاء
      // _postProcessCandidates(pinCandidates);
      // _postProcessCandidates(serialCandidates);

      // إزالة المكررات مع الحفاظ على أعلى سكور
      pinCandidates = _dedupeByTextKeepBest(pinCandidates);
      serialCandidates = _dedupeByTextKeepBest(serialCandidates);

      // اختيار الأفضل
      _selectBestPin(pinCandidates);
      _selectBestSerial(serialCandidates);

      textScanned = false;
      emit(Scanning());
      await textRecognizer.close();
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
    double score = confidence * 1.5;

    if (confidence < 0.75) score *= 0.85;
    if (confidence < 0.70) score *= 0.80;
    if (confidence < 0.65) score *= 0.75;
    if (confidence < 0.60) score *= 0.65;
    if (confidence < 0.50) score *= 0.40;

    score += (cleanText.length / 80.0);

    int symbolCount = line.text.length - cleanText.length;
    if (symbolCount <= 2) score += 0.15;
    if (symbolCount == 0) score += 0.1;

    if (_containsTextMarkers(line.text)) {
      score *= 0.2;
      print('   ⚠️  Contains text/words - likely NOT a number field');
    }

    if (symbolCount > 5) {
      score *= 0.7;
    }

    if (isLikelyPin(cleanText) && cleanText.length == 14) score += 0.2;
    if (isLikelySerial(cleanText) &&
        (cleanText.length == 12 || cleanText.length == 11))
      score += 0.2;

    return score;
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

  // ============== Validation Methods ==============

  bool isNumeric(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[0-9?]+$').hasMatch(s); // دعم ? مؤقتًا
  }

  String cleanNumericText(String text) {
    text = text.toUpperCase();
    // تحويل الأرقام العربية-الهندية إلى لاتينية
    text = _normalizeArabicIndicDigits(text);
    text = text
        .replaceAll('D', '0')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('Z', '2')
        .replaceAll('S', '5')
        .replaceAll('B', '8')
        .replaceAll('G', '6')
        .replaceAll('A', '4')
        .replaceAll('Q', '0')
        .replaceAll('?', '7'); // تصحيح ? إلى 7

    return text
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp(r'[-_.]'), '')
        .replaceAll(RegExp(r'[^\d]'), '');
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

  Future<String> matchDigitWithTemplates(Uint8List digitBytes) async {
    await _ensureTemplatesLoaded();
    const int imreadGray = 0, method = 5;

    final digitMat = cv.imdecode(digitBytes, imreadGray);

    // تقليل المتغيرات لسرعة أعلى: الأصلي + threshold فقط
    var (__, threshMat) = cv.threshold(digitMat, 150, 255, cv.THRESH_BINARY);

    final variants = <dynamic>[digitMat, threshMat]; // Mat فقط

    // حساب النتائج على الكاش مباشرة (دون قراءة ملفات كل مرة)
    final results = <String, double>{};
    for (final entry in _templateMatsCache.entries) {
      final digit = entry.key;
      double best = 0.0;
      for (final templMat in entry.value) {
        for (final v in variants) {
          final templResized = cv.resize(templMat, (v.width, v.height));
          final (minVal, maxVal, _, __) = cv.minMaxLoc(
            cv.matchTemplate(v, templResized, method),
          );
          if (maxVal > best) best = maxVal;
        }
      }
      results[digit] = best;
    }

    if (_debugOcr) print('FAST Template scores: $results');
    final sorted = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return '?';

    // early stop صارم: لو الثقة عالية والفارق واضح لا نكمل أي تحويرات إضافية
    if (sorted.first.value >= 0.85 &&
        (sorted.length == 1 || sorted.first.value - sorted[1].value >= 0.20)) {
      return sorted.first.key;
    }

    // حالة الشك: نضيف تدوير خفيف ±2 فقط ثم نعيد القياس على أعلى رقمين فقط
    final topDigits = sorted.take(2).map((e) => e.key).toList();
    var (ok1, rotP) = cv.imencode('.jpg', cv.rotate(digitMat, 2));
    var (ok2, rotN) = cv.imencode('.jpg', cv.rotate(digitMat, -2));
    final rotPmat = cv.imdecode(rotP, imreadGray);
    final rotNmat = cv.imdecode(rotN, imreadGray);
    final extraVariants = <dynamic>[rotPmat, rotNmat];

    for (final d in topDigits) {
      double best = results[d] ?? 0.0;
      final templList = _templateMatsCache[d] ?? [];
      for (final templMat in templList) {
        for (final v in extraVariants) {
          final templResized = cv.resize(templMat, (v.width, v.height));
          final (minVal, maxVal, _, __) = cv.minMaxLoc(
            cv.matchTemplate(v, templResized, method),
          );
          if (maxVal > best) best = maxVal;
        }
      }
      results[d] = best;
    }

    final finalSorted = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (_debugOcr) print('FINAL Template scores: $finalSorted');

    if (finalSorted.first.value >= 0.85 &&
        (finalSorted.length == 1 ||
            finalSorted.first.value - finalSorted[1].value >= 0.18)) {
      return finalSorted.first.key;
    }
    return '?';
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
