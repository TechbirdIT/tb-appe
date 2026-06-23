import 'package:flutter/material.dart';

import '../services/api.dart';

/// "Appe Buddy" AI chat — backed by `appe.ai.api.*`.
///
/// Sends messages via `send_message` (which creates the conversation on first
/// send) and renders the `{role, content}` message list returned by
/// `get_conversation`.
class AiBuddyScreen extends StatefulWidget {
  const AiBuddyScreen({super.key});

  @override
  State<AiBuddyScreen> createState() => _AiBuddyScreenState();
}

class _AiBuddyScreenState extends State<AiBuddyScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AppeApi? _api;
  String? _conversation;
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    AppeApi.create().then((a) => _api = a);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _api == null) return;
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
      _input.clear();
    });
    _toBottom();
    try {
      await _api!.aiSendMessage(text, conversation: _conversation);
      // Reload the authoritative message list / conversation id.
      // send_message returns conversation info; refetch to render assistant turn.
      final convs = await _api!.aiListConversations();
      if (_conversation == null && convs.isNotEmpty) {
        _conversation = convs.first['name']?.toString();
      }
      if (_conversation != null) {
        final conv = await _api!.aiGetConversation(_conversation!);
        final msgs = (conv['messages'] as List?) ?? const [];
        setState(() {
          _messages
            ..clear()
            ..addAll(msgs.cast<Map>().map((m) => m.cast<String, dynamic>()));
        });
      }
    } on ApiException catch (e) {
      setState(() => _messages
          .add({'role': 'assistant', 'content': '⚠️ ${e.message}'}));
    } catch (e) {
      setState(() => _messages
          .add({'role': 'assistant', 'content': '⚠️ Could not reach Appe Buddy.'}));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage:
                  const AssetImage('assets/ai_images/appe_buddy.png'),
              onBackgroundImageError: (error, stack) {},
              child: const SizedBox.shrink(),
            ),
            const SizedBox(width: 10),
            const Text('Appe Buddy'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('Ask Appe Buddy anything about your ERP.'),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _bubble(_messages[i]),
                  ),
          ),
          if (_sending) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message Appe Buddy…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isUser = (m['role'] ?? '') == 'user';
    final content = (m['content'] ?? '').toString();
    if (content.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(content),
      ),
    );
  }
}
