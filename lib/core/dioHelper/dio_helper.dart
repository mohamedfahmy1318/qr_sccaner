

import 'package:dio/dio.dart';
import 'package:qrscanner/core/appStorage/app_storage.dart';

class DioHelper {
  static const _baseUrl = 'https://bestscan.store/api/v1/';

  static Dio dioSingleton = Dio()..options.baseUrl = _baseUrl;

  static Future<Response<dynamic>> post(String path, bool isAuh,
      {FormData? formData,
      Map<String, dynamic>? body,
      Function(int, int)? onSendProgress}) {
    dioSingleton.options.headers = isAuh
        ? {
            'Authorization': 'Bearer ${AppStorage.getToken}',
//            'Authorization': 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIxIiwianRpIjoiNTNmOWE2MWIwZjZmODk0ZWU3ZjQ0Njc4ZGI4YTg2ZmM3ZThhYTk0NDQ4YzkzMjFkZDQyZTJkY2JhMGM4NWU2ZDA0ODE5ODU0ZmNkMTNhZGEiLCJpYXQiOjE2NzI2NTUzOTkuMzYyNDg1LCJuYmYiOjE2NzI2NTUzOTkuMzYyNDkzLCJleHAiOjE3MDQxOTEzOTkuMzQ3MjksInN1YiI6IjIiLCJzY29wZXMiOltdfQ.DSA5dvSwPWKEZrHBSxfuxvK04dS4pFA8GxYP-6N7P6YI-EqVSbaTVbpvLsLZQECrLHI8hlgMbpN29XRqZfEzictuvgs7FXPK_C1jASFQyjn5HaksINP_WSVoUVq9XUpcbzS0SCJx2XmWiZRCyb3V8YWNBcfy0TDMfbg4yipvcVP5jwGoguFTzW_eMd0FTQNIax28Xl35ww2oEZ0A7fofoBkMLHLlMKyIl3ls7PNI2ezeLjMSD-4E7FTSw81Vw256_DApy-Qy0Md5ZhhbCugRUaC8RbKOavx5d9oJrkjG_mzL9-0PunB-2cJjtKsy4-RxQiHArX8hceQgPV81Cokkpe6M-7JIfi0YmDow1CnjJM1K9oRX4rQ10812jwRY1fCTKQ5zxobpMw7AsGk9z6YUokxZQsr6neO1-zMvW-ZVV4hT3ZrCrfNbqG7zM457u0A5P913vDpDrKcH5Y9EYZUN-lzHB94LEvKaaP64DZIf5yEaN9AfttLtfl_BGnezaQkgPyKhhuOSilJdvJc1kZmBO1njnKwVz-x5CyiRE76cav05FjGy__8Ekispxcrr8oXUp3SAs1wlxjekQ1mOuHdgecs82f0NPidO_MWEgPGh_3UP8drSlVeex3MleoDp9w2a_zkQzuf_1COSsheyY6kw3FHVhpu970mby6vfCu7-XRw',
            'Accept-Language':  'en'
          }
        : null;
    final response = dioSingleton.post(path,
        data: formData ?? FormData.fromMap(body!),
        options: Options(
          
            headers: {
              'Authorization': 'Bearer ${AppStorage.getToken}',
//              'Authorization': 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIxIiwianRpIjoiNTNmOWE2MWIwZjZmODk0ZWU3ZjQ0Njc4ZGI4YTg2ZmM3ZThhYTk0NDQ4YzkzMjFkZDQyZTJkY2JhMGM4NWU2ZDA0ODE5ODU0ZmNkMTNhZGEiLCJpYXQiOjE2NzI2NTUzOTkuMzYyNDg1LCJuYmYiOjE2NzI2NTUzOTkuMzYyNDkzLCJleHAiOjE3MDQxOTEzOTkuMzQ3MjksInN1YiI6IjIiLCJzY29wZXMiOltdfQ.DSA5dvSwPWKEZrHBSxfuxvK04dS4pFA8GxYP-6N7P6YI-EqVSbaTVbpvLsLZQECrLHI8hlgMbpN29XRqZfEzictuvgs7FXPK_C1jASFQyjn5HaksINP_WSVoUVq9XUpcbzS0SCJx2XmWiZRCyb3V8YWNBcfy0TDMfbg4yipvcVP5jwGoguFTzW_eMd0FTQNIax28Xl35ww2oEZ0A7fofoBkMLHLlMKyIl3ls7PNI2ezeLjMSD-4E7FTSw81Vw256_DApy-Qy0Md5ZhhbCugRUaC8RbKOavx5d9oJrkjG_mzL9-0PunB-2cJjtKsy4-RxQiHArX8hceQgPV81Cokkpe6M-7JIfi0YmDow1CnjJM1K9oRX4rQ10812jwRY1fCTKQ5zxobpMw7AsGk9z6YUokxZQsr6neO1-zMvW-ZVV4hT3ZrCrfNbqG7zM457u0A5P913vDpDrKcH5Y9EYZUN-lzHB94LEvKaaP64DZIf5yEaN9AfttLtfl_BGnezaQkgPyKhhuOSilJdvJc1kZmBO1njnKwVz-x5CyiRE76cav05FjGy__8Ekispxcrr8oXUp3SAs1wlxjekQ1mOuHdgecs82f0NPidO_MWEgPGh_3UP8drSlVeex3MleoDp9w2a_zkQzuf_1COSsheyY6kw3FHVhpu970mby6vfCu7-XRw',
              'Accept': 'application/json',
              'Accept-Language':  'en'
            },
            followRedirects: false,
            validateStatus: (status) {
              return status! < 500;
            }),
        onSendProgress: onSendProgress);
    return response;
  }

  static Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) {
    try {
      dioSingleton.options.headers = {
        'Authorization': 'Bearer ${AppStorage.getToken}',
//        'Authorization': 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIxIiwianRpIjoiNTNmOWE2MWIwZjZmODk0ZWU3ZjQ0Njc4ZGI4YTg2ZmM3ZThhYTk0NDQ4YzkzMjFkZDQyZTJkY2JhMGM4NWU2ZDA0ODE5ODU0ZmNkMTNhZGEiLCJpYXQiOjE2NzI2NTUzOTkuMzYyNDg1LCJuYmYiOjE2NzI2NTUzOTkuMzYyNDkzLCJleHAiOjE3MDQxOTEzOTkuMzQ3MjksInN1YiI6IjIiLCJzY29wZXMiOltdfQ.DSA5dvSwPWKEZrHBSxfuxvK04dS4pFA8GxYP-6N7P6YI-EqVSbaTVbpvLsLZQECrLHI8hlgMbpN29XRqZfEzictuvgs7FXPK_C1jASFQyjn5HaksINP_WSVoUVq9XUpcbzS0SCJx2XmWiZRCyb3V8YWNBcfy0TDMfbg4yipvcVP5jwGoguFTzW_eMd0FTQNIax28Xl35ww2oEZ0A7fofoBkMLHLlMKyIl3ls7PNI2ezeLjMSD-4E7FTSw81Vw256_DApy-Qy0Md5ZhhbCugRUaC8RbKOavx5d9oJrkjG_mzL9-0PunB-2cJjtKsy4-RxQiHArX8hceQgPV81Cokkpe6M-7JIfi0YmDow1CnjJM1K9oRX4rQ10812jwRY1fCTKQ5zxobpMw7AsGk9z6YUokxZQsr6neO1-zMvW-ZVV4hT3ZrCrfNbqG7zM457u0A5P913vDpDrKcH5Y9EYZUN-lzHB94LEvKaaP64DZIf5yEaN9AfttLtfl_BGnezaQkgPyKhhuOSilJdvJc1kZmBO1njnKwVz-x5CyiRE76cav05FjGy__8Ekispxcrr8oXUp3SAs1wlxjekQ1mOuHdgecs82f0NPidO_MWEgPGh_3UP8drSlVeex3MleoDp9w2a_zkQzuf_1COSsheyY6kw3FHVhpu970mby6vfCu7-XRw',
        'Accept-Language': 'en'
      };
      final response = dioSingleton.delete(
        path,
        data: body,
        options: Options(
            headers: {
              'Authorization': 'Bearer ${AppStorage.getToken}',
              'Accept': 'application/json',
              'Accept-Language' :'en'
            },
            followRedirects: false,
            validateStatus: (status) {
              return status! < 500;
            }),
      );
      return response;
    } on FormatException catch (_) {
      throw const FormatException("Unable to process the data");
    } catch (e) {
      rethrow;
    }
  }

  static Future<Response<dynamic>>? get(String path) {
    if (AppStorage.isLogged) {
      dioSingleton.options.headers = {
        'Authorization': 'Bearer ${AppStorage.getToken}',
//        'Authorization': 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIxIiwianRpIjoiNTNmOWE2MWIwZjZmODk0ZWU3ZjQ0Njc4ZGI4YTg2ZmM3ZThhYTk0NDQ4YzkzMjFkZDQyZTJkY2JhMGM4NWU2ZDA0ODE5ODU0ZmNkMTNhZGEiLCJpYXQiOjE2NzI2NTUzOTkuMzYyNDg1LCJuYmYiOjE2NzI2NTUzOTkuMzYyNDkzLCJleHAiOjE3MDQxOTEzOTkuMzQ3MjksInN1YiI6IjIiLCJzY29wZXMiOltdfQ.DSA5dvSwPWKEZrHBSxfuxvK04dS4pFA8GxYP-6N7P6YI-EqVSbaTVbpvLsLZQECrLHI8hlgMbpN29XRqZfEzictuvgs7FXPK_C1jASFQyjn5HaksINP_WSVoUVq9XUpcbzS0SCJx2XmWiZRCyb3V8YWNBcfy0TDMfbg4yipvcVP5jwGoguFTzW_eMd0FTQNIax28Xl35ww2oEZ0A7fofoBkMLHLlMKyIl3ls7PNI2ezeLjMSD-4E7FTSw81Vw256_DApy-Qy0Md5ZhhbCugRUaC8RbKOavx5d9oJrkjG_mzL9-0PunB-2cJjtKsy4-RxQiHArX8hceQgPV81Cokkpe6M-7JIfi0YmDow1CnjJM1K9oRX4rQ10812jwRY1fCTKQ5zxobpMw7AsGk9z6YUokxZQsr6neO1-zMvW-ZVV4hT3ZrCrfNbqG7zM457u0A5P913vDpDrKcH5Y9EYZUN-lzHB94LEvKaaP64DZIf5yEaN9AfttLtfl_BGnezaQkgPyKhhuOSilJdvJc1kZmBO1njnKwVz-x5CyiRE76cav05FjGy__8Ekispxcrr8oXUp3SAs1wlxjekQ1mOuHdgecs82f0NPidO_MWEgPGh_3UP8drSlVeex3MleoDp9w2a_zkQzuf_1COSsheyY6kw3FHVhpu970mby6vfCu7-XRw',
        'Accept-Language':  'en'
      };
    }
    final response = dioSingleton.get(path);
    dioSingleton.options.headers = null;
    return response;
  }

  // static Future<void>? launchURL(url) async {
  //   if (!await launch(url)) throw 'Could not launch $url';
  // }
}
