import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Web Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const WebBrowserScreen(),
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
  String defaultUrl = 'http://61.250.235.29:9099/'; // 🔧 여기에 기본 URL을 입력하세요
  bool isLoading = true;

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
      defaultUrl = prefs.getString('default_url') ?? 'http://61.250.235.29:9099';
      currentUrl = prefs.getString('last_url') ?? defaultUrl; // last_url이 없으면 defaultUrl 사용
    });
    print('🔧 설정 로드 완료: currentUrl = $currentUrl, defaultUrl = $defaultUrl');
  }

// 웹뷰 초기화
  void _initializeWebView() {
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              currentUrl = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
              currentUrl = url;
            });
            _saveLastUrl(url);
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
            });
            _showErrorDialog('페이지 로드 오류: ${error.description}');
          },
        ),
      );
    print('🔩 웹뷰 초기화 완료');
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

    // QR 스캔 화면이 완전히 닫힌 후 다이얼로그 표시
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _showQRDataDialog(qrData);
      }
    });
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _sendToSpecificPage(qrData);
            },
            child: const Text('특정 페이지로 이동'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _sendToAPI(qrData);
            },
            child: const Text('API로 전송'),
          ),
        ],
      ),
    );
  }


  // 특정 페이지로 이동하면서 QR 데이터 전송
  void _sendToSpecificPage(String qrData) {
    // 특정 URL 설정 (여기서 수정하세요)
    const String targetUrl = 'https://your-qr-handler-page.com/receive';

    // URL 파라미터로 데이터 전달
    final String urlWithParams = '$targetUrl?qrData=${Uri.encodeComponent(qrData)}&timestamp=${DateTime.now().millisecondsSinceEpoch}';

    _loadUrl(urlWithParams);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('QR 데이터와 함께 특정 페이지로 이동합니다: $qrData'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // API로 QR 데이터 전송 (현재 페이지는 그대로)
  Future<void> _sendToAPI(String qrData) async {
    // 특정 API URL 설정 (여기서 수정하세요)
    const String apiUrl = 'http://61.250.235.29:9090/LSEVP/Post/QR';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Web Browser'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQRScanner,
            tooltip: 'QR 스캔',
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () async => await _loadUrl(defaultUrl),
            tooltip: '홈으로',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => webViewController.reload(),
            tooltip: '새로고침',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _showSettingsDialog();
                  break;
                case 'back':
                  webViewController.goBack();
                  break;
                case 'forward':
                  webViewController.goForward();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'back',
                child: Text('뒤로'),
              ),
              const PopupMenuItem(
                value: 'forward',
                child: Text('앞으로'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('설정'),
              ),
            ],
          ),
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
        title: const Text('QR 스캔'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
            tooltip: '플래시',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => cameraController.switchCamera(),
            tooltip: '카메라 전환',
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
                  // 반투명 배경
                  Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
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
                            'QR 코드를 사각형 안에 맞춰주세요',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '스캔 상태: ${isScanning ? "스캔 중..." : "완료"}',
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