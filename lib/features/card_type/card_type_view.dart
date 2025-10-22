import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qrscanner/common_component/custom_app_bar.dart';
import 'package:qrscanner/constant.dart';
import 'package:qrscanner/core/router/router.dart';
import 'package:qrscanner/features/card_type/card_type_controller.dart';
import 'package:qrscanner/features/card_type/card_type_states.dart';
import 'package:qrscanner/features/extract_image/extract_image_view.dart';

class CardTypeView extends StatelessWidget {
  const CardTypeView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CardTypeController()..getCategories(),
      child: BlocBuilder<CardTypeController, CardTypeStates>(
        builder: (context, state) {
          return Scaffold(
            body: Container(
              decoration: containerDecoration,
              child: ListView(
                children: [
                  const CustomAppBar(text: 'Card Type'),
                  Container(
                    height: MediaQuery.of(context).size.height,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).size.height * 0.1,
                      left: 10,
                      right: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(20),
                        topLeft: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Mob'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.42,
                                height:
                                    MediaQuery.of(context).size.height * 0.2,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(19),
                                  child: Image.asset(
                                    'assets/images/mob1.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Mob'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.42,
                                height:
                                    MediaQuery.of(context).size.height * 0.2,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(19),
                                  child: Image.asset(
                                    'assets/images/mob2.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.05,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Zain'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.44,
                                height:
                                    MediaQuery.of(context).size.height * 0.13,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset(
                                    'assets/images/20.jpeg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Zain'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.44,
                                height:
                                    MediaQuery.of(context).size.height * 0.13,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset(
                                    'assets/images/30.jpeg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.05,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Zain'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.44,
                                height:
                                    MediaQuery.of(context).size.height * 0.13,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset(
                                    'assets/images/50.jpeg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => MagicRouter.navigateTo(
                                const ExtractImageView(scanType: 'Zain'),
                              ),
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.44,
                                height:
                                    MediaQuery.of(context).size.height * 0.13,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset(
                                    'assets/images/100.jpeg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
