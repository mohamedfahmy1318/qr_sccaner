import 'package:flutter/material.dart';

var colorPrimary = const Color.fromRGBO(31, 43, 70, 1);
var colorSelectedBN = const Color(0xFF36BFC6);
var colorSecondary = const Color.fromRGBO(233, 239, 255, 1);

var colorLightGrey = const Color(0xFF707070);


BoxDecoration containerDecoration= const BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color.fromRGBO(31, 43, 70, 1),
      Color.fromRGBO(134, 159, 216, 1),
    ],
  ),
);