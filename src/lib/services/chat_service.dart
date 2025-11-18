import 'package:flutter/foundation.dart';
import '../models/message.dart';
import 'supabase_service.dart';

class ChatService {
  final _client = SupabaseService.client;

  Stream<List<Message>> getMessages(String chatId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', chatId)
        .order('created_at')
        .map((data) => data.map<Message>((m) => Message.fromJson(m)).toList());
  }

  Future<void> sendMessage(
    String conversationId,
    String senderId,
    String content,
  ) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content_text': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateMessage({
    required String messageId,
    required String newText,
  }) async {
    await _client
        .from('messages')
        .update({
          'content_text': newText,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', messageId);
  }

  Future<void> deleteMessage({required String messageId}) async {
    await _client.from('messages').delete().eq('id', messageId);
  }

  Future<void> addReaction({
    required String messageId,
    required String userId,
    required String reaction,
  }) async {
    await _client.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': userId,
      'reaction': reaction,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeReaction({
    required String messageId,
    required String userId,
  }) async {
    await _client.from('message_reactions').delete().match({
      'message_id': messageId,
      'user_id': userId,
    });
  }

  Future<Map<String, int>> getReactionsAggregated(String messageId) async {
    final res = await _client
        .from('message_reactions')
        .select('reaction')
        .eq('message_id', messageId);

    final Map<String, int> out = {};
    try {
      for (final row in res) {
        final r = (row['reaction'] ?? '').toString();
        if (r.isEmpty) continue;
        out[r] = (out[r] ?? 0) + 1;
      }
    } catch (_) {}
    return out;
  }

  Stream<List<Map<String, dynamic>>> streamReactions(String messageId) {
    return _client
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('message_id', messageId)
        .order('created_at')
        .map((data) => List<Map<String, dynamic>>.from(data as List));
  }

  Future<String> uploadAttachment(Uint8List bytes, String filename) async {
    const maxBytes = 20 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw Exception('Arquivo maior que 20MB.');
    }

    final bucket = 'attachments';
    final key = 'uploads/${DateTime.now().millisecondsSinceEpoch}_$filename';

    try {
      final storage = _client.storage.from(bucket);
      try {
        await storage.uploadBinary(key, bytes);
      } catch (e) {
        debugPrint('uploadBinary failed: $e');
        rethrow;
      }

      final public = _client.storage.from(bucket).getPublicUrl(key);
      final url = public.toString();
      return url;
    } catch (e) {
      debugPrint('uploadAttachment error: $e');
      final emsg = e.toString();
      if (emsg.contains('Bucket not found') ||
          emsg.toLowerCase().contains('bucket not found') ||
          (emsg.contains('404') && emsg.toLowerCase().contains('bucket'))) {
        throw Exception(
          'Bucket "attachments" não encontrado no Supabase Storage. Verifique se o bucket existe e as permissões.',
        );
      }
      rethrow;
    }
  }
}
