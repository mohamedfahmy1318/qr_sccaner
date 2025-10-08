import 'package:flutter/material.dart';
import 'package:qrscanner/common_component/custom_app_bar.dart';
import 'package:qrscanner/common_component/custom_button.dart';
import 'package:qrscanner/common_component/custom_text.dart';
import 'package:qrscanner/common_component/custom_text_field.dart';
import 'package:qrscanner/constant.dart';

class ScanResultView extends StatelessWidget {
  const ScanResultView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: containerDecoration,
        child: ListView(
          children: [
            const CustomAppBar(
              text: 'Scan Result',
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
                children:  [
                  const CustomTextField(
                    lableText: 'Pin No',
                  ),
                  const CustomTextField(
                    lableText: 'Serial',
                  ),
                  const SizedBox(height: 30,),
                  const CustomButton(
                    text: 'Save',
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height *0.16,),
                  const CustomText(
                    text: 'Number of card is 700',
                    fontSize: 20,
                    color: Colors.black,
                    alignment: Alignment.center,
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
