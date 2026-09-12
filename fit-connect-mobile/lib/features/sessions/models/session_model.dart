import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'session_model.g.dart';

/// セッション（トレーナーとの予約1件）のステータス。
/// DB側は sessions.status の CHECK 制約でこの4値に固定されている。
/// enum名とDB値は一致させているので、DB値が要るときは name をそのまま使う。
enum SessionStatus {
  scheduled,
  confirmed,
  completed,
  cancelled;

  /// 表示用の日本語ラベル
  String get labelJa => switch (this) {
        SessionStatus.scheduled => '予定',
        SessionStatus.confirmed => '確定',
        SessionStatus.completed => '完了',
        SessionStatus.cancelled => 'キャンセル',
      };

  /// 終了済み（これ以上予定として動かない）ステータスかどうか
  bool get isClosed =>
      this == SessionStatus.completed || this == SessionStatus.cancelled;

  /// DB文字列からの復元。未知の値は例外を投げず null を返す。
  /// （CHECK制約に将来値が増えても表示が壊れないようにするための入口）
  static SessionStatus? tryParse(String? value) => switch (value) {
        'scheduled' => SessionStatus.scheduled,
        'confirmed' => SessionStatus.confirmed,
        'completed' => SessionStatus.completed,
        'cancelled' => SessionStatus.cancelled,
        _ => null,
      };
}

/// sessions テーブルの1行。
/// ※ features/schedules（トレーナーの稼働可能時間）とは別ドメインなので混同しないこと。
@JsonSerializable()
class SessionModel {
  final String id;

  @JsonKey(name: 'trainer_id')
  final String trainerId;

  @JsonKey(name: 'client_id')
  final String clientId;

  /// 予約日時（timestamptz）。DateTimeConverterでローカル時刻に変換される
  @DateTimeConverter()
  @JsonKey(name: 'session_date')
  final DateTime sessionDate;

  /// 所要時間（分）。DBの既定値は60
  @JsonKey(name: 'duration_minutes')
  final int durationMinutes;

  /// scheduled / confirmed / completed / cancelled のいずれか（生値のまま保持）
  final String status;

  /// セッション種別。CHECK制約なしのフリーテキスト
  @JsonKey(name: 'session_type')
  final String? sessionType;

  // ※ sessions.memo はトレーナーが自分用に書く内輪メモで顧客UIには出さないため、
  //   モデルにも持たない（SessionRepository の列指定でも取得していない）。

  @JsonKey(name: 'ticket_id')
  final String? ticketId;

  /// 繰り返し予約のグループID
  @JsonKey(name: 'recurrence_group_id')
  final String? recurrenceGroupId;

  /// 紐づくノート（`client_notes.session_id → sessions.id` のFKを使った
  /// PostgREST の embed で一緒に取ってくる）。
  ///
  /// 顧客向けRLS（clients_select_shared_notes）が
  /// `is_shared = true AND client_id = auth.uid()` なので、顧客のクエリには
  /// 共有済みノートしか入ってこない（未共有ノートの存在も漏れない）。
  /// embed しない経路で取得した場合は空のまま。
  @JsonKey(name: 'client_notes')
  final List<ClientNote> notes;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const SessionModel({
    required this.id,
    required this.trainerId,
    required this.clientId,
    required this.sessionDate,
    required this.durationMinutes,
    required this.status,
    this.sessionType,
    this.ticketId,
    this.recurrenceGroupId,
    this.notes = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) =>
      _$SessionModelFromJson(json);
  Map<String, dynamic> toJson() => _$SessionModelToJson(this);

  /// 型付きステータス。未知の値なら null（例外は投げない）
  SessionStatus? get statusType => SessionStatus.tryParse(status);

  /// 表示用のステータスラベル。
  /// 未知の値は生値をそのまま返してフォールバックする（表示は崩れるが落ちない）
  String get statusLabel => statusType?.labelJa ?? status;

  /// 終了扱い（完了 / キャンセル）のステータスかどうか。
  /// 未知のステータスは「まだ生きている予定」側に倒す
  bool get isClosed => statusType?.isClosed ?? false;

  /// 終了予定時刻（開始時刻 + 所要時間）。
  /// 「今後 / 過去」の仕分けはこの終了時刻が基準（開始時刻ではない）
  DateTime get endTime => sessionDate.add(Duration(minutes: durationMinutes));

  /// 「今後」として扱うかどうか＝終了時刻がまだ来ていないこと。
  ///
  /// - 開始済みでも終了前なら true（セッション中に一覧・ホームから消えない）
  /// - ステータスは見ない。未来のキャンセル済みも「今後」に残し、顧客が
  ///   「明日の予定がキャンセルされた」ことに気付けるようにする
  ///   （キャンセル/完了であることの提示はステータスバッジの責務）
  bool get isUpcoming => endTime.isAfter(DateTime.now());

  /// JSTの暦日で見た「[reference] から何日後か」。当日=0 / 翌日=1 / 過去は負値。
  ///
  /// UI は1フレームの描画中に now を引き直すと日跨ぎで
  /// 「今日」判定と「あとN日」が食い違うため、now を1回だけ取ってこれを使う
  int daysUntilFrom(DateTime reference) =>
      _jstDateOnly(sessionDate).difference(_jstDateOnly(reference)).inDays;

  /// JSTの暦日で見た「今日から何日後か」。今日=0 / 明日=1 / 過去は負値
  int get daysUntil => daysUntilFrom(DateTime.now());

  /// JSTの暦日で今日かどうか
  bool get isToday => daysUntil == 0;

  /// JSTの暦日で明日かどうか
  bool get isTomorrow => daysUntil == 1;

  /// ClientNote.session に差し込む形（このセッションの日時・種別の抜粋）
  LinkedSession get asLinkedSession => LinkedSession(
        sessionDate: sessionDate,
        sessionType: sessionType,
      );

  /// 顧客に見せてよい共有済みノートだけを新しい順で返す。
  ///
  /// RLSにより embed には共有ノートしか返らないが、「未共有ノートの存在を
  /// 顧客に匂わせない」ことが要件なので、クライアント側でも is_shared を通す。
  ///
  /// sessions → client_notes の embed には逆向きの `sessions(...)` が入らないため、
  /// 各ノートの ClientNote.session には親であるこのセッションを補って返す
  /// （カルテ詳細のヘッダーがカルテ一覧から開いたときと同じ日時・種別を出せるように）
  List<ClientNote> get sharedNotes => notes
      .where((note) => note.isShared)
      .map((note) =>
          note.session == null ? note.withSession(asLinkedSession) : note)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// 一覧の行から開くノート（最新の共有ノート1件）。無ければ null。
  ///
  /// 1セッションに複数ノートを紐づける運用は想定していないが、万一複数あっても
  /// 行のタップ先が揺れないよう最新の1件に決め打つ
  ClientNote? get sharedNote {
    final shared = sharedNotes;
    return shared.isEmpty ? null : shared.first;
  }

  /// 一覧の行にノート導線（チップ + chevron）を出すかどうか
  bool get hasSharedNote => sharedNote != null;
}

/// 端末のタイムゾーンに依存せず、JST（UTC+9）の暦日だけを取り出す。
/// docs/tasks/lessons.md 参照: 日付比較は時刻を落として行う（タイムゾーン問題回避）。
/// DSTのある地域でも日数がずれないよう UTC 基準の DateTime として返す。
DateTime _jstDateOnly(DateTime dateTime) {
  final jst = dateTime.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(jst.year, jst.month, jst.day);
}
