import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import 'models/delivery_note.dart';
import 'delivery_note_repository.dart';
import 'delivery_note_item_repository.dart';

class DnListNotifier extends StateNotifier<List<DeliveryNote>> {
  final DeliveryNoteRepository _repo;
  DnListNotifier(this._repo) : super(const []);

  Future<void> load() async {
    try {
      state = await _repo.loadAll();
    } catch (e) {
      // Keep the last good list rather than crashing the caller
      // (AGENTS.md §10).
      dev.log('[DeliveryNotes] load failed: $e');
    }
  }

  Future<List<DeliveryNote>> loadByPoId(String poId) =>
      _repo.loadByPoId(poId);
}

final dnRepositoryProvider = Provider<DeliveryNoteRepository>((ref) {
  return DeliveryNoteRepository(ref.watch(workbookStoreProvider));
});

final dnItemRepositoryProvider = Provider<DeliveryNoteItemRepository>((ref) {
  return DeliveryNoteItemRepository(ref.watch(workbookStoreProvider));
});

final dnListProvider =
    StateNotifierProvider<DnListNotifier, List<DeliveryNote>>((ref) {
  return DnListNotifier(ref.watch(dnRepositoryProvider));
});
