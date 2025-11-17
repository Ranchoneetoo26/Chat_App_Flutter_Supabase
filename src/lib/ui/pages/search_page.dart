import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _searchingUsers = true;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;
  static const int _maxResults = 50;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(v);
    });
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;

    // Tokenize and normalize input
    final tokens = query
        .toLowerCase()
        .split(RegExp(r"\s+"))
        .map((t) => t.trim())
        .where((t) => t.length >= 2)
        .toList();
    if (tokens.isEmpty) return;

    setState(() {
      _loading = true;
      _results = [];
    });

    try {
      if (_searchingUsers) {
        final Map<String, Map<String, dynamic>> byId = {};
        final Map<String, int> score = {};

        for (final token in tokens) {
          final pattern = '%$token%';
          final res = await Supabase.instance.client
              .from('profiles')
              .select('id, username, full_name')
              .ilike('username', pattern)
              .or('full_name.ilike.$pattern');

          final list = (res as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          for (final item in list) {
            final id = item['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            byId[id] = item;
            score[id] = (score[id] ?? 0) + 1;
          }
        }

        // Build sorted results by score (higher relevance first)
        final sorted = byId.keys.toList()
          ..sort((a, b) {
            final sa = score[a] ?? 0;
            final sb = score[b] ?? 0;
            if (sa != sb) return sb - sa;
            final na = (byId[a]?['full_name'] ?? byId[a]?['username'] ?? '')
                .toString();
            final nb = (byId[b]?['full_name'] ?? byId[b]?['username'] ?? '')
                .toString();
            return na.compareTo(nb);
          });

        final limited = sorted
            .take(_maxResults)
            .map((id) => byId[id]!)
            .toList();
        setState(() {
          _results = limited;
        });
      } else {
        final Map<String, Map<String, dynamic>> byId = {};
        final Map<String, int> score = {};

        for (final token in tokens) {
          final pattern = '%$token%';
          final res = await Supabase.instance.client
              .from('conversations')
              .select('id, name, is_public')
              .eq('is_public', true)
              .ilike('name', pattern);

          final list = (res as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          for (final item in list) {
            final id = item['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            byId[id] = item;
            score[id] = (score[id] ?? 0) + 1;
          }
        }

        final sorted = byId.keys.toList()
          ..sort((a, b) {
            final sa = score[a] ?? 0;
            final sb = score[b] ?? 0;
            if (sa != sb) return sb - sa;
            final na = (byId[a]?['name'] ?? '').toString();
            final nb = (byId[b]?['name'] ?? '').toString();
            return na.compareTo(nb);
          });

        final limited = sorted
            .take(_maxResults)
            .map((id) => byId[id]!)
            .toList();
        setState(() {
          _results = limited;
        });
      }
    } catch (e) {
      // ignore errors; UI shows empty
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Buscar...'),
                    onChanged: _onSearchChanged,
                    onSubmitted: _runSearch,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _runSearch(_controller.text),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ToggleButtons(
              isSelected: [_searchingUsers, !_searchingUsers],
              onPressed: (i) {
                setState(() {
                  _searchingUsers = i == 0;
                });
              },
              children: const [
                Padding(padding: EdgeInsets.all(8), child: Text('Usuários')),
                Padding(padding: EdgeInsets.all(8), child: Text('Grupos')),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final item = _results[i];
                  if (_searchingUsers) {
                    final name = (item['full_name'] ?? item['username'] ?? '')
                        .toString();
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(
                        name.isNotEmpty ? name : item['id'].toString(),
                      ),
                      subtitle: Text(item['username'] ?? ''),
                      onTap: () {
                        Navigator.pop(context, item);
                      },
                    );
                  } else {
                    return ListTile(
                      leading: const Icon(Icons.group),
                      title: Text(item['name'] ?? 'Grupo'),
                      subtitle: Text('Público'),
                      onTap: () {
                        Navigator.pop(context, item);
                      },
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
