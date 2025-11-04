import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import '../../core/appStorage/scan_model.dart';
import 'package:image/image.dart' as img;
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

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

  // ============== Document Scanner مع مربع التحديد ==============
  Future<void> getImage(BuildContext context) async {
    try {
      // طلب إذن الكاميرا
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        showSnackBar('يرجى السماح باستخدام الكاميرا', color: Colors.red);
        emit(ImagePickedError());
        return;
      }

      print('📸 Opening document scanner...');

      // استخدام cunning_document_scanner
      final capturedPaths = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
      );

      if (capturedPaths == null || capturedPaths.isEmpty) {
        print('❌ User cancelled capture');
        textScanned = false;
        image = null;
        scanImage = null;
        emit(ImagePickedError());
        return;
      }

      final capturedPath = capturedPaths.first;
      print('✅ Captured image: $capturedPath');

      final sourceFile = File(capturedPath);
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

      print('✅ Image saved: $safePath');

      // إنشاء النسخة المحسّنة أولاً ثم استخدامها في القراءة
      final enhancedPath = await enhanceImageForOCR(safePath, threshold: 150);
      final enhancedFile = File(enhancedPath);
      final hasEnhancedFile =
          enhancedPath != safePath && enhancedFile.existsSync();

      scanImage = hasEnhancedFile ? enhancedFile : image;
      emit(ImagePickedSuccess());

      final primaryPath = hasEnhancedFile ? enhancedPath : safePath;
      final recognized = await getText(primaryPath, emitScanning: true);

      if (_needsEnhancedPass(recognized)) {
        bool secondaryRecognized = recognized;

        if (hasEnhancedFile) {
          secondaryRecognized = await getText(safePath, emitScanning: false);
        }

        if (_needsEnhancedPass(secondaryRecognized)) {
          final softerPath = await enhanceImageForOCR(safePath, threshold: 135);
          final softerFile = File(softerPath);
          if (softerFile.existsSync() && softerPath != primaryPath) {
            scanImage = softerFile;
            emit(ImagePickedSuccess());
            await getText(softerPath, emitScanning: false);
          }
        }
      }
    } catch (e) {
      print('❌ Error in getImage: $e');
      textScanned = false;
      image = null;
      scanImage = null;
      showSnackBar('خطأ في تصوير الكارت. حاول مرة أخرى', color: Colors.red);
      emit(ImagePickedError());
    }
  }

  bool isNumeric(String s) {
    return double.tryParse(s) != null;
  }

  // تحسين الصورة لدقة أعلى في OCR (Contrast + Brightness + Grayscale)
  Future<String> enhanceImageForOCR(
    String imagePath, {
    int threshold = 150,
  }) async {
    print('Enhancing image for better OCR...');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final enhancedPath =
          '${dir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final request = _EnhancementRequest(
        sourcePath: imagePath,
        outputPath: enhancedPath,
        threshold: threshold,
        maxWidth: 1000,
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
    return text.replaceAll(RegExp(r'[^0-9]'), '');
  }

  // استخراج كل الأرقام المحتملة من النص (محسّن للسرعة)
  List<String> extractAllNumbers(List<TextBlock> blocks) {
    Set<String> numbers = {}; // استخدام Set لتجنب التكرار مباشرة

    for (var block in blocks) {
      final cleaned = cleanText(block.text);
      if (cleaned.length >= 10) {
        numbers.add(cleaned);
      }

      // استخراج من Lines فقط (أسرع)
      for (var line in block.lines) {
        final cleanedLine = cleanText(line.text);
        if (cleanedLine.length >= 10) {
          numbers.add(cleanedLine);
        }
      }
    }

    return numbers.toList();
  }

  // البحث عن PIN (14 رقم تحديداً) - محسّن وأسرع
  String? findPIN(List<String> candidates) {
    // فلترة سريعة: استبعاد VAT (300), Service (142, 141)
    final filtered = candidates.where((c) {
      if (c.length < 13 || c.length > 18) return false;
      if (c.startsWith('300') || c.startsWith('142') || c.startsWith('141')) {
        return false;
      }
      return true;
    }).toList();

    for (final value in filtered) {
      if (value.length == 14) {
        return value;
      }
    }

    for (final value in filtered) {
      if (value.length > 14) {
        return value.substring(0, 14);
      }
    }

    for (final value in filtered) {
      if (value.length == 13) {
        return '${value}0';
      }
    }

    return null;
  }

  // البحث عن Serial (11-13 رقم) - محسّن
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
    List<String> allNumbers = extractAllNumbers(recognizedText.blocks);

    // ترتيب حسب الطول (الأطول أولاً)
    allNumbers.sort((a, b) => b.length.compareTo(a.length));

    print('Found ${allNumbers.length} numbers');

    // البحث السريع عن PIN و Serial
    final detectedPin = findPIN(allNumbers);
    final detectedSerial = findSerial(allNumbers, detectedPin);

    bool hasResult = false;

    if (detectedPin != null) {
      if (pin.text != detectedPin) {
        pin.text = detectedPin;
        print('✅ PIN: ${pin.text}');
      }
      hasResult = true;
    }

    if (detectedSerial != null) {
      if (serial.text != detectedSerial) {
        serial.text = detectedSerial;
        print('✅ Serial: ${serial.text}');
      }
      hasResult = true;
    }

    if (pin.text.isNotEmpty || serial.text.isNotEmpty) {
      emit(ScanPinSuccess());
    }

    textScanned = false;
    return hasResult || pin.text.isNotEmpty || serial.text.isNotEmpty;
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

  bool _needsEnhancedPass(bool recognized) {
    if (!recognized) {
      return true;
    }

    final pinValue = pin.text;
    final serialValue = serial.text;

    final hasValidPin = pinValue.length == 14 && _isNumeric(pinValue);
    final hasValidSerial =
        serialValue.length >= 11 &&
        serialValue.length <= 13 &&
        _isNumeric(serialValue);

    if (!hasValidPin || !hasValidSerial) {
      return true;
    }

    return false;
  }

  bool _isNumeric(String value) => RegExp(r'^\d+$').hasMatch(value);
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

    img.Image grayscale = img.grayscale(decoded);

    if (grayscale.width > request.maxWidth) {
      final resizedHeight =
          (grayscale.height * request.maxWidth / grayscale.width).round();
      grayscale = img.copyResize(
        grayscale,
        width: request.maxWidth,
        height: resizedHeight,
        interpolation: img.Interpolation.average,
      );
    }

    img.Image boosted = img.adjustColor(
      grayscale,
      contrast: 1.3,
      brightness: 1.05,
    );

    final thresholdValue = request.threshold.clamp(60, 220).toInt();
    for (int y = 0; y < boosted.height; y++) {
      for (int x = 0; x < boosted.width; x++) {
        final pixel = boosted.getPixel(x, y);
        final luminance = pixel.r;
        final value = luminance > thresholdValue ? 255 : 0;
        boosted.setPixelRgba(x, y, value, value, value, 255);
      }
    }

    final enhancedBytes = img.encodeJpg(boosted, quality: 85);
    File(request.outputPath).writeAsBytesSync(enhancedBytes, flush: true);

    return request.outputPath;
  } catch (e) {
    // ignore: avoid_print
    print('Enhancement isolate error: $e');
    return request.sourcePath;
  }
}
