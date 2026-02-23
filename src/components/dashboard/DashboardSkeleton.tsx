export function DashboardSkeleton() {
  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-7xl mx-auto p-6 space-y-6 animate-pulse">
        {/* ヘッダー */}
        <div className="mb-8">
          <div className="h-9 bg-gray-200 rounded-lg w-72 mb-2" />
          <div className="h-5 bg-gray-200 rounded w-32" />
        </div>

        {/* KPIカード */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div
              key={i}
              className="bg-white rounded-xl border border-gray-200 border-l-4 border-l-gray-200 p-6"
            >
              <div className="flex items-center justify-between mb-4">
                <div className="h-4 bg-gray-200 rounded w-24" />
                <div className="w-10 h-10 bg-gray-200 rounded-lg" />
              </div>
              <div className="h-8 bg-gray-200 rounded w-16" />
            </div>
          ))}
        </div>

        {/* 本日の予定 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="h-5 bg-gray-200 rounded w-32 mb-4" />
          <div className="space-y-3">
            {[...Array(2)].map((_, i) => (
              <div key={i} className="flex items-center gap-4 p-3">
                <div className="h-4 bg-gray-200 rounded w-20" />
                <div className="h-4 bg-gray-200 rounded flex-1" />
                <div className="h-6 bg-gray-200 rounded w-16" />
              </div>
            ))}
          </div>
        </div>

        {/* メッセージ + アラート */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {[...Array(2)].map((_, i) => (
            <div key={i} className="bg-white rounded-xl border border-gray-200 p-6">
              <div className="h-5 bg-gray-200 rounded w-36 mb-4" />
              <div className="space-y-3">
                {[...Array(3)].map((_, j) => (
                  <div key={j} className="flex items-center gap-3 p-2">
                    <div className="w-9 h-9 bg-gray-200 rounded-full" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 bg-gray-200 rounded w-24" />
                      <div className="h-3 bg-gray-200 rounded w-40" />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* クイックアクション */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-white rounded-xl border border-gray-200 p-4 h-20" />
          ))}
        </div>
      </div>
    </main>
  )
}
