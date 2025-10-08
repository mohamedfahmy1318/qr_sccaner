import 'package:flutter/material.dart';
import 'package:qrscanner/common_component/custom_app_bar.dart';
import 'package:qrscanner/common_component/custom_button.dart';
import 'package:qrscanner/common_component/custom_text_field.dart';
import 'package:qrscanner/constant.dart';


class SettingsView extends StatelessWidget {
  // ignore: use_super_parameters
  const SettingsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: containerDecoration,
        child: ListView(
          children: [
            const CustomAppBar(
              text: 'Settings',
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
                children: const [
                  CustomTextField(
                    lableText: 'Network IP',
                  ),
                  CustomTextField(
                    lableText: 'Image Qualtiy',
                  ),
                  SizedBox(height: 30,),
                  CustomButton(
                    text: 'Save',
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
