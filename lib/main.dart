// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:xhttp_demo/utils/xhttp.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        builder: EasyLoading.init(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('XHttp Demo'),
          ),
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                _createButton(
                    text: 'GET 请求',
                    onPressed: () {
                      XHttp.getInstance().get('/api/get', {'id': 1}).then((data) {
                        // DO SOMETHING
                      }).catchError((e) {
                        // DO SOMETHING
                      });
                      XHttp.request('/api/get', baseUrl: 'http://yyy.com', msg: 'hello world').then((data) {
                        // DO SOMETHING
                      }).catchError((e) {
                        // DO SOMETHING
                      });
                    }),
                _createButton(
                    text: 'POST 请求',
                    onPressed: () {
                      XHttp.getInstance().post('/api/login', {'username': 'xxx', 'password': '123456'}).then((data) {
                        // DO SOMETHING
                      }).catchError((e) {
                        // DO SOMETHING
                      });
                      XHttp.request(
                        '/api/login',
                        method: XHttp.POST,
                        data: {'username': 'xxx', 'password': '123456'},
                      ).then((data) {
                        // DO SOMETHING
                      }).catchError((e) {
                        // DO SOMETHING
                      });
                    }),
                _createButton(
                    text: '更换 baseUrl',
                    onPressed: () {
                      XHttp.getInstance(baseUrl: 'http://xxxxx.com').get('/api/get', {'id': 1}).then((data) {
                        // DO SOMETHING
                      }).catchError((e) {
                        // DO SOMETHING
                      });
                    }),
                _createButton(
                    text: '自定义请求等待 msg',
                    onPressed: () {
                      XHttp.getInstance(msg: '正在获取数据...').get('/api/get', {'id': 1});
                    }),
                _createButton(
                    text: '取消请求',
                    onPressed: () {
                      XHttp.cancelRequest();
                      // XHttp.cancelWhiteListRequest();
                    }),
                _createHorizontalLine(),
                _createButton(
                    text: '不使用默认结果 msg',
                    onPressed: () {
                      XHttp.getInstance()
                          .get('/api/get', {'id': 1}, {'successMsg': '获取成功', 'errorMsg': '获取失败'})
                          .then((data) => {
                                // DO SOMETHING
                              })
                          .catchError((e) {
                            // DO SOMETHING
                          });
                    }),
                _createButton(
                    text: '自定义结果处理',
                    onPressed: () {
                      XHttp.getInstance()
                          .get('/api/get', {'id': 1}, {'type': XHttp.DIALOG_TYPE_OTHERS})
                          .then((data) => {
                                // DO SOMETHING
                              })
                          .catchError((e) {
                            // DO SOMETHING
                          });
                      ;
                    }),
                _createButton(
                    text: '传入结果 Function 处理且设置不能取消白名单',
                    onPressed: () {
                      XHttp.getInstance().get(
                        '/api/get',
                        {'id': 1},
                        {
                          'type': XHttp.DIALOG_TYPE_CUSTOM,
                          'onSuccess': (data) {
                            // DO SOMETHING
                          },
                          'onError': (e) {
                            // DO SOMETHING
                          }
                        },
                        true,
                      );
                    }),
              ],
            ),
          ),
        ));
  }
}

Widget _createButton({String text, Function onPressed}) {
  return Container(padding: EdgeInsets.all(10), child: ElevatedButton(child: Text(text), onPressed: onPressed));
}

Widget _createHorizontalLine() {
  return SizedBox(
    width: double.infinity,
    height: 1,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.deepPurpleAccent),
    ),
  );
}
