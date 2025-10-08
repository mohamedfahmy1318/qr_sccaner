import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qrscanner/core/appStorage/my_scans_model.dart';
import 'package:qrscanner/features/saved_data/saved_data_states.dart';
import '../../core/dioHelper/dio_helper.dart';

class SavesDataController extends Cubit<SavedDataStates>{
  SavesDataController() : super(SavedDataInit());

  static SavesDataController of(context)=>BlocProvider.of(context);

  MyScansModel? myScansModel;
  void myScans(){
    emit(SavedDataLoading());
    DioHelper.get('history')?.then((value){
      myScansModel = MyScansModel.fromJson(value.data);
      emit(SavedDataSuccess());
  }).catchError((error){
    print(error.toString());
    emit(SavedDataError());
  });
  }


}