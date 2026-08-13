import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import 'models/delivery_note.dart';
import 'delivery_note_repository.dart';
import 'delivery_note_item_repository.dart';

class DnListNotifier extends StateNotifier<List<DeliveryNote>> {
  final DeliveryNoteRepository _repo;
  DnListNotifier(this._repo) : super(const []);

  Future<void> load() async {
    state = await _repo.loadAll();
  }

  Future<List<DeliveryNote>> loadByPoId(String poId) async {
    return await _repo.loadByPoId(poId);
  }
}

final dnRepositoryProvider = Provider<DeliveryNoteRepository>((ref) {
  return DeliveryNoteRepository(ref.read(sheetsServiceProvider));
});

final dnItemRepositoryProvider = Provider<DeliveryNoteItemRepository>((ref) {
  return DeliveryNoteItemRepository(ref.read(sheetsServiceProvider));
});

final dnListProvider =
    StateNotifierProvider<DnListNotifier, List<DeliveryNote>>((ref) {
  return DnListNotifier(ref.read(dnRepositoryProvider));
});
