import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeopleWorks CheckList',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SafeArea(
        left: false,  // 좌측은 edge-to-edge 유지
        right: false, // 우측은 edge-to-edge 유지
        top: false,    // 상단 상태바 edge-to-edge 유지
        bottom: true, // 하단 네비게이션 바 영역 회피
        child: WebBrowserScreen(),
      ),
    );
  }
}

class WebBrowserScreen extends StatefulWidget {
  const WebBrowserScreen({super.key});

  @override
  State<WebBrowserScreen> createState() => _WebBrowserScreenState();
}

class _WebBrowserScreenState extends State<WebBrowserScreen> {
  late WebViewController webViewController;
  String currentUrl = '';
  String defaultUrl = 'http://10.10.10.100:9090/Home/Preshiftcheck_list'; // 🔧 여기에 기본 URL을 입력하세요
  bool isLoading = true;
  String webPageTitle = 'PeopleWorks CheckList';

  @override
  void initState() {
    super.initState();
    // 설정 로드 후 웹뷰 초기화 및 URL 로드
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSettings(); // 설정 먼저 로드
    _initializeWebView();   // 그 다음 웹뷰 초기화
    // currentUrl이 비어있지 않다면 해당 URL 로드
    if (currentUrl.isNotEmpty) {
      await _loadUrl(currentUrl);
    } else {
      // currentUrl이 비어있다면 defaultUrl 로드
      await _loadUrl(defaultUrl);
    }
  }

// 설정 로드
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      defaultUrl = prefs.getString('default_url') ?? 'http://10.10.10.100:9090/Home/Preshiftcheck_list';
      currentUrl = prefs.getString('last_url') ?? defaultUrl; // last_url이 없으면 defaultUrl 사용
    });
    print('🔧 설정 로드 완료: currentUrl = $currentUrl, defaultUrl = $defaultUrl');
  }

  // [브릿지 호출 메소드]
  Future<void> appToWebCall(WebViewController controller) async {
    //showAlertDialog(context, "appToWebCall");


    // [초기 변수 선언 및 데이터 삽입] : [map]
    var map = Map<String, dynamic>();

    map["name"] = "twok";
    map["age"] = 30;


    // [jsonEncode : JSON 인코딩 실시]
    var jsonString = jsonEncode(map);


    await controller.runJavaScript('window.onMessageReceive(${jsonString})');
  }

  // [팝업창 활성 메소드]
  Future<dynamic> showAlertDialog(BuildContext context, String message) {
    return showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("Alert"),
        content: Text(message),
        actions: [
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Confirm")),
        ],
      ),
    );
  }

  Future<bool?> showConfirmDialog(BuildContext context, String message) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm"),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

// 웹뷰 초기화
  // lib/main.dart의 _initializeWebView() 메서드 수정
  void _initializeWebView() {
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))

    // 🔧 User Agent 설정 (서버 호환성 향상)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; SM-T870) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Safari/537.36')

    // 🔧 추가 WebView 설정
      ..enableZoom(true)
// JavaScript 채널 추가
      ..addJavaScriptChannel(
        'TitleChannel',
        onMessageReceived: (JavaScriptMessage message) {
          setState(() {
            webPageTitle = message.message; // 웹페이지 제목 업데이트
          });
        },
      )
      ..addJavaScriptChannel('Alert', onMessageReceived: (JavaScriptMessage message){
        showAlertDialog(context, message.message);
      },)
      ..addJavaScriptChannel('Confirm', onMessageReceived: (JavaScriptMessage message) async {
        final result = await showConfirmDialog(context, message.message);
        // 결과를 웹으로 전달
        webViewController.runJavaScript('window._confirmResult = ${result ?? false};');
      },)
      ..setNavigationDelegate(
        NavigationDelegate(
          // 🔧 URL 필터링 강화
          onNavigationRequest: (NavigationRequest request) {
            print('🌐 네비게이션 요청: ${request.url}');

            // 허용된 도메인 체크
            final allowedDomains = [
              '10.10.10.100',
            ];

            final uri = Uri.parse(request.url);
            final isAllowed = allowedDomains.any((domain) =>
            uri.host.contains(domain) || uri.host == domain);

            if (!isAllowed) {
              print('⚠️ 차단된 도메인: ${uri.host}');
              // 차단하지 않고 허용하되 로그만 남김
            }

            return NavigationDecision.navigate;
          },

          onPageStarted: (String url) {
            print('📄 페이지 시작: $url');
            setState(() {
              isLoading = true;
              currentUrl = url;
            });

            // 즉시 헤더 숨기기 CSS 주입
            _injectHideHeaderCSS();
          },

          onPageFinished: (String url) {
            print('✅ 페이지 완료: $url');
            setState(() {
              isLoading = false;
              currentUrl = url;
            });
            _saveLastUrl(url);
            // 웹페이지 제목 추출 및 헤더 숨기기
            _extractPageTitle();

            try {
              var javascript = '''
              // alert 함수 재정의
              window.alert = function (e){
                var uagent = navigator.userAgent.toLowerCase();
                var android_agent = uagent.search("android");
                
                if (android_agent > -1) {
                  window.Alert.postMessage(String(e));
                }
                else {
                  window.webkit.messageHandlers.Alert.postMessage(String(e));
                }
              };
            
              // confirm 함수 재정의
              window.confirm = function (message) {
                return new Promise(function(resolve) {
                  var uagent = navigator.userAgent.toLowerCase();
                  var android_agent = uagent.search("android");
                  
                  // 결과를 받을 콜백 설정
                  window._confirmCallback = resolve;
                  
                  if (android_agent > -1) {
                    window.Confirm.postMessage(String(message));
                  } else {
                    window.webkit.messageHandlers.Confirm.postMessage(String(message));
                  }
                  
                  // 결과 대기를 위한 폴링
                  var checkResult = function() {
                    if (typeof window._confirmResult !== 'undefined') {
                      var result = window._confirmResult;
                      delete window._confirmResult;
                      resolve(result);
                    } else {
                      setTimeout(checkResult, 100);
                    }
                  };
                  checkResult();
                });
              };
              ''';

              webViewController.runJavaScript(javascript);
            } catch (_) {}
          },

          // 🔧 에러 처리 강화
          onWebResourceError: (WebResourceError error) {
            print('❌ 리소스 에러: ${error.description} (${error.url})');
            print('   에러 타입: ${error.errorType}');
            print('   에러 코드: ${error.errorCode}');

            setState(() {
              isLoading = false;
            });

            // 🔧 Connection refused 에러만 팝업 표시하지 않음
            if (error.description.toLowerCase().contains('connection refused') ||
                error.description.toLowerCase().contains('err_connection_refused')) {
              print('🔇 Connection refused 에러 무시됨');
              return; // 팝업 표시하지 않음
            }

            // 다른 중요한 에러만 표시
            if (error.url?.contains(currentUrl) == true) {
              _showErrorDialog('페이지 로드 오류: ${error.description}');
            }
          },

          // 🔧 HTTP 인증 에러 처리
          onHttpAuthRequest: (HttpAuthRequest request) {
            print('🔐 HTTP 인증 요청: ${request.host}');
            // 필요시 인증 정보 제공
          },
        ),
      );

    print('🔩 웹뷰 초기화 완료 (강화된 설정)');
  }
// 웹에서 받은 JSON 데이터 처리
  void _handleWebData(Map<String, dynamic> jsonData) {
    print('🌐 웹에서 JSON 데이터 수신: $jsonData');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('웹에서 데이터 수신'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('받은 데이터:'),
            const SizedBox(height: 8),
            SelectableText(
              jsonEncode(jsonData),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            const Text('어떤 작업을 수행하시겠습니까?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _sendWebDataToAPI(jsonData);
            },
            child: const Text('API로 전송'),
          ),
        ],
      ),
    );
  }

// 웹 데이터를 API로 전송
  Future<void> _sendWebDataToAPI(Map<String, dynamic> jsonData) async {
    const String apiUrl = 'http://10.10.10.100:9090/LSEVP/Post/QR';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(jsonData), // 받은 JSON을 그대로 전송
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('웹 데이터가 API로 전송되었습니다: ${jsonEncode(jsonData)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception('API 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('API 전송 실패: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 마지막 접속 URL 저장
  Future<void> _saveLastUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_url', url);
  }

  // 기본 URL 저장
  Future<void> _saveDefaultUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_url', url);
    setState(() {
      defaultUrl = url;
    });
  }

  // URL 로드
  Future<void> _loadUrl(String url) async {
    print('🌐 URL 로드 요청: $url');

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
      print('🔗 프로토콜 추가: $url');
    }

    try {
      print('📞 웹뷰 로드 시도...');
      await webViewController.loadRequest(Uri.parse(url));
      print('✅ 웹뷰 로드 성공');
    } catch (e) {
      print('❌ URL 로드 오류: $e');
      // 웹뷰가 아직 준비되지 않았을 수 있으므로 잠시 후 재시도
      print('⏱️ 100ms 대기 후 재시도...');
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        print('🔄 재시도 중...');
        await webViewController.loadRequest(Uri.parse(url));
        print('✅ 재시도 성공');
      } catch (e2) {
        print('❌ URL 로드 재시도 오류: $e2');
        _showErrorDialog('페이지 로드에 실패했습니다: $url');
      }
    }
  }

  // QR 스캔 화면으로 이동
  void _openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerScreen(
          onQRScanned: (qrData) {
            _handleQRData(qrData);
          },
        ),
      ),
    );
  }

// _handleQRData 메서드 수정
  void _handleQRData(String qrData) {
    print('🎯 QR 데이터 처리 시작: $qrData');

    // 알림창 없이 바로 페이지 이동
    _sendToSpecificPage(qrData);
    // QR 스캔 화면이 완전히 닫힌 후 다이얼로그 표시
    // Future.delayed(const Duration(milliseconds: 100), () {
    //   if (mounted) {
    //     _showQRDataDialog(qrData);
    //   }
    // });
  }

  // _showQRDataDialog 메서드 수정
  void _showQRDataDialog(String qrData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('QR 스캔 완료'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('스캔된 데이터:'),
            const SizedBox(height: 8),
            SelectableText(
              qrData,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            const Text('어떤 작업을 수행하시겠습니까?'),
          ],
        ),
        actions: [
           ElevatedButton(
             onPressed: () {
               Navigator.of(context).pop();
               _sendToSpecificPage(qrData);
             },
             child: const Text('특정 페이지로 이동'),
           ),
        ],
        // actions: [

          // TextButton(
          //   onPressed: () => Navigator.of(context).pop(),
          //   child: const Text('취소'),
          // ),
          // ElevatedButton(
          //   onPressed: () {
          //     Navigator.of(context).pop();
          //     _sendToSpecificPage(qrData);
          //   },
          //   child: const Text('특정 페이지로 이동'),
          // ),
          // ElevatedButton(
          //   onPressed: () {
          //     Navigator.of(context).pop();
          //     _sendToAPI(qrData);
          //   },
          //   child: const Text('API로 전송'),
          // ),
        // ],
      ),
    );
  }


  // 특정 페이지로 이동하면서 QR 데이터 전송
  void _sendToSpecificPage(String qrData) {
    // 특정 URL 설정 (여기서 수정하세요)
    const String targetUrl = 'http://10.10.10.100:9090/Home/Preshiftcheck_Create';

    // URL 파라미터로 데이터 전달
    final String urlWithParams = '$targetUrl?CheckType=${'DAILY'}&Date=${DateTime.now()}&Process=${'SMD'}&Line=${'SMTALine'}';

    _loadUrl(urlWithParams);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Move by QR Data'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // API로 QR 데이터 전송 (현재 페이지는 그대로)
  Future<void> _sendToAPI(String qrData) async {
    // 특정 API URL 설정 (여기서 수정하세요)
    const String apiUrl = 'http://10.10.10.100:9090/LSEVP/Post/QR';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'QRcode': qrData
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR 데이터가 API로 전송되었습니다: $qrData'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception('API 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('API 전송 실패: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 설정 다이얼로그 표시
  void _showSettingsDialog() {
    final TextEditingController defaultUrlController =
    TextEditingController(text: defaultUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: defaultUrlController,
              decoration: const InputDecoration(
                labelText: '기본 URL',
                hintText: 'https://example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _saveDefaultUrl(defaultUrlController.text);
              Navigator.of(context).pop();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  // 에러 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
  // JavaScript 실행 메서드 추가
  Future<void> _injectTitleExtractionScript() async {
    const String script = '''
      (function() {
        // 헤더의 제목 추출
        const header = document.querySelector('header h1 a, header h1');
        let title = 'PeopleWorks CheckList'; // 기본값
        
      if (header) {
        title = header.textContent || header.innerText || title;
        
        const headerElement = document.querySelector('header');
        if (headerElement) {
          headerElement.style.display = 'none';
          
          // 컨테이너의 상단 여백도 조정
          const container = document.querySelector('.container');
          if (container) {
            container.style.paddingTop = '0';
            container.style.marginTop = '0';
          }
        }
      }
        
        // Flutter로 제목 전달
        if (window.TitleChannel) {
          TitleChannel.postMessage(title);
        }
      })();
    ''';

    try {
      await webViewController.runJavaScript(script);
    } catch (e) {
      print('JavaScript 실행 오류: $e');
    }
  }
// 헤더 숨기기 CSS (onPageStarted에서 실행)
  Future<void> _injectHideHeaderCSS() async {
    const String cssScript = '''
    (function() {
      const style = document.createElement('style');
      style.textContent = `
        header { 
          display: none !important; 
          visibility: hidden !important;
        }
        .container {
          padding-top: 0 !important;
          margin-top: 0 !important;
        }
      `;
      document.head.appendChild(style);
    })();
  ''';

    try {
      await webViewController.runJavaScript(cssScript);
    } catch (e) {
      print('CSS 주입 오류: $e');
    }
  }
// 제목 추출만 (onPageFinished에서 실행)
  Future<void> _extractPageTitle() async {
    const String titleScript = '''
    (function() {
      const header = document.querySelector('header h1 a, header h1');
      let title = 'PeopleWorks CheckList';
      
      if (header) {
        title = header.textContent || header.innerText || title;
      }
      
      if (window.TitleChannel) {
        TitleChannel.postMessage(title);
      }
    })();
  ''';

    try {
      await webViewController.runJavaScript(titleScript);
    } catch (e) {
      print('제목 추출 오류: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        // 왼쪽에 기존 타이틀 배치
        leading: InkWell(
          onTap: () async{
            await _loadUrl(defaultUrl);
            print('🔍 Url: $defaultUrl');
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start, // Row 내부 요소들을 시작점에 정렬
              children: <Widget>[
                // 로고 이미지
                Image.asset(
                  'assets/MainLogo_Remove.png', // pubspec.yaml에 등록된 로고 이미지 경로
                  width: 160, // 로고 이미지의 너비 (조절 가능)
                  height: 44, // 로고 이미지의 높이 (조절 가능)
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 4), // 로고와 텍스트 사이의 간격
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 9.0),
                    child: Text(
                      'CheckList',
                      style: TextStyle(
                        fontSize: 24, // 텍스트 크기는 공간에 맞게 조절될 수 있음
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255,201,30,36), // AppBar의 foregroundColor가 적용되지만 명시적으로 지정 가능
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        leadingWidth: 300, // leading 영역 너비 조정
        // 중앙에 웹페이지 제목 배치
        title: Text(
          webPageTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQRScanner,
            tooltip: 'QR 스캔',
          ),
          // IconButton(
          //   icon: const Icon(Icons.home),
          //   onPressed: () async => await _loadUrl(defaultUrl),
          //   tooltip: '홈으로',
          // ),
          // IconButton(
          //   icon: const Icon(Icons.refresh),
          //   onPressed: () => webViewController.reload(),
          //   tooltip: '새로고침',
          // ),
          // PopupMenuButton<String>(
          //   onSelected: (value) {
          //     switch (value) {
          //       case 'settings':
          //         _showSettingsDialog();
          //         break;
          //       case 'back':
          //         webViewController.goBack();
          //         break;
          //       case 'forward':
          //         webViewController.goForward();
          //         break;
          //     }
          //   },
          //   itemBuilder: (context) => [
          //     const PopupMenuItem(
          //       value: 'back',
          //       child: Text('뒤로'),
          //     ),
          //     const PopupMenuItem(
          //       value: 'forward',
          //       child: Text('앞으로'),
          //     ),
          //     const PopupMenuItem(
          //       value: 'settings',
          //       child: Text('설정'),
          //     ),
          //   ],
          // ),
        ],
      ),
      body: Column(
        children: [
          // 로딩 인디케이터
          if (isLoading)
            const LinearProgressIndicator(),
          // 웹뷰
          Expanded(
            child: WebViewWidget(
              controller: webViewController,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// QR 스캐너 화면
class QRScannerScreen extends StatefulWidget {
  final Function(String) onQRScanned;

  const QRScannerScreen({
    super.key,
    required this.onQRScanned,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool isScanning = true;
  String? scannedData;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

// _onDetect 메서드 수정 (QRScannerScreen 내부)
  void _onDetect(BarcodeCapture capture) {
    if (!isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        print('🔍 QR 코드 스캔됨: $code');

        setState(() {
          isScanning = false;
          scannedData = code;
        });

        // 카메라 정지
        cameraController.stop();

        // 즉시 스캔 화면 닫기
        Navigator.of(context).pop();

        // 스캔된 데이터를 부모 화면으로 전달
        widget.onQRScanned(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scan'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
            tooltip: 'Flash',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => cameraController.switchCamera(),
            tooltip: 'Change Camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 카메라 화면
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),

          // // 스캔 완료 표시
          // if (scannedData != null)
          //   Container(
          //     width: double.infinity,
          //     height: double.infinity,
          //     color: Colors.black.withOpacity(0.7),
          //     child: Center(
          //       child: Container(
          //         padding: const EdgeInsets.all(20),
          //         margin: const EdgeInsets.all(20),
          //         decoration: BoxDecoration(
          //           color: Colors.white,
          //           borderRadius: BorderRadius.circular(10),
          //         ),
          //         child: Column(
          //           mainAxisSize: MainAxisSize.min,
          //           children: [
          //             const Icon(
          //               Icons.check_circle,
          //               color: Colors.green,
          //               size: 60,
          //             ),
          //             const SizedBox(height: 16),
          //             const Text(
          //               'QR 코드 스캔 완료!',
          //               style: TextStyle(
          //                 fontSize: 18,
          //                 fontWeight: FontWeight.bold,
          //               ),
          //             ),
          //             const SizedBox(height: 8),
          //             Text(
          //               scannedData!,
          //               style: const TextStyle(
          //                 fontSize: 14,
          //                 color: Colors.grey,
          //               ),
          //               textAlign: TextAlign.center,
          //             ),
          //           ],
          //         ),
          //       ),
          //     ),
          //   ),

          // 스캔 가이드 오버레이 (스캔 중일 때만 표시)
          if (isScanning)
            Container(
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  // 스캔 영역 (투명한 사각형)
                  Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // 안내 텍스트
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Please align the QR code within the square.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Scan Status: ${isScanning ? "Scanning..." : "Completed"}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}