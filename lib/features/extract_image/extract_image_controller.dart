import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/features/extract_image/card_camera_page.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import '../../core/appStorage/scan_model.dart';
import 'package:image/image.dart' as img;

class ExtractImageController extends Cubit<ExtractImageStates> {
  ExtractImageController(this.scanType) : super(ExtractInitial());

  static ExtractImageController of(context) => BlocProvider.of(context);
  TextEditingController pin = TextEditingController();
  TextEditingController serial = TextEditingController();

  final String? scanType;

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  String scannedText = '';
  bool textScanned = false;
  File? image;
  File? scanImage;

  // ============== Custom Camera مع مربع التحديد ==============
  Future<void> getImage(BuildContext context) async {
    try {
      print('📸 Opening custom camera...');

      // استخدام الكاميرا المخصصة
      final capturedImage = await CardCameraPage.capture(context);

      if (capturedImage == null) {
        print('❌ User cancelled capture');
        textScanned = false;
        image = null;
        scanImage = null;
        emit(ImagePickedError());
        return;
      }

      print('✅ Captured image: ${capturedImage.path}');

      final sourceFile = File(capturedImage.path);
      if (!await sourceFile.exists()) {
        print('❌ Captured file not found');
        showSnackBar('فشل في حفظ الصورة', color: Colors.red);
        emit(ImagePickedError());
        return;
      }

      // نسخ الصورة إلى مكان آمن
      final dir = await getApplicationDocumentsDirectory();
      final safePath =
          '${dir.path}/zain_card_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await sourceFile.copy(safePath);

      if (!await File(safePath).exists()) {
        print('❌ File not copied!');
        showSnackBar('خطأ في حفظ الصورة', color: Colors.red);
        emit(ImagePickedError());
        return;
      }

      image = File(safePath);
      scanImage = null;
      textScanned = true;

      pin.clear();
      serial.clear();

      // مسح المرشحين السابقين
      pinCandidates.clear();
      serialCandidates.clear();

      print('✅ Image saved: $safePath');

      // عرض الصورة الأصلية بالألوان للمستخدم
      scanImage = image;
      emit(ImagePickedSuccess());

      // محاولات متعددة لاستخراج الأرقام بدقة عالية
      print('🔍 Starting OCR with multiple enhancements...');

      // محاولة 1: تحسين خفيف
      final enhanced1 = await enhanceImageForOCR(safePath, threshold: 130);
      await getText(enhanced1, emitScanning: true);

      // محاولة 2: الصورة الأصلية
      print('🔁 Trying original image...');
      await getText(safePath, emitScanning: false);

      // محاولة 3: تحسين متوسط
      print('� Trying medium enhancement...');
      final enhanced2 = await enhanceImageForOCR(safePath, threshold: 150);
      if (enhanced2 != enhanced1) {
        await getText(enhanced2, emitScanning: false);
      }

      // محاولة 4: تحسين عالي
      print('🔁 Trying high enhancement...');
      final enhanced3 = await enhanceImageForOCR(safePath, threshold: 170);
      if (enhanced3 != enhanced1 && enhanced3 != enhanced2) {
        await getText(enhanced3, emitScanning: false);
      }

      // اختيار أفضل نتيجة من جميع المحاولات
      _selectBestResults();
    } catch (e, stackTrace) {
      print('❌ Error in getImage: $e');
      print('Stack trace: $stackTrace');
      textScanned = false;
      image = null;
      scanImage = null;
      showSnackBar('خطأ في تصوير الكارت: $e', color: Colors.red);
      emit(ImagePickedError());
    }
  }

  bool isNumeric(String s) {
    return double.tryParse(s) != null;
  }

  // تحسين الصورة لدقة أعلى في OCR (Contrast + Brightness + Grayscale)
  Future<String> enhanceImageForOCR(
    String imagePath, {
    int threshold = 140,
  }) async {
    print('Enhancing image for OCR with threshold: $threshold...');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final enhancedPath =
          '${dir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final request = _EnhancementRequest(
        sourcePath: imagePath,
        outputPath: enhancedPath,
        threshold: threshold,
        maxWidth: 1600, // زيادة الدقة لتحسين قراءة الأرقام
      );

      final resultPath = await compute(_enhanceImageInIsolate, request);

      if (resultPath != imagePath) {
        print('Enhanced image saved: $resultPath');
      } else {
        print('Using original image for OCR');
      }

      return resultPath;
    } catch (e) {
      print('Error enhancing image: $e, using original');
      return imagePath;
    }
  }

  // تنظيف النص من كل شيء ما عدا الأرقام
  String cleanText(String text) {
    final normalized = _normalizeDigitLookalikes(text);
    return normalized.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _normalizeDigitLookalikes(String input) {
    final buffer = StringBuffer();
    for (final char in input.split('')) {
      switch (char) {
        case 'O':
        case 'o':
          buffer.write('0');
          break;
        case 'S':
        case 's':
          buffer.write('5');
          break;
        case 'G':
        case 'g':
          buffer.write('6');
          break;
        case 'B':
          buffer.write('8');
          break;
        case 'I':
        case 'l':
          buffer.write('1');
          break;
        case 'Z':
        case 'z':
          buffer.write('2');
          break;
        default:
          buffer.write(char);
      }
    }
    return buffer.toString();
  }

  // استخراج كل الأرقام المحتملة من النص (محسّن للسرعة)
  List<String> extractAllNumbers(List<TextBlock> blocks) {
    Set<String> numbers = {}; // استخدام Set لتجنب التكرار مباشرة

    for (var block in blocks) {
      final blockText = block.text.toUpperCase();

      // تجاهل أي Block يحتوي على كلمة VAT أو TAX
      if (blockText.contains('VAT') ||
          blockText.contains('TAX') ||
          blockText.contains('TAXNO') ||
          blockText.contains('ضريب')) {
        print('⚠️ Skipping VAT/TAX block: ${block.text}');
        continue;
      }

      final cleaned = cleanText(block.text);
      if (cleaned.length >= 10) {
        // تجاهل الأرقام التي تبدأ بـ 300 (VAT)
        if (!cleaned.startsWith('300')) {
          numbers.add(cleaned);
        } else {
          print('⚠️ Skipping VAT number from block: $cleaned');
        }
      }

      // استخراج من Lines فقط (أسرع)
      for (var line in block.lines) {
        final lineText = line.text.toUpperCase();

        // تجاهل السطر إذا كان يحتوي على VAT
        if (lineText.contains('VAT') ||
            lineText.contains('TAX') ||
            lineText.contains('ضريب')) {
          print('⚠️ Skipping VAT/TAX line: ${line.text}');
          continue;
        }

        final cleanedLine = cleanText(line.text);
        if (cleanedLine.length >= 10) {
          // تجاهل الأرقام التي تبدأ بـ 300
          if (!cleanedLine.startsWith('300')) {
            numbers.add(cleanedLine);
          } else {
            print('⚠️ Skipping VAT number from line: $cleanedLine');
          }
        }
      }
    }

    return numbers.toList();
  }

  // تخزين المرشحين لاختيار الأفضل
  Map<String, int> pinCandidates = {};
  Map<String, int> serialCandidates = {};

  // البحث عن PIN (14 رقم تحديداً) - محسّن وأسرع
  String? findPIN(List<String> candidates) {
    // فلترة قوية: استبعاد VAT (300) فقط
    final filtered = candidates.where((c) {
      if (c.length < 13 || c.length > 18) return false;

      // استبعاد الرقم الضريبي: يبدأ بـ 300 فقط
      if (c.startsWith('300')) {
        print('❌ Ignored VAT number: $c');
        return false;
      }
      if (c.startsWith('3') && c.length == 15) {
        print('❌ Ignored potential VAT (15 digits starting with 3): $c');
        return false;
      }

      return true;
    }).toList();

    // البحث عن PIN صحيح بطول 14 رقم تحديداً
    for (final value in filtered) {
      if (value.length == 14) {
        return _formatPIN(value);
      }
    }

    for (final value in filtered) {
      if (value.length > 14) {
        return _formatPIN(value.substring(0, 14));
      }
    }

    for (final value in filtered) {
      if (value.length == 13) {
        return _formatPIN('0$value');
      }
    }

    return null;
  }

  // تنسيق رقم الـ PIN بصيغة: 0621 814 1091 663
  String _formatPIN(String pin) {
    if (pin.length != 14) return pin;

    // تقسيم الرقم: 4 أرقام، 3 أرقام، 4 أرقام، 3 أرقام
    return '${pin.substring(0, 4)} ${pin.substring(4, 7)} ${pin.substring(7, 11)} ${pin.substring(11, 14)}';
  }

  // اختيار أفضل نتيجة من جميع المحاولات
  void _selectBestResults() {
    print(
      '📊 Selecting best results from ${pinCandidates.length} PIN candidates and ${serialCandidates.length} serial candidates',
    );

    // اختيار الـ PIN الأكثر تكراراً
    if (pinCandidates.isNotEmpty) {
      var bestPin = pinCandidates.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      // إذا كانت هناك مرشحات متساوية، اختر الذي يبدأ بـ 6 أو 0
      var topCandidates = pinCandidates.entries
          .where((e) => e.value == bestPin.value)
          .toList();
      if (topCandidates.length > 1) {
        // فضّل الأرقام التي تبدأ بـ 6 أو 0
        var preferredStarts = topCandidates.where((e) {
          final cleanPin = e.key.replaceAll(' ', '');
          return cleanPin.startsWith('6') || cleanPin.startsWith('0');
        }).toList();
        if (preferredStarts.isNotEmpty) {
          bestPin = preferredStarts.first;
        }
      }

      pin.text = bestPin.key;
      print('🏆 Best PIN (${bestPin.value} votes): ${pin.text}');
    }

    // اختيار الـ Serial الأكثر تكراراً
    if (serialCandidates.isNotEmpty) {
      var bestSerial = serialCandidates.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      serial.text = bestSerial.key;
      print('🏆 Best Serial (${bestSerial.value} votes): ${serial.text}');
    }

    // عرض النتيجة النهائية
    if (pin.text.isNotEmpty || serial.text.isNotEmpty) {
      emit(ScanPinSuccess());
    }
  } // البحث عن Serial (11-13 رقم) - محسّن

  String? findSerial(List<String> candidates, String? excludePin) {
    const invalidPrefixes = ['300', '142', '141'];

    final filtered = candidates.where((c) {
      if (c == excludePin) return false;
      if (c.length < 11 || c.length > 13) return false;
      if (invalidPrefixes.any((prefix) => c.startsWith(prefix))) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aDistance = (a.length - 12).abs();
      final bDistance = (b.length - 12).abs();
      return aDistance.compareTo(bDistance);
    });

    if (filtered.isNotEmpty) {
      return filtered.first;
    }

    for (final c in candidates) {
      if (c == excludePin) continue;
      if (c.length >= 11 && c.length <= 13) {
        return c;
      }
    }

    return null;
  }

  Future<bool> getText(String imagePath, {bool emitScanning = true}) async {
    print('🔍 Starting Fast OCR...');
    if (emitScanning) {
      emit(Scanning());
    }

    final inputImage = InputImage.fromFilePath(imagePath);

    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );

    // استخراج الأرقام بسرعة
    final initialNumbers = extractAllNumbers(recognizedText.blocks);
    final Set<String> uniqueNumbers = initialNumbers.toSet();

    final normalizedFullText = _normalizeDigitLookalikes(recognizedText.text);
    final digitRuns = RegExp(r'\d{11,16}').allMatches(normalizedFullText);
    for (final match in digitRuns) {
      uniqueNumbers.add(match.group(0)!);
    }

    final List<String> allNumbers = uniqueNumbers.toList();

    // ترتيب حسب الطول (الأطول أولاً)
    allNumbers.sort((a, b) => b.length.compareTo(a.length));

    print('Found ${allNumbers.length} numbers');

    // البحث السريع عن PIN و Serial
    final detectedPin = findPIN(allNumbers);
    final detectedSerial = findSerial(allNumbers, detectedPin);

    bool hasResult = false;

    // تخزين النتائج في المرشحين بدلاً من استبدالها مباشرة
    if (detectedPin != null) {
      pinCandidates[detectedPin] = (pinCandidates[detectedPin] ?? 0) + 1;
      print(
        '✅ PIN candidate: $detectedPin (${pinCandidates[detectedPin]} votes)',
      );
      hasResult = true;
    }

    if (detectedSerial != null) {
      serialCandidates[detectedSerial] =
          (serialCandidates[detectedSerial] ?? 0) + 1;
      print(
        '✅ Serial candidate: $detectedSerial (${serialCandidates[detectedSerial]} votes)',
      );
      hasResult = true;
    }

    textScanned = false;
    return hasResult;
  }

  ScanModel? scanModel;

  Future<void> scan() async {
    emit(ScanLoading());
    final body = {
      'pin': pin.text.replaceAll(' ', ''),
      'serial': serial.text.replaceAll(' ', ''),
      'phone_type': 'iphone',
      'category_id': '1',
    };
    FormData formData = FormData.fromMap(body);
    formData.files.add(
      MapEntry('image', await MultipartFile.fromFile(image!.path)),
    );
    print(body);
    DioHelper.post('scan', true, body: body, formData: formData)
        .then((value) {
          final data = value.data as Map<String, dynamic>;
          print(data);
          if (data['status'] == 1) {
            showSnackBar('تم الارسال بنجاح');
            emit(ScanSuccess());
          } else {
            showSnackBar('error');
            emit(ScanError());
          }
        })
        .catchError((error) {
          print(error.toString());
          emit(ScanError());
        });
  }

  @override
  Future<void> close() async {
    pin.dispose();
    serial.dispose();
    await _textRecognizer.close();
    await super.close();
  }
}

class _EnhancementRequest {
  const _EnhancementRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.threshold,
    required this.maxWidth,
  });

  final String sourcePath;
  final String outputPath;
  final int threshold;
  final int maxWidth;
}

String _enhanceImageInIsolate(_EnhancementRequest request) {
  try {
    final sourceFile = File(request.sourcePath);
    if (!sourceFile.existsSync()) {
      return request.sourcePath;
    }

    final imageBytes = sourceFile.readAsBytesSync();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return request.sourcePath;
    }

    img.Image processed = img.grayscale(decoded);

    // تكبير الصورة للحفاظ على التفاصيل
    if (processed.width > request.maxWidth) {
      final resizedHeight =
          (processed.height * request.maxWidth / processed.width).round();
      processed = img.copyResize(
        processed,
        width: request.maxWidth,
        height: resizedHeight,
        interpolation: img.Interpolation.cubic,
      );
    }

    // تطبيع السطوع (Histogram Equalization)
    final bytes = processed.getBytes();
    int minLuminance = 255;
    int maxLuminance = 0;

    for (int i = 0; i < bytes.length; i += 4) {
      final luminance = bytes[i];
      if (luminance < minLuminance) minLuminance = luminance;
      if (luminance > maxLuminance) maxLuminance = luminance;
    }

    if (maxLuminance > minLuminance) {
      final double scale = 255.0 / (maxLuminance - minLuminance);
      for (int i = 0; i < bytes.length; i += 4) {
        int luminance = bytes[i];
        luminance = ((luminance - minLuminance) * scale).clamp(0, 255).round();
        bytes[i] = luminance;
        bytes[i + 1] = luminance;
        bytes[i + 2] = luminance;
        bytes[i + 3] = 255;
      }
    }

    // تطبيق contrast و brightness بناءً على الـ threshold
    final double contrastBoost = (request.threshold / 120.0).clamp(1.4, 2.2);
    final double brightnessBoost =
        1.12 + ((request.threshold - 140).clamp(-50, 50) / 220.0);

    processed = img.adjustColor(
      processed,
      contrast: contrastBoost,
      brightness: brightnessBoost,
      saturation: 0.0, // إزالة الألوان تماماً للتركيز على التباين
    );

    final enhancedBytes = img.encodeJpg(processed, quality: 98);
    File(request.outputPath).writeAsBytesSync(enhancedBytes, flush: true);

    return request.outputPath;
  } catch (e) {
    // ignore: avoid_print
    print('Enhancement isolate error: $e');
    return request.sourcePath;
  }
}
