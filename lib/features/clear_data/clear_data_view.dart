import 'package:flutter/material.dart';
import 'package:qrscanner/common_component/custom_app_bar.dart';
import 'package:qrscanner/constant.dart';
import 'package:qrscanner/features/clear_data/component/clear_data_card.dart';


class ClearDataView extends StatelessWidget {
  const ClearDataView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: containerDecoration,
        child: ListView(
          children: [
            const CustomAppBar(
              text: 'Clear Data',
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
              child:  ListView.builder(
                shrinkWrap: true,
                physics: const ScrollPhysics(),
                itemCount: 20,
                itemBuilder: (context, index) =>const ClearDataCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
