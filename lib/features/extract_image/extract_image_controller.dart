import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as imglib;
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/core/appStorage/scan_model.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import 'package:regexpattern/regexpattern.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
        gray = imglib.contrast(gray, contrast: 160);
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

  // ============== Text Recognition ==============
  Future<void> getText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );

      String fullText = recognizedText.text;
      print('Raw OCR Text:\n$fullText');

      List<String> lines = fullText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      // خريطة التصحيح الشائعة (بما فيها ? → 7)
      Map<String, String> correctionMap = {
        '5': '6',
        '0': '8',
        'O': '0',
        'I': '1',
        'l': '1',
        '?': '7', // تصحيح الـ ? إلى 7
        '!': '1',
        'B': '8',
        'S': '5',
      };

      List<Map<String, dynamic>> pinCandidates = [];
      List<Map<String, dynamic>> serialCandidates = [];

      print('\n═══════════════════════════════════════════════════════');
      print('🔍 Starting Advanced OCR Analysis...');
      print('═══════════════════════════════════════════════════════');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          scannedText += "${line.text}\n";

          String cleanText = cleanNumericText(line.text);

          if (cleanText.length >= 10) {
            print('\n─────────────────────────────────────────────────────');
            print('📝 Original: "${line.text}"');
            print('✨ Cleaned:  "$cleanText"');
            print('📏 Length:   ${cleanText.length}');
            double confidence = _calculateConfidence(line);
            print('💯 Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
          }

          if (isNumeric(cleanText) && cleanText.length >= 10) {
            double confidence = _calculateConfidence(line);
            double score = _calculateScore(line, cleanText, confidence);
            _analyzeAndClassify(
              line,
              cleanText,
              score,
              confidence,
              pinCandidates,
              serialCandidates,
            );
          }
        }
      }

      // دمج السطور للـ PIN إذا لزم الأمر
      if (pinCandidates.isEmpty) {
        _tryCombiningLines(recognizedText, pinCandidates);
      }

      // معالجة ما بعد لتصحيح الأخطاء
      _postProcessCandidates(pinCandidates);
      _postProcessCandidates(serialCandidates);

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

  void _postProcessCandidates(List<Map<String, dynamic>> candidates) {
    List<Map<String, dynamic>> additional = [];
    for (var candidate in candidates) {
      String text = candidate['text'];
      double baseScore = candidate['score'];
      double baseConfidence = candidate['confidence'];

      // إضافة variants لـ 5→6
      List<int> fivePositions = [];
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '5') {
          fivePositions.add(i);
        }
      }

      for (int pos in fivePositions) {
        String variant = text.substring(0, pos) + '6' + text.substring(pos + 1);
        additional.add({
          'text': variant,
          'score': baseScore * 0.95,
          'confidence': baseConfidence * 0.95,
          'length': variant.length,
        });
        print('   🔧 Added variant for 5->6 at position $pos: $variant');
      }

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
          'score': baseScore * 0.98,
          'confidence': baseConfidence * 0.98,
          'length': variant.length,
        });
        print('   🔧 Added variant for ?->7 at position $pos: $variant');
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
    if (isLikelySerial(cleanText) && cleanText.length == 12) score += 0.2;

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
    double score,
    double confidence,
    List<Map<String, dynamic>> pinCandidates,
    List<Map<String, dynamic>> serialCandidates,
  ) {
    bool hasTextMarkers = _containsTextMarkers(line.text);

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
        'score': score + pinBonus,
        'confidence': confidence,
        'length': cleanText.length,
      });

      print(
        '   ✅ Possible PIN (score: ${(score + pinBonus).toStringAsFixed(3)})',
      );
    }

    if (isLikelySerial(cleanText)) {
      serialCandidates.add({
        'text': cleanText,
        'score': score,
        'confidence': confidence,
        'length': cleanText.length,
      });

      print('   ✅ Possible Serial (score: ${score.toStringAsFixed(3)})');
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
            'score': score,
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

    pinCandidates.sort((a, b) => b['score'].compareTo(a['score']));

    pinAlternatives = pinCandidates
        .map((c) => c['text'] as String)
        .toSet()
        .toList();

    var validPins = pinCandidates.where((c) => c['confidence'] >= 0.5).toList();
    if (validPins.isEmpty) validPins = pinCandidates;

    final bestScore = validPins.first['score'];
    final topCandidates = validPins
        .where((c) => (bestScore - c['score']).abs() < 0.2)
        .toList();

    if (topCandidates.length > 1) {
      topCandidates.sort((a, b) {
        int confCompare = b['confidence'].compareTo(a['confidence']);
        if (confCompare != 0) return confCompare;
        return b['length'].compareTo(a['length']);
      });
    }

    pin.text = topCandidates.first['text'];

    _printPinResults(topCandidates.first, pinCandidates);
    emit(ScanPinSuccess());
  }

  void _selectBestSerial(List<Map<String, dynamic>> serialCandidates) {
    if (serialCandidates.isEmpty) {
      serialAlternatives = [];
      print('\n⚠️  No valid Serial detected\n');
      return;
    }

    serialCandidates.sort((a, b) => b['score'].compareTo(a['score']));
    serialAlternatives = serialCandidates
        .map((c) => c['text'] as String)
        .toSet()
        .toList();

    final bestScore = serialCandidates.first['score'];
    final topCandidates = serialCandidates
        .where((c) => (bestScore - c['score']).abs() < 0.1)
        .toList();

    if (topCandidates.length > 1) {
      topCandidates.sort((a, b) {
        int confCompare = b['confidence'].compareTo(a['confidence']);
        if (confCompare != 0) return confCompare;
        return b['length'].compareTo(a['length']);
      });
    }

    serial.text = topCandidates.first['text'];

    _printSerialResults(topCandidates.first, serialCandidates);
  }

  void _printPinResults(
    Map<String, dynamic> selected,
    List<Map<String, dynamic>> all,
  ) {
    print('\n═══════════════════════════════════════════════════════');
    print('🎯 SELECTED PIN: ${pin.text}');
    print('   📊 Score: ${selected['score'].toStringAsFixed(3)}');
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
          '         Score: ${all[i]['score'].toStringAsFixed(3)}, ' +
              'Conf: ${(all[i]['confidence'] * 100).toStringAsFixed(1)}%, ' +
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
    print('   📊 Score: ${selected['score'].toStringAsFixed(3)}');
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
}
