import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Main shell: renders the connected Frappe / ERPNext site in a full-screen
/// in-app WebView, the way the original Appe app does.
class WebViewHome extends StatefulWidget {
  const WebViewHome({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<WebViewHome> createState() => _WebViewHomeState();
}

class _WebViewHomeState extends State<WebViewHome> {
  InAppWebViewController? _controller;
  double _progress = 0;

  Future<bool> _onBack() async {
    if (_controller != null && await _controller!.canGoBack()) {
      _controller!.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onBack();
        if (shouldPop && mounted) {
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_progress < 1.0)
                LinearProgressIndicator(value: _progress),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(widget.siteUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    useOnDownloadStart: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    geolocationEnabled: true,
                  ),
                  onWebViewCreated: (c) => _controller = c,
                  onProgressChanged: (_, p) =>
                      setState(() => _progress = p / 100),
                  onPermissionRequest: (_, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
