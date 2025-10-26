import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import 'package:regexpattern/regexpattern.dart';
import '../../core/appStorage/scan_model.dart';

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

  final ImagePicker picker = ImagePicker();

  // ============== Image Capture ==============
  Future<void> getImage() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile != null) {
        image = File(pickedFile.path);
        scanImage = File(pickedFile.path);
        textScanned = true;
        emit(ImagePickedSuccess());
        await getText(pickedFile.path);
      } else {
        print('No image selected.');
        textScanned = false;
        image = null;
        emit(ImagePickedError());
      }
    } catch (e) {
      print('Error in getImage: $e');
      emit(ImagePickedError());
    }
  }

  // ============== Text Recognition ==============
  Future<void> getText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      // تجربة مع multiple scripts لدقة أعلى
      List<TextRecognizer> recognizers = [
        TextRecognizer(script: TextRecognitionScript.latin),
      ];

      // تخزين كل النتائج من كل الـ recognizers
      List<RecognizedText> allResults = [];

      for (var recognizer in recognizers) {
        try {
          final result = await recognizer.processImage(inputImage);
          allResults.add(result);
          await recognizer.close();
        } catch (e) {
          print('⚠️ Recognizer failed: $e');
        }
      }

      if (allResults.isEmpty) {
        print('❌ No OCR results');
        emit(ScanError());
        return;
      }

      final RecognizedText recognizedText = allResults.first;

      scannedText = '';

      // تخزين النتائج مع نقاط الثقة والطول
      List<Map<String, dynamic>> pinCandidates = [];
      List<Map<String, dynamic>> serialCandidates = [];

      print('\n═══════════════════════════════════════════════════════');
      print('🔍 Starting Advanced OCR Analysis...');
      print('═══════════════════════════════════════════════════════');

      // ============== Process OCR Results ==============
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          scannedText = "$scannedText${line.text}\n";

          // تنظيف النص
          String cleanText = cleanNumericText(line.text);

          // طباعة النتائج للمراجعة
          if (cleanText.length >= 10) {
            print('\n─────────────────────────────────────────────────────');
            print('📝 Original: "${line.text}"');
            print('✨ Cleaned:  "$cleanText"');
            print('📏 Length:   ${cleanText.length}');

            // حساب درجة الثقة
            double confidence = _calculateConfidence(line);
            print('💯 Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
          }

          // التحقق من أن النص أرقام فقط ويستحق المعالجة
          if (isNumeric(cleanText) && cleanText.length >= 10) {
            // حساب درجة الثقة من العناصر
            double confidence = _calculateConfidence(line);

            // حساب النقاط
            double score = _calculateScore(line, cleanText, confidence);

            // تحليل وتصنيف
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

      // ============== Try Combining Lines for PIN ==============
      if (pinCandidates.isEmpty) {
        _tryCombiningLines(recognizedText, pinCandidates);
      }

      // ============== Select Best PIN ==============
      _selectBestPin(pinCandidates);

      // ============== Select Best Serial ==============
      _selectBestSerial(serialCandidates);

      textScanned = false;
      emit(Scanning());
    } catch (e) {
      print('❌ Error in getText: $e');
      emit(ScanError());
    }
  }

  // ============== Helper Methods ==============

  /// حساب درجة الثقة من عناصر السطر
  double _calculateConfidence(TextLine line) {
    double confidence = 0.0;
    for (TextElement element in line.elements) {
      confidence += element.confidence ?? 0.0;
    }
    return line.elements.isNotEmpty ? confidence / line.elements.length : 0.5;
  }

  /// حساب النقاط بناءً على عدة عوامل
  double _calculateScore(TextLine line, String cleanText, double confidence) {
    double score = confidence * 1.5; // وزن الثقة الأساسي

    // عقوبة للثقة المنخفضة
    if (confidence < 0.75) score *= 0.9;
    if (confidence < 0.65) score *= 0.85;
    if (confidence < 0.5) score *= 0.5;

    // مكافأة للنصوص الأطول
    score += (cleanText.length / 80.0);

    // مكافأة للنصوص النظيفة
    int symbolCount = line.text.length - cleanText.length;
    if (symbolCount <= 2) score += 0.15;
    if (symbolCount == 0) score += 0.1;

    // عقوبة قوية للنصوص التي تحتوي على كلمات
    if (_containsTextMarkers(line.text)) {
      score *= 0.2;
      print('   ⚠️  Contains text/words - likely NOT a number field');
    }

    // عقوبة للنصوص المليئة بالرموز
    if (symbolCount > 5) {
      score *= 0.7;
    }

    return score;
  }

  /// التحقق من وجود كلمات في النص
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

  /// تحليل وتصنيف النص إلى PIN أو Serial
  void _analyzeAndClassify(
    TextLine line,
    String cleanText,
    double score,
    double confidence,
    List<Map<String, dynamic>> pinCandidates,
    List<Map<String, dynamic>> serialCandidates,
  ) {
    bool hasTextMarkers = _containsTextMarkers(line.text);

    // تحليل PIN
    if (isLikelyPin(cleanText)) {
      double pinBonus = hasTextMarkers ? 0.0 : 0.3;

      // مكافأة إضافية للنطاق المثالي
      if ((scanType == 'Mob' &&
              cleanText.length >= 15 &&
              cleanText.length <= 21) ||
          (scanType != 'Mob' &&
              cleanText.length >= 15 &&
              cleanText.length <= 19)) {
        pinBonus += 0.2;
      }

      // مكافأة للأرقام التي تبدأ بأرقام شائعة
      if (cleanText.startsWith('6') ||
          cleanText.startsWith('2') ||
          cleanText.startsWith('1')) {
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

    // تحليل Serial
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

  /// محاولة دمج السطور للحصول على PIN
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

          double confidence = 0.4; // ثقة أقل للمدمج
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

  /// اختيار أفضل PIN
  void _selectBestPin(List<Map<String, dynamic>> pinCandidates) {
    if (pinCandidates.isEmpty) {
      pinAlternatives = [];
      print('\n⚠️  No valid PIN detected');
      _printPinTips();
      return;
    }

    // ترتيب حسب النقاط
    pinCandidates.sort((a, b) => b['score'].compareTo(a['score']));

    // حفظ البدائل
    pinAlternatives = pinCandidates.map((c) => c['text'] as String).toList();

    // استبعاد الخيارات ذات الثقة المنخفضة جداً
    var validPins = pinCandidates.where((c) => c['confidence'] >= 0.5).toList();
    if (validPins.isEmpty) validPins = pinCandidates;

    // اختيار الأفضل
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

  /// اختيار أفضل Serial
  void _selectBestSerial(List<Map<String, dynamic>> serialCandidates) {
    if (serialCandidates.isEmpty) {
      serialAlternatives = [];
      print('\n⚠️  No valid Serial detected\n');
      return;
    }

    serialCandidates.sort((a, b) => b['score'].compareTo(a['score']));
    serialAlternatives = serialCandidates
        .map((c) => c['text'] as String)
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

  // ============== Print Methods ==============

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
  }

  // ============== Validation Methods ==============

  bool isNumeric(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[0-9]+$').hasMatch(s);
  }

  String cleanNumericText(String text) {
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
      return text.length >= 12 && text.length <= 14;
    } else {
      return text.length >= 12 && text.length <= 13;
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
