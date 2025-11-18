import 'package:flutter/material.dart';

class MessageReactions extends StatefulWidget {
  final void Function(String reaction)? onReact;
  const MessageReactions({super.key, this.onReact});

  @override
  State<MessageReactions> createState() => _MessageReactionsState();
}

class _MessageReactionsState extends State<MessageReactions> {
  String? selectedReaction;
  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? Colors.grey[900] : Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: reactions.map((r) {
          final isSelected = r == selectedReaction;
          return GestureDetector(
            onTap: () {
              setState(() => selectedReaction = r);
              if (widget.onReact != null) widget.onReact!(r);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(r, style: const TextStyle(fontSize: 28)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
