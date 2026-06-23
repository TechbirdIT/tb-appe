import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/api.dart';
import 'webview_home.dart';

/// Full view of a single Notification Log entry. Renders the HTML body, marks
/// the notification read on open, and (if it references a document) offers to
/// open that document in the ERP WebView.
class NotificationDetailScreen extends StatefulWidget {
  const NotificationDetailScreen({super.key, required this.notification});

  final Map<String, dynamic> notification;

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  String _site = '';

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  Future<void> _markRead() async {
    try {
      final api = await AppeApi.create();
      _site = api.site;
      final name = (widget.notification['name'] ?? '').toString();
      if (name.isNotEmpty && (widget.notification['read'] ?? 0) == 0) {
        await api.markNotificationRead(name);
      }
    } catch (_) {
      // Non-fatal — viewing still works even if marking read fails.
    }
  }

  String get _subject {
    final s = (widget.notification['subject'] ?? '').toString();
    return s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _docUrl() {
    final dt = (widget.notification['document_type'] ?? '').toString();
    final dn = (widget.notification['document_name'] ?? '').toString();
    if (dt.isEmpty || dn.isEmpty || _site.isEmpty) return null;
    final slug = dt.toLowerCase().replaceAll(' ', '-');
    return '$_site/app/$slug/${Uri.encodeComponent(dn)}';
  }

  @override
  Widget build(BuildContext context) {
    final html = (widget.notification['email_content'] ?? '').toString();
    final docUrl = _docUrl();
    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_subject.isEmpty ? '(no subject)' : _subject,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text((widget.notification['creation'] ?? '').toString(),
                    style: const TextStyle(
                        color: Colors.black45, fontSize: 12)),
                const Divider(height: 24),
                if (html.trim().isEmpty)
                  const Text('No additional details.')
                else
                  // Render the HTML body in a lightweight inline WebView.
                  SizedBox(
                    height: 360,
                    child: InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data:
                            '<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font-family:sans-serif;font-size:15px;color:#222;padding:4px;margin:0}</style></head><body>$html</body></html>',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (docUrl != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => WebViewHome(siteUrl: docUrl)),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                        'Open ${widget.notification['document_type']}'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
