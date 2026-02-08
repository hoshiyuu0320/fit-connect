// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$messageRepositoryHash() => r'983823314282193fabadb5261bdd8e35a7ff7255';

/// MessageRepositoryのProvider
///
/// Copied from [messageRepository].
@ProviderFor(messageRepository)
final messageRepositoryProvider =
    AutoDisposeProvider<MessageRepository>.internal(
  messageRepository,
  name: r'messageRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$messageRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MessageRepositoryRef = AutoDisposeProviderRef<MessageRepository>;
String _$messagesStreamHash() => r'3ba88b0db331e3047dadd319ccc9ea5cab8d2d59';

/// メッセージリストを取得するProvider（リアルタイム）
///
/// Copied from [messagesStream].
@ProviderFor(messagesStream)
final messagesStreamProvider =
    AutoDisposeStreamProvider<List<Message>>.internal(
  messagesStream,
  name: r'messagesStreamProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$messagesStreamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MessagesStreamRef = AutoDisposeStreamProviderRef<List<Message>>;
String _$unreadMessageCountHash() =>
    r'c98a07f1698d9ce70f898226c8c0bfec65d609b4';

/// 未読メッセージ数を取得するProvider
/// messagesStreamProviderを監視し、メッセージ変更時に自動再取得
///
/// Copied from [unreadMessageCount].
@ProviderFor(unreadMessageCount)
final unreadMessageCountProvider = AutoDisposeFutureProvider<int>.internal(
  unreadMessageCount,
  name: r'unreadMessageCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$unreadMessageCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UnreadMessageCountRef = AutoDisposeFutureProviderRef<int>;
String _$messageByIdHash() => r'b38c51b35374ebf1eefe93594902d9f63ba35193';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// 特定のメッセージをIDで取得するProvider
///
/// Copied from [messageById].
@ProviderFor(messageById)
const messageByIdProvider = MessageByIdFamily();

/// 特定のメッセージをIDで取得するProvider
///
/// Copied from [messageById].
class MessageByIdFamily extends Family<AsyncValue<Message?>> {
  /// 特定のメッセージをIDで取得するProvider
  ///
  /// Copied from [messageById].
  const MessageByIdFamily();

  /// 特定のメッセージをIDで取得するProvider
  ///
  /// Copied from [messageById].
  MessageByIdProvider call(
    String messageId,
  ) {
    return MessageByIdProvider(
      messageId,
    );
  }

  @override
  MessageByIdProvider getProviderOverride(
    covariant MessageByIdProvider provider,
  ) {
    return call(
      provider.messageId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'messageByIdProvider';
}

/// 特定のメッセージをIDで取得するProvider
///
/// Copied from [messageById].
class MessageByIdProvider extends AutoDisposeFutureProvider<Message?> {
  /// 特定のメッセージをIDで取得するProvider
  ///
  /// Copied from [messageById].
  MessageByIdProvider(
    String messageId,
  ) : this._internal(
          (ref) => messageById(
            ref as MessageByIdRef,
            messageId,
          ),
          from: messageByIdProvider,
          name: r'messageByIdProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$messageByIdHash,
          dependencies: MessageByIdFamily._dependencies,
          allTransitiveDependencies:
              MessageByIdFamily._allTransitiveDependencies,
          messageId: messageId,
        );

  MessageByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.messageId,
  }) : super.internal();

  final String messageId;

  @override
  Override overrideWith(
    FutureOr<Message?> Function(MessageByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: MessageByIdProvider._internal(
        (ref) => create(ref as MessageByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        messageId: messageId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Message?> createElement() {
    return _MessageByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MessageByIdProvider && other.messageId == messageId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, messageId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin MessageByIdRef on AutoDisposeFutureProviderRef<Message?> {
  /// The parameter `messageId` of this provider.
  String get messageId;
}

class _MessageByIdProviderElement
    extends AutoDisposeFutureProviderElement<Message?> with MessageByIdRef {
  _MessageByIdProviderElement(super.provider);

  @override
  String get messageId => (origin as MessageByIdProvider).messageId;
}

String _$messagesNotifierHash() => r'2084ebbc3a7c5ccc2ed5134d7ec0d1bf17477779';

/// メッセージ送受信を管理するProvider
///
/// Copied from [MessagesNotifier].
@ProviderFor(MessagesNotifier)
final messagesNotifierProvider =
    AutoDisposeAsyncNotifierProvider<MessagesNotifier, List<Message>>.internal(
  MessagesNotifier.new,
  name: r'messagesNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$messagesNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$MessagesNotifier = AutoDisposeAsyncNotifier<List<Message>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
