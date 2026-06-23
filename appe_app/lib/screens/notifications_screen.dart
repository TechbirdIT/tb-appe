import 'package:flutter/material.dart';

import '../services/api.dart';
import 'login_screen.dart';
import 'notification_detail_screen.dart';

/// Notifications — Unread / Read / All tabs, backed by `frappe.client.get_list`
/// over `Notification Log`.
///
/// Unlike the original app (which dumps the raw Frappe `AuthenticationError`
/// traceback when its token is stale), this screen catches auth failures and
/// shows a clean "session expired → sign in" recovery, and any other failure as
/// a short message with Retry.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Unread'),
              Tab(text: 'Read'),
              Tab(text: 'All'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _NotificationList(read: 0),
            _NotificationList(read: 1),
            _NotificationList(read: -1),
          ],
        ),
      ),
    );
  }
}

class _NotificationList extends StatefulWidget {
  const _NotificationList({required this.read});
  final int read; // -1 all, 0 unread, 1 read

  @override
  State<_NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<_NotificationList>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  bool _authExpired = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _authExpired = false;
    });
    try {
      final api = await AppeApi.create();
      final data = await api.notifications(read: widget.read);
      setState(() {
        _items =
            data.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } on AuthException catch (e) {
      setState(() {
        _authExpired = true;
        _error = e.message;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  void _toLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorState();
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 160),
          Center(child: Text('No notifications.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (_, i) => _tile(_items[i]),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _authExpired ? Icons.lock_outline : Icons.error_outline,
              size: 56,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _authExpired ? 'Session expired' : 'Something went wrong',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _authExpired
                ? FilledButton.icon(
                    onPressed: _toLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in again'),
                  )
                : OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final unread = (n['read'] ?? 0) == 0;
    final subject = _stripHtml((n['subject'] ?? '').toString());
    final body = _stripHtml((n['email_content'] ?? '').toString());
    return ListTile(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => NotificationDetailScreen(notification: n)),
        );
        if (mounted) _load(); // refresh read/unread state on return
      },
      leading: CircleAvatar(
        backgroundColor:
            unread ? const Color(0xFF1B2440) : const Color(0xFFE3E5EA),
        child: Icon(Icons.notifications,
            color: unread ? Colors.white : Colors.black45, size: 20),
      ),
      title: Text(subject.isEmpty ? '(no subject)' : subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
      subtitle: body.isEmpty
          ? null
          : Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(_shortDate((n['creation'] ?? '').toString()),
          style: const TextStyle(fontSize: 11, color: Colors.black45)),
    );
  }

  String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}';
  }
}
