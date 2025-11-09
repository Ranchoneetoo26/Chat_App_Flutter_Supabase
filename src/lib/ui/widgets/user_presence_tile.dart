import 'package:flutter/material.dart';

class UserPresenceTile extends StatelessWidget {
  final String displayName;
  final bool isOnline;
  final VoidCallback? onTap;

  const UserPresenceTile({
    super.key,
    required this.displayName,
    required this.isOnline,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? Colors.green : Colors.grey,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(displayName),
      subtitle: Text(isOnline ? "Online agora" : "Offline"),
    );
  }
}
