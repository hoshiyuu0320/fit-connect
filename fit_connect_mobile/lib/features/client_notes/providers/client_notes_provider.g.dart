// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_notes_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$clientNoteRepositoryHash() =>
    r'45bdf68f8cc2639f6c22b35f1e7ad2c323a04133';

/// ClientNoteRepositoryのProvider
///
/// Copied from [clientNoteRepository].
@ProviderFor(clientNoteRepository)
final clientNoteRepositoryProvider =
    AutoDisposeProvider<ClientNoteRepository>.internal(
  clientNoteRepository,
  name: r'clientNoteRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$clientNoteRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ClientNoteRepositoryRef = AutoDisposeProviderRef<ClientNoteRepository>;
String _$sharedClientNotesHash() => r'8553f5baba9e1ea8885d9c7c543b5e0a72e9932f';

/// 共有済みカルテ一覧を取得するProvider
///
/// Copied from [sharedClientNotes].
@ProviderFor(sharedClientNotes)
final sharedClientNotesProvider =
    AutoDisposeFutureProvider<List<ClientNote>>.internal(
  sharedClientNotes,
  name: r'sharedClientNotesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sharedClientNotesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SharedClientNotesRef = AutoDisposeFutureProviderRef<List<ClientNote>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
