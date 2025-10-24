import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qrscanner/features/extract_image/extact_image_states.dart';
import 'package:qrscanner/features/extract_image/extract_image_controller.dart';
import '../../common_component/custom_app_bar.dart';
import '../../common_component/custom_button.dart';
import '../../constant.dart';

class ExtractImageView extends StatelessWidget {
  final String? scanType;

  const ExtractImageView({super.key, this.scanType});

  Future<bool> saveFile(String url, String fileName,
      Function(int value, int total) onReceiveProgress) async {
    try {
      if (await _requestPermission(Permission.storage)) {
        Directory? directory;
        directory = await getExternalStorageDirectory();
        String newPath = "";
        List<String> paths = directory!.path.split("/");
        for (int x = 1; x < paths.length; x++) {
          String folder = paths[x];
          if (folder != "Android") {
            newPath += "/$folder";
          } else {
            break;
          }
        }
        newPath = '$newPath${DateTime.now()}';
        directory = Directory(newPath);

        ///Created by mahmoud maray
        File saveFile = File("${directory.path}/$fileName");
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        if (await directory.exists()) {
          await Dio().download(url, saveFile.path,
              onReceiveProgress: onReceiveProgress);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _requestPermission(Permission permission) async {
    if (await permission.isGranted) {
      return true;

      ///Created By mahmoud maray
    } else {
      var result = await permission.request();
      if (result == PermissionStatus.granted) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ExtractImageController(scanType),
      child: BlocBuilder<ExtractImageController, ExtractImageStates>(
          builder: (context, state) {
        return Scaffold(
          body: Container(
            decoration: containerDecoration,
            child: ListView(
              children: [
                const CustomAppBar(
                  text: 'Saved Data',
                ),
                Container(
                  height: MediaQuery.of(context).size.height,
                  padding: EdgeInsets.only(
                      top: MediaQuery.of(context).size.height * 0.06,
                      left: 20,
                      right: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(20),
                      topLeft: Radius.circular(20),
                    ),
                  ),
                  child: ListView(
                    children: [
                      Container(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height * 0.28,
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Colors.blueAccent, width: 1.0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ExtractImageController.of(context).image != null
                            ? Image.file(
                                ExtractImageController.of(context).image!)
                            : SizedBox(
                                height: 50,
                                width: 40,
                                child: Padding(
                                  padding: const EdgeInsets.all(50),
                                  child: Image.asset(
                                      'assets/images/screenshot.png',
                                      fit: BoxFit.contain,
                                      height: 50,
                                      width: 50),
                                )),
                      ),
                      const SizedBox(
                        height: 30.0,
                      ),
                      Container(
                        width: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xff869FD8),
                          borderRadius: BorderRadius.circular(5.0),
                        ),
                        padding: const EdgeInsets.all(16.0),
                        child: InkWell(
                          onTap: () {
                            // CardScanOptions scanOptions = const CardScanOptions(
                            //   scanCardHolderName: true,
                            //   // enableDebugLogs: true,
                            //   validCardsToScanBeforeFinishingScan: 5,
                            //   possibleCardHolderNamePositions: [
                            //     CardHolderNameScanPosition.aboveCardNumber,
                            //   ],
                            // );
                            // final CardDetails? cardDetails = await CardScanner.scanCard(scanOptions: scanOptions);
                            // print('daddadadad'+ cardDetails.toString());
                            ExtractImageController.of(context).getImage();
                          },
                          child: const SizedBox(
                            width: 10.0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                ),
                                SizedBox(
                                  width: 10.0,
                                ),
                                Text(
                                  'Camera',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 15.0,
                      ),
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1.0),
                          borderRadius: BorderRadius.circular(
                            5.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('Pin No'),
                            const SizedBox(
                              width: 30.0,
                            ),
                            BlocBuilder<ExtractImageController,
                                ExtractImageStates>(
                              buildWhen: (context, state) =>
                                  state is ScanPinSuccess,
                              builder: (context, state) => Text(
                                ExtractImageController.of(context).pin.text,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 30.0,
                      ),
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1.0),
                          borderRadius: BorderRadius.circular(
                            5.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('Serial'),
                            const SizedBox(
                              width: 30.0,
                            ),
                            BlocBuilder<ExtractImageController,
                                ExtractImageStates>(
                              buildWhen: (context, state) =>
                                  state is ScanPinSuccess,
                              builder: (context, state) => Text(
                                ExtractImageController.of(context).serial.text,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 30.0,
                      ),
                      BlocBuilder<ExtractImageController, ExtractImageStates>(
                        builder: (context, state) => state is ScanLoading
                            ? SizedBox(
                                height: 35,
                                width: 35,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: colorPrimary,
                                  ),
                                ),
                            )
                            : CustomButton(
                                text: 'Save',
                                onPress: () async {
                                  final controller =
                                      context.read<ExtractImageController>();
                                  final messenger =
                                      ScaffoldMessenger.of(context);

                                  if (controller.image == null) {
                                    messenger.showSnackBar(const SnackBar(
                                      content: Text(
                                          'Please capture a card image first.'),
                                    ));
                                    return;
                                  }

                                  await controller.scan();

                                  final fileName = controller.serial.text.isNotEmpty
                                      ? controller.serial.text
                                      : 'scan_${DateTime.now().millisecondsSinceEpoch}';

                                  final saved = await saveFile(
                                    controller.image!.path,
                                    fileName,
                                    (value, total) {},
                                  );

                                  if (!saved) {
                                    messenger.showSnackBar(const SnackBar(
                                      content: Text('Unable to save the image.'),
                                    ));
                                  }
                                }),
                      ),
                      const SizedBox(
                        height: 60.0,
                      ),
                      const Center(child: Text('Nomber of Card is 700'))
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

//import 'package:flutter/cupertino.dart';
//import 'package:flutter/material.dart';
//import 'package:flutter_bloc/flutter_bloc.dart';
//import 'package:qrscanner/features/extract_image/extact_image_states.dart';
//import 'package:qrscanner/features/extract_image/extract_image_controller.dart';
//import '../../common_component/custom_app_bar.dart';
//import '../../common_component/custom_button.dart';
//import '../../constant.dart';
//
//class ExtractImageView extends StatelessWidget {
//  @override
//  Widget build(BuildContext context) {
//    return BlocProvider(create: (context) => ExtractImageController(),
//      child: Scaffold(
//        body: Container(
//          decoration: containerDecoration,
//          child: ListView(
//            children: [
//              const CustomAppBar(
//                text: 'Saved Data',
//              ),
//              BlocBuilder<ExtractImageController,ExtractImageStates>(
//                builder: (context,state){
//                  return Container(
//                    height: MediaQuery.of(context).size.height,
//                    padding: EdgeInsets.only(
//                        top: MediaQuery.of(context).size.height * 0.06,
//                        left: 20,
//                        right: 20),
//                    decoration: const BoxDecoration(
//                      color: Colors.white,
//                      borderRadius: BorderRadius.only(
//                        topRight: Radius.circular(20),
//                        topLeft: Radius.circular(20),
//                      ),
//                    ),
//                    child: ListView(
//                      children: [
//                        Container(
//                          width:MediaQuery.of(context).size.width,
//                          height: MediaQuery.of(context).size.width * 0.4,
//                          child: ExtractImageController.of(context).image != null ?
//                          Image.file(ExtractImageController.of(context).image!,fit: BoxFit.cover,) : Icon(Icons.camera_alt_rounded,
//                            size: 30.0,),
//                          decoration: BoxDecoration(
//                            border: Border.all(
//                                color: Colors.blueAccent,
//                                width: 1.0
//                            ),
//                            borderRadius: BorderRadius.circular(5.0),
//                          ),
//                        ),
//                        SizedBox(
//                          height: 30.0,
//                        ),
//                        Container(
//                          width: 200,
//                          decoration: BoxDecoration(
//                            color: Colors.blueAccent,
//                            borderRadius: BorderRadius.circular(5.0),
//                          ),
//                          padding: EdgeInsets.all(16.0),
//                          child: GestureDetector(
//                            onTap: (){
//                              ExtractImageController.of(context).getImage();
//                            },
//                            child: Row(
//                              mainAxisSize: MainAxisSize.min,
//                              children: [
//                                Icon(Icons.camera_alt,color: Colors.white,),
//                                SizedBox(
//                                  width: 10.0,
//                                ),
//                                Text('Camera',
//                                  style: TextStyle(
//                                      color: Colors.white
//                                  ),),
//                              ],
//                            ),
//                          ),
//                        ),
//                        SizedBox(
//                          height: 15.0,
//                        ),
//
//                        Container(
//                          padding: EdgeInsets.all(16.0),
//                          decoration: BoxDecoration(
//                            border: Border.all(
//                                color: Colors.grey,
//                                width: 1.0
//                            ),
//                            borderRadius: BorderRadius.circular(5.0,),
//                          ),
//                          child: Row(
//                            children: [
//                              Text('Pin No'),
//                              SizedBox(
//                                width: 30.0,
//                              ),
//                              Text('345678987654567',
//                                style: TextStyle(
//                                    color: Colors.grey
//                                ),)
//                            ],
//                          ),
//                        ),SizedBox(
//                          height: 30.0,
//                        ),
//                        Container(
//                          padding: EdgeInsets.all(16.0),
//                          decoration: BoxDecoration(
//                            border: Border.all(
//                                color: Colors.grey,
//                                width: 1.0
//                            ),
//                            borderRadius: BorderRadius.circular(5.0,),
//                          ),
//                          child: Row(
//                            children: [
//                              Text('Pin No'),
//                              SizedBox(
//                                width: 30.0,
//                              ),
//                              Text('345678987654567',
//                                style: TextStyle(
//                                    color: Colors.grey
//                                ),)
//                            ],
//                          ),
//                        ),
//                        SizedBox(
//                          height: 30.0,
//                        ),
//                        CustomButton(
//                            text: 'Save',
//                            onPress: (){
//                            }
//                        ),
//                        SizedBox(
//                          height: 60.0,
//                        ),
//                        Center(child: Text('Nomber of ard is 700'))
//                      ],
//                    ),
//                  );
//                },),
//            ],
//          ),
//        ),
//      ),
//    );
//  }
//}
