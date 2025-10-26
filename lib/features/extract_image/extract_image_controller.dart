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
  TextEditingController pin = TextEditingController();
  TextEditingController serial = TextEditingController();

  final String? scanType;

  String scannedText = '';
  bool textScanned = false;
  final ImagePicker picker = ImagePicker();
  File? image;

  File? scanImage;

  Future<void> getImage() async {
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.camera,
    );
    if (pickedFile != null) {
      image = File(pickedFile.path);
      scanImage = File(pickedFile.path);
      textScanned = true;
      emit(
        ImagePickedSuccess(),
      ); //rename state as you need if use this code for new project (dont forget make this state in states file)
      await getText(pickedFile.path);
    } else {
      print('No image selected.');
      textScanned = false;
      image = null;
      emit(
        ImagePickedError(),
      ); //rename state as you need if use this code for new project (dont forget make this state in states file)
      scannedText = 'eeeeeeeeeeerrrrrrrrrooooooorrrrrrrr';
    }
  }

  bool isNumeric(String s) {
    return double.tryParse(s) != null;
  }

  // RegExp(r'^[z0-9_.]+$').hasMatch(line.text)

  Future<void> getText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(
      inputImage,
    );
    await textRecognizer.close();
    scannedText = '';
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        scannedText = "$scannedText${line.text}\n";
        print('shshshhsh${block.text}');
        print('shshshhsh${block.text.length}');
        final List<String> parts = block.text.split(' ');
        final String firstPart = parts.isNotEmpty ? parts.first : '';

        if (scanType == 'Mob') {
          if (firstPart.isNumeric()) {
            if (block.text.length == 21) {
              pin.text = block.text;
              emit(ScanPinSuccess());
            }
            if (block.text.length == 13 ||
                block.text.length == 14 ||
                block.text.length == 12) {
              serial.text = block.text;
            }
          }
        } else {
          if (firstPart.isNumeric()) {
            print('shshshhsh${block.text}');
            print('shshshhshllllll${block.text.length}');
            print('bsbsbbsbsb${block.text.split('')}');
            if (block.text.length == 17) {
              print('donnnnne${block.text}');
              pin.text = block.text;
              emit(ScanPinSuccess());
            }
            if (block.text.length == 12) {
              serial.text = block.text;
            }
          }
        }
      }
    }
    textScanned = false;
    emit(Scanning());
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
          if (data['status'] == 1) {
            showSnackBar('تم االارسال بنجاح');
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
}

//import 'dart:io';
//
//import 'package:dio/dio.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
//import 'package:image_picker/image_picker.dart';
//import 'package:qrscanner/core/dioHelper/dio_helper.dart';
//import 'package:qrscanner/features/extract_image/extact_image_states.dart';
//
//import '../../core/appStorage/scan_model.dart';
//
//class ExtractImageController extends Cubit<ExtractImageStates>{
//  ExtractImageController():super(ExtractInitial());
//  static ExtractImageController of(context) => BlocProvider.of(context);
//  var picker = ImagePicker();
//  File? image;
//  Future<void> getImage() async {
//    final pickedFile = await picker.getImage(
//      source: ImageSource.camera,
//    );
//    if (pickedFile != null) {
//      image = File(pickedFile.path);
//      emit(ImagePickedSuccess()); //rename state as you need if use this code for new project (dont forget make this state in states file)
//    } else {
//      print('No image selected.');
//      emit(ImagePickedError()); //rename state as you need if use this code for new project (dont forget make this state in states file)
//    }
//  }
//
//  ScanModel? scanModel;
//  Future<void> scan() async {
//    emit(ScanLoading());
//    final body = {
//      'pin':'6231263625365',
//      'serial': '23623663526',
//      'phone_type': 'iphone',
//      'category_id' : '1',
//    };
//    FormData formData = FormData.fromMap({});
//    formData.files.add(
//      MapEntry('image', await MultipartFile.fromFile(image!.path)),
//    );
//    DioHelper.post('scan', true,body: body,formData: formData)?.then((value){
//      scanModel = ScanModel.fromJson(value.data);
//      emit(ScanSuccess());
//    }).catchError((error){
//      print(error.toString());
//      emit(ScanError());
//    });
//  }
//
//
//
//
//
//
//}
