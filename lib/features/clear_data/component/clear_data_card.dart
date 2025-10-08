import 'package:flutter/material.dart';
import 'package:qrscanner/common_component/custom_text.dart';


class ClearDataCard extends StatelessWidget {
  const ClearDataCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.grey)
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20,horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children:  [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CustomText(
                      text: 'Pin : ',
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                    CustomText(
                      text: '71 7589 578 8717 408',
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ],
                ),
                Row(
                  children: [
                    CustomText(
                      text: 'Serial : ',
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                    CustomText(
                      text: '71 7589 578 8717 408',
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ],
                ),
              ],
            ),
            Image.asset('assets/images/restore.png')
          ],
        ),
      ),
    );
  }
}
