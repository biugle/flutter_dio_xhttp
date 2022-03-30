// ignore_for_file: unnecessary_this

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

/// 全局网络请求 dio 实例 单例 XHttp
class XHttp {
  static const String GET = "GET";
  static const String POST = "POST";
  static const String PUT = "PUT";
  static const String PATCH = "PATCH";
  static const String DELETE = "DELETE";

  static const CUSTOM_ERROR_CODE = 'DIO_CUSTOM_ERROR'; // 自定义错误代码
  static const REQUEST_TYPE_STR = 'REQUEST'; // 请求类型字符串
  static const RESPONSE_TYPE_STR = 'RESPONSE'; // 响应类型字符串
  static const ERROR_TYPE_STR = 'RESPONSE_ERROR'; // 错误类型字符串
  static const DEFAULT_LOAD_MSG = '请求中...'; // 默认请求提示文字

  static const CONNECT_TIMEOUT = 60000; // 连接超时时间
  static const RECEIVE_TIMEOUT = 60000; // 接收超时时间
  static const SEND_TIMEOUT = 60000; // 发送超时时间

  static const DIALOG_TYPE_OTHERS = 'OTHERS'; // 结果处理-其他类型
  static const DIALOG_TYPE_TOAST = 'TOAST'; // 结果处理-轻提示类型
  static const DIALOG_TYPE_ALERT = 'ALERT'; // 结果处理-弹窗类型
  static const DIALOG_TYPE_CUSTOM = 'CUSTOM'; // 结果处理-自定义处理

  static String loadMsg = DEFAULT_LOAD_MSG; // 请求提示文字

  static String errorShowTitle = '发生错误啦'; // 错误提示标题

  static String errorShowMsg; // 错误提示文字

  static CancelToken cancelToken = CancelToken(); // 取消网络请求 token，默认所有请求都可取消。

  static CancelToken whiteListCancelToken = CancelToken(); // 取消网络请求白名单 token，此 token 不会被取消。

  Map<String, CancelToken> _pendingRequests = {}; // 正在请求列表

  static Dio dio;

  String _getBaseUrl() => 'https://xxx.com';

  /// 通用全局单例，第一次使用时初始化。
  XHttp._internal() {
    if (null == dio) {
      dio = Dio(BaseOptions(
        baseUrl: _getBaseUrl(),
        // contentType: ,
        // responseType: ,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: CONNECT_TIMEOUT,
        receiveTimeout: RECEIVE_TIMEOUT,
        sendTimeout: SEND_TIMEOUT,
        extra: {'cancelDuplicatedRequest': true}, // 是否取消重复请求
      ));
      _init();
    }
  }

  /// 获取单例本身
  static final XHttp _instance = XHttp._internal();

  /// 取消重复的请求
  void _removePendingRequest(String tokenKey) {
    if (_pendingRequests.containsKey(tokenKey)) {
      // 如果在 pending 中存在当前请求标识，需要取消当前请求，并且移除。
      _pendingRequests[tokenKey]?.cancel(tokenKey);
      _pendingRequests.remove(tokenKey);
    }
  }

  /// 初始化 dio
  void _init() {
    // 添加拦截器
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, handler) async {
          if (kDebugMode) {
            print("请求之前");
          }
          if (dio.options.extra['cancelDuplicatedRequest'] == true && options.cancelToken == null) {
            String tokenKey = [
              options.method,
              options.baseUrl + options.path,
              jsonEncode(options.data ?? {}),
              jsonEncode(options.queryParameters ?? {})
            ].join('&');
            _removePendingRequest(tokenKey);
            options.cancelToken = CancelToken();
            options.extra['tokenKey'] = tokenKey;
            _pendingRequests[tokenKey] = options.cancelToken;
          }
          _handleRequest(options, handler);
          // 有 token 时，添加 token。放打印日志后面，避免泄露 token。
          // 也可以登录成功后掉用 XHttp.setToken() 方法设置 token，但是持久化的话还是要这样最好。
          String token = 'Bearer xxxxx';
          if (token != dio.options.headers['authorization']) {
            dio.options.headers['authorization'] = token;
            options.headers['authorization'] = token; // 不设置的话第一次的请求会有问题，上面的是全局设置尚未对本条请求生效。
          }
          return handler.next(options);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) {
          if (kDebugMode) {
            print("响应之前");
          }
          _handleResponse(response, handler);
          RequestOptions option = response.requestOptions;
          if (dio.options.extra['cancelDuplicatedRequest'] == true && option.cancelToken == null) {
            _removePendingRequest(option.extra['tokenKey']);
          }
          String code = (response?.data ?? {})['code'];
          String msg = (response?.data ?? {})['msg'] ?? response.statusMessage;
          // 静态数据 或者 根据后台实际返回结构解析，即 code == '0' 时，data 为有效数据。
          bool isSuccess = option.contentType != null && option.contentType.contains("text") || code == '0';
          response.data = Result(response.data, isSuccess, response.statusCode, msg, headers: response.headers);
          return handler.next(response);
        },
        onError: (DioError error, handler) {
          if (kDebugMode) {
            print("出错之前");
          }
          _handleError(error);
          if (!CancelToken.isCancel(error) && dio.options.extra['cancelDuplicatedRequest'] == true) {
            _pendingRequests.clear(); // 不可抗力错误则清空列表
          }
          // 发生错误同时也会返回一个 Result 结构，通过这个 Result 可以拿到响应状态等信息。
          if (error.response != null && error.response?.data != null) {
            error.response.data = Result(
                error.response.data, false, error.response?.statusCode, errorShowMsg ?? error.response?.statusMessage,
                headers: error.response?.headers);
          } else {
            throw Exception(errorShowMsg);
          }
          return handler.next(error);
        },
      ),
    );
    // print("初始化 Dio 完成\n请求超时限制：$CONNECT_TIMEOUT ms\n接收超时限制：$RECEIVE_TIMEOUT ms\n发送超时限制：$SEND_TIMEOUT ms\nDio-BaseUrl：${dio.options.baseUrl}\nDio-Headers：${dio.options.headers}");
  }

  /// 请求 request 之前统一处理
  void _handleRequest(RequestOptions options, handler) {
    Toast.hide();
    Toast.loading(loadMsg);
    Map logData = {
      'url': options.baseUrl + options.path,
      'method': options.method,
      'headers': options.headers,
      'data': options.data ?? options.queryParameters, // GET 请求参数可以在 url 中，也可以使用 queryParameters，所以需要增加此判断。
    };
    _dealRequestInfo(logData, REQUEST_TYPE_STR);
  }

  /// 响应 response 之前统一处理
  void _handleResponse(Response response, handler) {
    Map logData = {
      'url': response.requestOptions.uri,
      'method': response.requestOptions.method,
      'headers': response.headers,
      'data': response.data,
      'statusCode': response.statusCode,
      'statusMessage': response.statusMessage,
    };
    _dealRequestInfo(logData, RESPONSE_TYPE_STR);
    Toast.hide();
  }

  /// 错误 error 统一处理
  void _handleError(DioError error) {
    // 也可以在此处根据状态码并处理错误信息，例如退出登录等等。
    String errorTypeInfo = '其他错误！';
    switch (error.type) {
      case DioErrorType.connectTimeout:
        errorTypeInfo = '连接超时！';
        break;
      case DioErrorType.sendTimeout:
        errorTypeInfo = "请求超时！";
        break;
      case DioErrorType.receiveTimeout:
        errorTypeInfo = "响应超时！";
        break;
      case DioErrorType.response:
        errorTypeInfo = "服务异常！";
        break;
      case DioErrorType.cancel:
        errorTypeInfo = "请求取消！";
        break;
      case DioErrorType.other:
      default:
        break;
    }
    Map logData = {
      'url': error.requestOptions.baseUrl + error.requestOptions.path,
      'method': error.requestOptions.method,
      'headers': error.response?.headers,
      'data': error.response?.data,
      'statusCode': error.response?.statusCode,
      'statusMessage': error.response?.statusMessage,
      'errorType': error.type,
      'errorMessage': error.message,
      'errorTypeInfo': errorTypeInfo,
    };
    _dealRequestInfo(logData, ERROR_TYPE_STR);
    Toast.hide();
    errorShowMsg =
        "$errorShowTitle ${error.response?.statusCode ?? 'unknown'} $errorTypeInfo \n ${error.response?.statusMessage ?? ''} ${error.message ?? ''} \n ${error.response?.data ?? ''}";
  }

  /// 合并打印请求日志 REQUEST RESPONSE RESPONSE_ERROR
  String _dealRequestInfo(Map logData, String logType) {
    String logStr = "\n";
    logStr += "========================= $logType START =========================\n";
    logStr += "- URL: ${logData['url']} \n";
    logStr += "- METHOD: ${logData['method']} \n";
    // logStr += "- HEADER: \n { \n";
    // logStr += parseData(logData['headers']);
    // logStr += "\n } \n";
    if (logData['data'] != null) {
      logStr += "- ${logType}_BODY: \n";
      logStr += "!!!!!----------*!*##~##~##~##*!*##~##~##~##*!*----------!!!!! \n";
      logStr += "${parseData(logData['data'])} \n";
      logStr += "!!!!!----------*!*##~##~##~##*!*##~##~##~##*!*----------!!!!! \n";
    }
    if (logType.contains(RESPONSE_TYPE_STR)) {
      logStr += "- STATUS_CODE: ${logData['statusCode']} \n";
      logStr += "- STATUS_MSG: ${logData['statusMessage']} \n";
    }
    if (logType == ERROR_TYPE_STR) {
      logStr += "- ERROR_TYPE: ${logData['errorType']} \n";
      logStr += "- ERROR_MSG: ${logData['errorMessage']} \n";
      logStr += "- ERROR_TYPE_INFO: ${logData['errorTypeInfo']} \n";
    }
    logStr += "========================= $logType E N D =========================\n";
    logWrapped(logStr);
    return logStr;
  }

  /// 统一结果提示处理
  Future _showResultDialog(Response response, resultDialogConfig) async {
    if (response == null) {
      return;
    }
    resultDialogConfig = resultDialogConfig ?? {};
    String dialogType = resultDialogConfig['type'] ?? XHttp.DIALOG_TYPE_TOAST;
    if (dialogType == XHttp.DIALOG_TYPE_OTHERS) {
      return; // 其他类型 OTHERS 自定义处理
    }
    bool isSuccess = response?.data?.success ?? false;
    String msg = response?.data?.msg ?? '未知错误';
    if (dialogType == XHttp.DIALOG_TYPE_TOAST) {
      // resultDialogConfig 可以有 successMsg, errorMsg
      isSuccess
          ? Toast.show(resultDialogConfig['successMsg'] ?? msg, type: Toast.SUCCESS)
          : Toast.show(resultDialogConfig['errorMsg'] ?? msg, type: Toast.ERROR);
      return;
    }
    if (dialogType == XHttp.DIALOG_TYPE_ALERT) {
      // resultDialogConfig 可以有 title, content, closeable, showCancel, cancelText, confirmText, confirmCallback, cancelCallback, closeCallback ...
      // Utils.showDialog(...);
      return;
    }
    if (dialogType == XHttp.DIALOG_TYPE_CUSTOM) {
      // resultDialogConfig 可以有 onSuceess, onError
      if (isSuccess) {
        if (resultDialogConfig['onSuccess'] != null) {
          resultDialogConfig['onSuccess'](response.data);
        }
      } else {
        if (resultDialogConfig['onError'] != null) {
          resultDialogConfig['onError'](response.data);
        }
      }
    }
  }

  /// 处理异常
  void _catchOthersError(e) {
    String errMsg = "${errorShowMsg ?? e}$CUSTOM_ERROR_CODE".split(CUSTOM_ERROR_CODE)[0];
    int errMsgLength = errMsg.length;
    String errshowMsg = errMsgLength > 300 ? errMsg.substring(0, 150) : errMsg;
    if (e is DioError) {
      if (CancelToken.isCancel(e)) {
        Toast.show('Cancel Request Successful'); // 取消重复请求可能会多次弹窗
        return;
      }
      Toast.show(errshowMsg, type: Toast.WARNING);
      return;
    }
    Toast.show(errshowMsg + "\n......", type: Toast.ERROR);
  }

  /// 本可以直接 XHttp.xxx 调用（添加 static 关键字给之后的 get/post 等方法），但是考虑多台服务器的情况，建议 XHttp.getInstance().xxx 调用。
  static XHttp getInstance({String baseUrl, String msg}) {
    String targetBaseUrl = baseUrl ?? _instance._getBaseUrl();
    loadMsg = msg ?? DEFAULT_LOAD_MSG;
    if (dio.options.baseUrl != targetBaseUrl) {
      dio.options.baseUrl = targetBaseUrl;
    }
    return _instance;
  }

  /// 取消普通请求
  static XHttp cancelRequest() {
    Toast.hide();
    if (dio.options.extra['cancelDuplicatedRequest'] == true) {
      _instance._pendingRequests.forEach((tokenKey, cancelToken) {
        cancelToken.cancel('cancel request $tokenKey');
      });
    } else {
      cancelToken.cancel('cancel request');
      cancelToken = CancelToken(); // 坑！取消后必须重新创建 cancelToken 否则后面使用原来 cancelToken 的请求会无效
    }
    return _instance;
  }

  /// 取消所有白名单 cancelToken 的请求
  static XHttp cancelWhiteListRequest() {
    Toast.hide();
    whiteListCancelToken.cancel('cancel whiteList request');
    whiteListCancelToken = CancelToken();
    return _instance;
  }

  /// 获取 cancelToken
  static CancelToken getCancelToken() {
    return cancelToken;
  }

  /// 获取 whiteListCancelToken
  static CancelToken getWhiteListCancelToken() {
    return whiteListCancelToken;
  }

  /// 获取一个新的 cancelToken
  static CancelToken getNewCancelToken() {
    return CancelToken();
  }

  /// get 请求
  Future get(String url, [Map<String, dynamic> params, resultDialogConfig, bool isCancelWhiteList = false]) async {
    // 可转为使用 request 代替，简化代码。
    // 写中括号可以忽略参数名称，因为必须按顺序传参。
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      if (params != null) {
        response = await dio.get(url, queryParameters: params, cancelToken: requestToken);
        return response.data;
      } else {
        response = await dio.get(url, cancelToken: requestToken);
        return response.data;
      }
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  /// post 请求
  Future post(String url, [Map<String, dynamic> data, resultDialogConfig, bool isCancelWhiteList = false]) async {
    // 可转为使用 request 代替，简化代码。
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      response = await dio.post(url, data: data, cancelToken: requestToken);
      return response.data;
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  /// put 请求
  Future put(String url, [Map<String, dynamic> data, resultDialogConfig, bool isCancelWhiteList = false]) async {
    // 可转为使用 request 代替，简化代码。
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      response = await dio.put(url, data: data, cancelToken: requestToken);
      return response.data;
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  /// patch 请求
  Future patch(String url, [Map<String, dynamic> data, resultDialogConfig, bool isCancelWhiteList = false]) async {
    // 可转为使用 request 代替，简化代码。
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      response = await dio.patch(url, data: data, cancelToken: requestToken);
      return response.data;
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  /// delete 请求
  Future delete(String url, [Map<String, dynamic> data, resultDialogConfig, bool isCancelWhiteList = false]) async {
    // 可转为使用 request 代替，简化代码。
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      response = await dio.delete(url, data: data, cancelToken: requestToken);
      return response.data;
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  /// request
  static Future request(
    String url, {
    String method = XHttp.GET,
    Map<String, dynamic> queryParameters,
    Map<String, dynamic> data,
    bool isCancelWhiteList = false,
    resultDialogConfig,
    Options options,
    void Function(int, int) onSendProgress,
    void Function(int, int) onReceiveProgress,
    String msg,
    String baseUrl,
  }) async {
    XHttp.getInstance(baseUrl: baseUrl, msg: msg);
    Response response;

    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }

    try {
      response = await dio.request(
        url,
        options: options ?? Options(method: method, contentType: Headers.formUrlEncodedContentType),
        queryParameters: queryParameters,
        data: data,
        cancelToken: requestToken,
        onReceiveProgress: onReceiveProgress,
        onSendProgress: onSendProgress,
      );
      return response.data;
    } catch (e) {
      _instance._catchOthersError(e);
    } finally {
      _instance._showResultDialog(
        response,
        resultDialogConfig ?? {'type': XHttp.DIALOG_TYPE_OTHERS},
      ); // request 请求默认都需自己处理结果
    }
  }

  /// 下载文件
  Future downloadFile(urlPath, savePath, [resultDialogConfig, bool isCancelWhiteList = false]) async {
    Response response;
    var requestToken;
    if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
      if (isCancelWhiteList) {
        requestToken = whiteListCancelToken;
      } else {
        requestToken = cancelToken;
      }
    }
    try {
      response = await dio.download(urlPath, savePath, onReceiveProgress: (int count, int total) {
        // 进度
        print("$count $total");
      }, cancelToken: requestToken);
      return response.data;
    } catch (e) {
      _catchOthersError(e);
    } finally {
      _showResultDialog(response, resultDialogConfig);
    }
  }

  // /// post 表单请求 【Web】
  // Future postForm(String url, [Map<String, dynamic> params, resultDialogConfig, bool isCancelWhiteList = false]) async {
  //   Response response;
  //   var requestToken;
  //   if (dio.options.extra['cancelDuplicatedRequest'] != true || isCancelWhiteList) {
  //     if (isCancelWhiteList) {
  //       requestToken = whiteListCancelToken;
  //     } else {
  //       requestToken = cancelToken;
  //     }
  //   }
  //   try {
  //     response = await dio.post(url, queryParameters: params, cancelToken: requestToken);
  //     return response.data;
  //   } catch (e) {
  //     _catchOthersError(e);
  //   } finally {
  //     _showResultDialog(response, resultDialogConfig);
  //   }
  // }

  /// +++++++++++++++++++++++++ 小扩展 【待增加：retry、代理/proxy、根据状态码自动退出与重连等】 +++++++++++++++++++++++++

  /// 获取当前的 baseUrl
  static String getBaseUrl() {
    return dio.options.baseUrl;
  }

  /// 设置当前的 baseUrl
  static XHttp setBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
    return _instance;
  }

  /// 获取当前 headers
  static Map getHeaders() {
    return dio.options.headers;
  }

  /// 获取当前 headers 属性
  static dynamic getHeader(String key) {
    return dio.options.headers[key];
  }

  /// 设置当前 headers
  static XHttp setHeaders(Map headers) {
    dio.options.headers = headers;
    return _instance;
  }

  /// 设置当前 headers 属性
  static XHttp setHeader(String key, String value) {
    dio.options.headers[key] = value;
    return _instance;
  }

  /// 删除当前的请求头属性
  static XHttp removeHeader(String key) {
    dio.options.headers.remove(key);
    return _instance;
  }

  /// 删除当前的所有请求头属性
  static XHttp removeAllHeaders() {
    dio.options.headers.clear();
    return _instance;
  }

  /// 获取当前的所有超时时间
  static Map getRequestTimeout() {
    return {
      'connectTimeout': dio.options.connectTimeout,
      'receiveTimeout': dio.options.receiveTimeout,
      'sendTimeout': dio.options.sendTimeout
    };
  }

  /// 设置当前的所有超时时间
  static XHttp setRequestTimeout(int timeout) {
    dio.options.connectTimeout = timeout;
    dio.options.receiveTimeout = timeout;
    dio.options.sendTimeout = timeout;
    return _instance;
  }

  /// 设置当前的连接超时时间
  static XHttp setConnectTimeout(int timeout) {
    dio.options.connectTimeout = timeout;
    return _instance;
  }

  /// 设置当前的接收超时时间
  static XHttp setReceiveTimeout(int timeout) {
    dio.options.receiveTimeout = timeout;
    return _instance;
  }

  /// 设置当前的发送超时时间
  static XHttp setSendTimeout(int timeout) {
    dio.options.sendTimeout = timeout;
    return _instance;
  }

  /// 获取用户数据
  static Map<String, dynamic> getAuthUser() {
    String token = dio.options.headers['authorization'];
    if (null == token) {
      return null;
    }
    // 解析token
    return {'account': 'xxx', 'name': 'xxx', 'roles': 'xxx'};
  }

  /// 设置当前 token
  static XHttp setAuthToken([String token]) {
    if (null == token) {
      dio.options.headers.remove('authorization');
    } else {
      dio.options.headers['authorization'] = token;
    }
    return _instance;
  }

  /// 设置错误提示标题
  static XHttp setErrorTitle(String msg) {
    errorShowTitle = msg;
    return _instance;
  }

  // /// 设置当前的请求数据格式
  // static XHttp setContentType(String contentType) {
  //   dio.options.contentType = contentType;
  //   return _instance;
  // }

  // /// 设置当前的请求数据格式
  // static XHttp setContentTypeMultipartForm() {
  //   dio.options.contentType = "multipart/form-data";
  //   return _instance;
  // }

  // /// 设置当前的请求返回数据格式
  // static XHttp setDataType(ResponseType dataType) {
  //   dio.options.responseType = dataType;
  //   return _instance;
  // }

  // /// 设置当前的请求返回数据格式
  // static XHttp setDataTypeJson() {
  //   dio.options.responseType = ResponseType.json;
  //   return _instance;
  // }

  // ----- [cookie/charset/accept/encoder/decoder] 这些都可以通过设置 headers 实现 -----
}

/// ====================================================== 以下内容为工具方法 ======================================================

/// 解析数据
String parseData(data) {
  String responseStr = "";
  if (data is Map) {
    responseStr += data.mapToStructureString();
  } else if (data is FormData) {
    final formDataMap = Map()
      ..addEntries(data.fields)
      ..addEntries(data.files);
    responseStr += formDataMap.mapToStructureString();
  } else if (data is List) {
    responseStr += data.listToStructureString();
  } else {
    responseStr += data.toString();
  }
  return responseStr;
}

/// 分段 log，可以写到 log 中。
void logWrapped(String text) {
  final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
  pattern.allMatches(text).forEach((match) => print(match.group(0)));
}

/// Map 拓展，Map 转结构化字符串输出。
extension Map2StringEx on Map {
  String mapToStructureString({int indentation = 0, String space = "  "}) {
    if (this == null || this.isEmpty) {
      return "$this";
    }
    String result = "";
    String indentationContent = space * indentation;
    result += "{";
    this.forEach((key, value) {
      if (value is Map) {
        result += "\n$indentationContent" + "\"$key\": ${value.mapToStructureString(indentation: indentation + 1)},";
      } else if (value is List) {
        result += "\n$indentationContent" + "\"$key\": ${value.listToStructureString(indentation: indentation + 1)},";
      } else {
        result += "\n$indentationContent" + "\"$key\": ${value is String ? "\"$value\"," : "$value,"}";
      }
    });
    result = result.substring(0, result.length - 1); // 去掉最后一个逗号
    result += "\n$indentationContent}";
    return result;
  }
}

/// List 拓展，List 转结构化字符串输出。
extension List2StringEx on List {
  String listToStructureString({int indentation = 0, String space = "  "}) {
    if (this == null || this.isEmpty) {
      return "$this";
    }
    String result = "";
    String indentationContent = space * indentation;
    result += "[";
    for (var value in this) {
      if (value is Map) {
        result +=
            "\n$indentationContent" + space + "${value.mapToStructureString(indentation: indentation + 1)},"; // 加空格更好看
      } else if (value is List) {
        result += value.listToStructureString(indentation: indentation + 1);
      } else {
        result += "\n$indentationContent" + value is String ? "\"$value\"," : "$value,";
      }
    }
    result = result.substring(0, result.length - 1); // 去掉最后一个逗号
    result += "\n$indentationContent]";
    return result;
  }
}

/// 结果处理
class Result {
  var data;
  bool success;
  int code;
  String msg;
  var headers;
  Result(this.data, this.success, this.code, this.msg, {this.headers});
}

class Toast {
  Toast._() {
    // EasyLoading 已全局初始化构建
    // EasyLoading.instance.loadingStyle = EasyLoadingStyle.custom;
    // 此处可自定义风格
  }
  static final Toast _instance = Toast._();

  static const String SUCCESS = "SUCCESS";
  static const String ERROR = "ERROR";
  static const String WARNING = "WARNING";
  static const String INFO = "INFO";

  static loading(String msg) {
    EasyLoading.show(status: msg);
  }

  static progeress(double value, String msg) {
    EasyLoading.showProgress(value, status: msg);
  }

  static show(String msg, {String type}) {
    switch (type) {
      case Toast.SUCCESS:
        EasyLoading.showSuccess(msg);
        break;
      case Toast.ERROR:
        EasyLoading.showError(msg);
        break;
      case Toast.WARNING:
        EasyLoading.showInfo(msg);
        break;
      case Toast.INFO:
      default:
        EasyLoading.showToast(msg);
        break;
    }
  }

  static hide() {
    EasyLoading.dismiss();
  }
}

// /// 使用示例：若未设置多个 baseUrl，可省略 getInstance()，记得给 get、post 设置 static 关键字或者直接初始化多个 baseUrl 的实例。也可以参考 request 在 get、post 方法中设置 baseUrl。
//  XHttp.getInstance().post("/user/login", {
//     "username": username,
//     "password": password
//   }).then((res) {
//     // DO SOMETHING
//   }).catchError((err) {
//     // DO SOMETHING
//   });
