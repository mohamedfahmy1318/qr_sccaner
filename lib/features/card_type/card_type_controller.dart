
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qrscanner/common_component/snack_bar.dart';
import 'package:qrscanner/core/dioHelper/dio_helper.dart';
import 'package:qrscanner/features/card_type/card_type_states.dart';

import '../../core/appStorage/get_categories_model.dart';

class CardTypeController extends Cubit<CardTypeStates> {
  CardTypeController() : super(CardTypeInitial());

  static CardTypeController of(context) => BlocProvider.of(context);

  GetCategoriesModel? getCategoriesModel;

  void getCategories() {
    emit(CardTypeLoading());
    DioHelper.get('category')?.then((value) {
      final data = value.data as Map<String, dynamic>;
      getCategoriesModel = GetCategoriesModel.fromJson(data);
      emit(CardTypeSuccess());
    }).catchError((error) {
      print(error.toString());
      emit(CardTypeError());
    });
  }

  void clearData() {
    emit(CardTypeLoading());
    DioHelper.post('delete',true,body: {}).then((value) {
      final data = value.data as Map<String, dynamic>;
      if (data['status'] == 1) {
        showSnackBar('Deleted Sucessfully');
        emit(CardTypeSuccess());
      } else {
        showSnackBar(data['message']);
        emit(CardTypeError());
      }
    }).catchError((error) {
      print(error.toString());
    });
  }
}
