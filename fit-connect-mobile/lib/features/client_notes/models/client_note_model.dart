import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'client_note_model.g.dart';

/// ノートに紐づくセッションの抜粋（日時・種別）。
///
/// ClientNote の JSON `sessions` キー（`{session_date, session_type}`）の受け皿。
/// 顧客は sessions テーブルを直接読めない（memo を隠すため顧客用の SELECT
/// ポリシーを置いていない）ので、`sessions(...)` の embed ではなく、
/// ClientNoteRepository が必要な列だけを返す RPC get_my_sessions の結果から
/// 一覧・詳細の見出しに要る2列だけを差し込む。
///
/// 廃止した session_number（手入力の通し番号）の代わりに、この日時を
/// 「どのセッションのノートか」の主役として表示する。
@JsonSerializable()
class LinkedSession {
  /// セッション日時（timestamptz）。DateTimeConverterでローカル時刻に変換される
  @DateTimeConverter()
  @JsonKey(name: 'session_date')
  final DateTime sessionDate;

  /// セッション種別。CHECK制約なしのフリーテキスト（表示は sessionTypeLabel を通す）
  @JsonKey(name: 'session_type')
  final String? sessionType;

  const LinkedSession({
    required this.sessionDate,
    this.sessionType,
  });

  factory LinkedSession.fromJson(Map<String, dynamic> json) =>
      _$LinkedSessionFromJson(json);
  Map<String, dynamic> toJson() => _$LinkedSessionToJson(this);
}

@JsonSerializable()
class ClientNote {
  final String id;

  @JsonKey(name: 'client_id')
  final String clientId;

  @JsonKey(name: 'trainer_id')
  final String trainerId;

  final String title;
  final String content;

  @JsonKey(name: 'file_urls')
  final List<String> fileUrls;

  @JsonKey(name: 'is_shared')
  final bool isShared;

  @NullableDateTimeConverter()
  @JsonKey(name: 'shared_at')
  final DateTime? sharedAt;

  /// 紐づくセッション（sessions.id）。任意。
  /// 実データへの正式な参照はこちら（紐づけの有無の判定にも使える）。
  @JsonKey(name: 'session_id')
  final String? sessionId;

  /// 紐づくセッションの日時・種別（JSON `sessions` キーの受け皿）。
  ///
  /// ClientNoteRepository が get_my_sessions の結果を差し込んだ経路でだけ入る。
  /// sessionId があっても差し込まない経路（SessionRepository がセッション側に
  /// ノートをぶら下げる取得など）や、セッション情報の取得に失敗したときは
  /// null のままなので、表示側は sessionId ではなくこちらの有無で
  /// 「日時を出せるか」を判定すること
  @JsonKey(name: 'sessions')
  final LinkedSession? session;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const ClientNote({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.title,
    required this.content,
    this.fileUrls = const [],
    required this.isShared,
    this.sharedAt,
    this.sessionId,
    this.session,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientNote.fromJson(Map<String, dynamic> json) =>
      _$ClientNoteFromJson(json);
  Map<String, dynamic> toJson() => _$ClientNoteToJson(this);

  /// 紐づくセッションを差し込んだコピーを返す。
  ///
  /// セッション側にぶら下げて取ったノート（SessionRepository 経由）には `sessions` が
  /// 入らないため、親セッション側で自分の日時・種別を後から補うのに使う
  /// （SessionModel.sharedNotes 参照）。他のフィールドはそのまま
  ClientNote withSession(LinkedSession session) => ClientNote(
        id: id,
        clientId: clientId,
        trainerId: trainerId,
        title: title,
        content: content,
        fileUrls: fileUrls,
        isShared: isShared,
        sharedAt: sharedAt,
        sessionId: sessionId,
        session: session,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
