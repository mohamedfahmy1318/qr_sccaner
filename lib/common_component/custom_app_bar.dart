import 'package:flutter/material.dart';
import 'package:qrscanner/common_component/custom_text.dart';

import '../constant.dart';


class CustomAppBar extends StatelessWidget {
  const CustomAppBar({Key? key, this.text}) : super(key: key);
  final String? text;

  @override
  Widget build(BuildContext context) {
    return   Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const BackButton(
            color: Colors.white,
          ),
          SizedBox(width: MediaQuery.of(context).size.width *0.25,),
          CustomText(
            text: text!,
            alignment: Alignment.center,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: colorSecondary,
          )
        ],
      ),
    );
  }
}
