class Chat {
  final String id;
  final String name;
  final bool isGroup;

  Chat({required this.id, required this.name, this.isGroup = false});

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'],
        name: json['name'] ?? '',
        isGroup: json['is_group'] ?? false,
      );
}
