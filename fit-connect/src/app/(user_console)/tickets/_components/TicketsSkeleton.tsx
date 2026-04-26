export function TicketsSkeleton() {
  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto" style={{ backgroundColor: '#F8FAFC' }}>
      <div className="max-w-6xl mx-auto p-6 space-y-6 animate-pulse">

        {/* ページタイトル */}
        <div>
          <div className="h-7 w-48 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
          <div className="h-4 w-64 rounded mt-2" style={{ backgroundColor: '#E2E8F0' }} />
        </div>

        {/* KPIサマリーバー */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div
              key={i}
              className="bg-white border rounded-md p-4"
              style={{ borderColor: '#E2E8F0' }}
            >
              <div className="flex items-center gap-3 mb-2">
                <div
                  className="w-9 h-9 rounded-md flex-shrink-0"
                  style={{ backgroundColor: '#E2E8F0' }}
                />
                <div className="h-4 w-24 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
              </div>
              <div className="h-7 w-12 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
              <div className="h-3 w-32 rounded mt-2" style={{ backgroundColor: '#E2E8F0' }} />
            </div>
          ))}
        </div>

        {/* タブバー */}
        <div>
          <div
            className="flex items-center gap-1 border-b pb-3"
            style={{ borderColor: '#E2E8F0' }}
          >
            <div
              className="h-4 w-28 rounded-md mx-4"
              style={{ backgroundColor: '#E2E8F0' }}
            />
            <div
              className="h-4 w-36 rounded-md mx-4"
              style={{ backgroundColor: '#E2E8F0' }}
            />
            <div
              className="h-4 w-20 rounded-md mx-4"
              style={{ backgroundColor: '#E2E8F0' }}
            />
          </div>

          {/* テーブルコンテンツ */}
          <div className="mt-6">
            <div
              className="bg-white border rounded-md overflow-hidden"
              style={{ borderColor: '#E2E8F0' }}
            >
              {/* テーブルヘッダー */}
              <div
                className="flex items-center gap-4 px-4 py-3 border-b"
                style={{ backgroundColor: '#F8FAFC', borderColor: '#E2E8F0' }}
              >
                <div className="h-3 w-16 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-24 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-12 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-14 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-20 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-16 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                <div className="h-3 w-10 rounded" style={{ backgroundColor: '#E2E8F0' }} />
              </div>

              {/* テーブル行 */}
              {[...Array(5)].map((_, i) => (
                <div
                  key={i}
                  className="flex items-center gap-4 px-4 py-3"
                  style={{
                    borderBottom: i < 4 ? '1px solid #E2E8F0' : 'none',
                  }}
                >
                  {/* アバター + 名前 */}
                  <div className="flex items-center gap-2 w-28 flex-shrink-0">
                    <div
                      className="w-7 h-7 rounded-full flex-shrink-0"
                      style={{ backgroundColor: '#E2E8F0' }}
                    />
                    <div
                      className="h-3 rounded flex-1"
                      style={{ backgroundColor: '#E2E8F0', minWidth: '3rem' }}
                    />
                  </div>

                  {/* チケット名 */}
                  <div
                    className="h-3 w-32 rounded flex-shrink-0"
                    style={{ backgroundColor: '#E2E8F0' }}
                  />

                  {/* 種別バッジ */}
                  <div
                    className="h-5 w-16 rounded-md flex-shrink-0"
                    style={{ backgroundColor: '#E2E8F0' }}
                  />

                  {/* 残回数 + プログレスバー */}
                  <div className="flex-shrink-0 w-24 space-y-1">
                    <div className="h-3 w-20 rounded" style={{ backgroundColor: '#E2E8F0' }} />
                    <div className="h-1.5 w-full rounded-full" style={{ backgroundColor: '#E2E8F0' }} />
                  </div>

                  {/* 有効期限 */}
                  <div
                    className="h-3 w-36 rounded flex-shrink-0"
                    style={{ backgroundColor: '#E2E8F0' }}
                  />

                  {/* ステータスバッジ */}
                  <div
                    className="h-5 w-16 rounded-md flex-shrink-0"
                    style={{ backgroundColor: '#E2E8F0' }}
                  />

                  {/* 操作ボタン */}
                  <div className="flex gap-1 flex-shrink-0">
                    <div className="h-6 w-8 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
                    <div className="h-6 w-8 rounded-md" style={{ backgroundColor: '#E2E8F0' }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

      </div>
    </div>
  )
}
