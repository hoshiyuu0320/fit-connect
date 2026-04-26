export function ScheduleSkeleton() {
  return (
    <div className="h-[calc(100vh-48px)] overflow-hidden flex flex-col animate-pulse" style={{ backgroundColor: '#F8FAFC' }}>

      {/* ヘッダー（ツールバー相当） */}
      <div className="flex-shrink-0 bg-white border-b" style={{ borderColor: '#E2E8F0' }}>

        {/* 上段: タイトル + ボタン群 */}
        <div className="flex items-center justify-between px-6 py-2.5">
          <div className="h-6 w-36 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
          <div className="flex items-center gap-3">
            <div className="h-9 w-36 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
            <div className="h-9 w-36 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
          </div>
        </div>

        {/* 下段: ビュー切替 + ナビ | 検索 + セレクター */}
        <div className="flex items-center justify-between px-6 py-2">
          <div className="flex items-center gap-3">
            {/* セグメントコントロール */}
            <div className="h-9 w-36 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
            {/* ナビゲーション */}
            <div className="h-9 w-40 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
          </div>
          <div className="flex items-center gap-3">
            {/* 検索 */}
            <div className="h-9 w-44 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
            {/* クライアントセレクター */}
            <div className="h-9 w-36 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
          </div>
        </div>
      </div>

      {/* カレンダー本体 */}
      <div className="flex-1 overflow-hidden bg-white border" style={{ borderColor: '#E2E8F0' }}>

        {/* 曜日ヘッダー行 */}
        <div className="flex border-b" style={{ borderColor: '#E2E8F0' }}>
          {/* 時刻列のスペーサー */}
          <div className="w-[60px] flex-shrink-0 border-r" style={{ borderColor: '#E2E8F0' }} />
          {/* 7列分の曜日セル */}
          {[...Array(7)].map((_, i) => (
            <div
              key={i}
              className="flex-1 py-3 flex flex-col items-center gap-1 border-r last:border-0"
              style={{ borderColor: '#E2E8F0' }}
            >
              <div className="h-3 w-4 rounded" style={{ backgroundColor: '#E2E8F0' }} />
              <div className="h-5 w-6 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
            </div>
          ))}
        </div>

        {/* タイムグリッド */}
        <div className="flex overflow-hidden" style={{ height: 'calc(100% - 56px)' }}>
          {/* 時刻列 */}
          <div className="w-[60px] flex-shrink-0 border-r" style={{ borderColor: '#E2E8F0' }}>
            {[...Array(8)].map((_, i) => (
              <div
                key={i}
                className="h-20 border-b flex items-start justify-end pr-2 pt-1"
                style={{ borderColor: '#E2E8F0' }}
              >
                <div className="h-3 w-8 rounded" style={{ backgroundColor: '#E2E8F0' }} />
              </div>
            ))}
          </div>

          {/* 7列分のグリッド */}
          <div className="flex-1 grid grid-cols-7">
            {[...Array(7)].map((_, colIdx) => (
              <div
                key={colIdx}
                className="relative border-r last:border-0"
                style={{ borderColor: '#E2E8F0' }}
              >
                {/* 時間行の区切り線 */}
                {[...Array(8)].map((_, rowIdx) => (
                  <div
                    key={rowIdx}
                    className="h-20 border-b"
                    style={{ borderColor: '#E2E8F0' }}
                  />
                ))}

                {/* セッションブロックの骨格（一部の列に表示） */}
                {colIdx === 1 && (
                  <div
                    className="absolute left-1 right-1 rounded-md"
                    style={{
                      top: '40px',
                      height: '64px',
                      backgroundColor: '#E2E8F0',
                    }}
                  />
                )}
                {colIdx === 3 && (
                  <div
                    className="absolute left-1 right-1 rounded-md"
                    style={{
                      top: '120px',
                      height: '80px',
                      backgroundColor: '#E2E8F0',
                    }}
                  />
                )}
                {colIdx === 5 && (
                  <div
                    className="absolute left-1 right-1 rounded-md"
                    style={{
                      top: '80px',
                      height: '48px',
                      backgroundColor: '#E2E8F0',
                    }}
                  />
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
