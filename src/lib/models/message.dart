class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'],
        chatId: json['chat_id'],
        senderId: json['sender_id'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']),
      );
}
