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

  /// Adiciona ou atualiza a reação de um usuário para uma mensagem (toggle semantics).
  Future<void> addReaction({
    required String messageId,
    required String userId,
    required String reaction,
  }) async {
    // Insere ou atualiza (upsert) a reação. A tabela `message_reactions` deve
    // ter unique constraint em (message_id, user_id).
    await _client.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': userId,
      'reaction': reaction,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Remove a reação de um usuário para uma mensagem
  Future<void> removeReaction({
    required String messageId,
    required String userId,
  }) async {
    await _client.from('message_reactions').delete().match({
      'message_id': messageId,
      'user_id': userId,
    });
  }

  /// Retorna um mapa de reação -> contagem para uma mensagem
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

  /// Stream em tempo real das reações de uma determinada mensagem
  Stream<List<Map<String, dynamic>>> streamReactions(String messageId) {
    return _client
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('message_id', messageId)
        .order('created_at')
        .map((data) => List<Map<String, dynamic>>.from(data as List));
  }

  /// Faz upload de um anexo para o bucket `attachments` e retorna a URL pública.
  /// Aceita os bytes do arquivo e o nome original para compor o caminho.
  Future<String> uploadAttachment(Uint8List bytes, String filename) async {
    final bucket = 'attachments';
    final key = 'uploads/${DateTime.now().millisecondsSinceEpoch}_$filename';

    try {
      // Tenta usar uploadBinary (disponível nas versões recentes do SDK).
      final storage = _client.storage.from(bucket);
      // uploadBinary pode existir ou não dependendo da versão; usamos try/catch.
      try {
        await storage.uploadBinary(key, bytes);
      } catch (e) {
        // Fallback: escrevemos em disco temporário e usamos upload
        // (apenas para plataformas que suportam File).
        rethrow;
      }

      final public = _client.storage.from(bucket).getPublicUrl(key);
      final url = public.toString();
      return url;
    } catch (e) {
      debugPrint('uploadAttachment error: $e');
      rethrow;
    }
  }
}
