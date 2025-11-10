import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';
import 'supabase_service.dart';

class ChatService {
  final _client = SupabaseService.client;

  Stream<List<Message>> getMessages(String chatId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at')
        .map((data) => data.map(Message.fromJson).toList());
  }

  Future<void> sendMessage(String chatId, String senderId, String content) async {
    await _client.from('messages').insert({
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
