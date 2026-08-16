import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import 'models/company_profile.dart';
import 'company_profile_repository.dart';

class SettingsState {
  final CompanyProfile? profile;
  final bool isLoading;

  const SettingsState(this.profile, this.isLoading);
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final CompanyProfileRepository _repo;

  SettingsNotifier(this._repo) : super(const SettingsState(null, false));

  Future<void> load() async {
    state = SettingsState(state.profile, true);
    try {
      final profile = await _repo.load();
      state = SettingsState(profile, false);
    } catch (_) {
      state = SettingsState(state.profile, false);
    }
  }

  Future<void> save(CompanyProfile profile) async {
    await _repo.save(profile);
    await load();
  }
}

final companyProfileRepositoryProvider =
    Provider<CompanyProfileRepository>((ref) {
  return CompanyProfileRepository(ref.watch(workbookStoreProvider));
});

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(companyProfileRepositoryProvider));
});
