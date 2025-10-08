import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/appStorage/app_storage.dart';
import 'package:qrscanner/core/appStorage/user_model.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/core/router/router.dart';
import 'package:qrscanner/features/card_scanner/card_scanner_view.dart';
import 'package:qrscanner/features/login/login_states.dart';

class LogInController extends Cubit<LoginStates>{
  LogInController() : super(LoginInit());

  static LogInController of(context)=>BlocProvider.of(context);
  TextEditingController email =TextEditingController();
  TextEditingController password =TextEditingController();


  final formKey = GlobalKey<FormState>();

  UserModel? userModel;
  void login() {
    emit(LoginLoading());
    final body = {
      'email': email.text,
      'password': password.text,
      'phone': 'samsung'
    };
    print(body);
    DioHelper.post('login', false, body: body).then((value) {
      final data=value.data as Map<String,dynamic>;
      if(data['status']==1){
        userModel=UserModel.fromJson(value.data);
        AppStorage.cacheUserInfo(userModel!);
        MagicRouter.navigateAndPopAll(const CardScannerView());
        emit(LoginSuccess(userModel!));
      }else{
        showSnackBar(data['message']);
        emit(LoginError());
      }

    }).catchError((error){
      print(error.toString());
      emit(LoginError());
    });
  }

}