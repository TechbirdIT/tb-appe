import 'package:flutter/material.dart';

import '../services/api.dart';

/// Posts feed — backed by `appe.appe_api.get_appe_posts`.
/// Each post carries `{title, content, owner, creation, images[]}`.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await AppeApi.create();
      final res = await api.appePosts(start: 0, pageLength: 20);
      final data = (res is Map ? res['data'] : res) as List? ?? const [];
      setState(() {
        _posts
          ..clear()
          ..addAll(data.cast<Map>().map((m) => m.cast<String, dynamic>()));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load posts:\n$_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No posts yet.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _posts.length,
                          itemBuilder: (_, i) => _postCard(_posts[i]),
                        ),
                ),
    );
  }

  Widget _postCard(Map<String, dynamic> p) {
    final images = (p['images'] as List?)?.cast<String>() ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text((p['title'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text((p['owner'] ?? '').toString()),
          ),
          if ((p['content'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text((p['content'] ?? '').toString()),
            ),
          if (images.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                images.first,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
