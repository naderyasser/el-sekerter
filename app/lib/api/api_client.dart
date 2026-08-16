import 'package:dio/dio.dart';

import '../core/config.dart';
import '../core/time.dart';
import '../data/settings_store.dart';
import '../models/appointment.dart';
import '../models/chat_message.dart';
import '../models/server_action.dart';

/// خطأ معمول عشان يتعرض للمستخدم زي ما هو.
class ApiException implements Exception {
  ApiException(this.message, {this.isNetwork = false});

  final String message;

  /// مشكلة شبكة (مش رد خطأ من السيرفر) — التطبيق بيعرض «راجع النت».
  final bool isNetwork;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this._settings, {Dio? dio}) : _dio = dio ?? Dio();

  final SettingsStore _settings;
  final Dio _dio;

  Future<ChatResponse> chat({
    required String message,
    required List<Appointment> appointments,
    required List<ChatMessage> history,
    required String timezone,
  }) async {
    final token = await _settings.apiToken();
    if (token == null) {
      throw ApiException(
        'التطبيق مو مضبوط. افتح الإعدادات وحط عنوان السيرفر والتوكن.',
      );
    }

    final baseUrl = await _settings.apiBaseUrl();

    try {
      final response = await _dio.post<Map<String, Object?>>(
        '$baseUrl/api/secretary/chat',
        data: {
          'message': message,
          // وقت الجهاز هو مرجع الموديل في «بكرة» و«بعد ساعتين».
          'now': isoWithOffset(DateTime.now()),
          'timezone': timezone,
          'appointments': appointments
              .map((a) => a.toApi())
              .toList(growable: false),
          'history': history
              .takeLast(AppConfig.historyWindow)
              .map((m) => m.toApi())
              .toList(growable: false),
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: Headers.jsonContentType,
          sendTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
        ),
      );

      final body = response.data;
      if (body == null) throw ApiException('السيرفر رجّع رد فاضي.');
      return ChatResponse.fromJson(body);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Future<bool> ping(String baseUrl, String token) async {
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/secretary/health',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.connectTimeout,
        ),
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  ApiException _translate(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return ApiException(
          'ما أقدر أوصل للسيرفر. راجع النت وعنوان السيرفر.',
          isNetwork: true,
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'السيرفر أخذ وقت طويل. جرّب مرة ثانية.',
          isNetwork: true,
        );
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status == 403) {
      return ApiException('التوكن غلط. راجعه في الإعدادات.');
    }
    if (status == 400) {
      return ApiException('الطلب مرفوض من السيرفر.');
    }

    // 503 بيجي من السيرفر ومعاه رسالة معمولة للعرض؛ استخدمها زي ما هي.
    final detail = (e.response?.data as Map?)?['detail'];
    if (detail is String && detail.isNotEmpty) return ApiException(detail);

    return ApiException('صار خطأ في الاتصال بالسيرفر.');
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => length <= n ? this : skip(length - n);
}
