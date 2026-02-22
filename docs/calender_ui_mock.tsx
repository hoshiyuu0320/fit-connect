import React from 'react';
// import { DndContext, closestCenter } from '@dnd-kit/core';
// import { SortableContext } from '@dnd-kit/sortable';

export default function WorkoutPlanCalendar({ clientId }: { clientId: string }) {
    return (
        <div className="flex h-screen bg-gray-50 overflow-hidden">
            {/* ========================================
        ヘッダーエリア
        ========================================
      */}
            <header className="absolute top-0 w-full h-16 bg-white border-b flex items-center justify-between px-6 z-10">
                <div className="flex items-center gap-4">
                    <button className="text-gray-500 hover:text-gray-800">← 戻る</button>
                    <h1 className="text-xl font-bold text-gray-800">山田 太郎のプラン</h1>
                </div>
                <div className="flex items-center gap-2">
                    <button className="p-2 border rounded-md hover:bg-gray-100">先週</button>
                    <span className="font-semibold mx-4">2026年2月 第3週</span>
                    <button className="p-2 border rounded-md hover:bg-gray-100">来週</button>
                </div>
            </header>

            {/* DndContext Provider をここでラップする想定 */}
            <main className="flex w-full pt-16">

                {/* ========================================
          左ペイン：テンプレートリスト（ドラッグ元）
          ========================================
        */}
                <aside className="w-80 bg-white border-r flex flex-col h-full">
                    <div className="p-4 border-b">
                        <h2 className="text-sm font-bold text-gray-500 mb-2">テンプレート</h2>
                        <input
                            type="text"
                            placeholder="検索..."
                            className="w-full p-2 border rounded-md text-sm"
                        />
                    </div>
                    <div className="flex-1 overflow-y-auto p-4 space-y-3">
                        {/* Draggable Template Card */}
                        <div className="p-3 bg-gray-50 border rounded-lg cursor-grab hover:shadow-md transition-shadow active:cursor-grabbing">
                            <div className="font-bold text-gray-800">🏋️ 胸・三頭筋 (初心者)</div>
                            <div className="text-xs text-gray-500 mt-1">4種目 / 約45分</div>
                        </div>
                        <div className="p-3 bg-gray-50 border rounded-lg cursor-grab hover:shadow-md transition-shadow active:cursor-grabbing">
                            <div className="font-bold text-gray-800">🦵 脚・腹筋 (基本)</div>
                            <div className="text-xs text-gray-500 mt-1">5種目 / 約60分</div>
                        </div>
                        {/* ... other templates ... */}
                    </div>
                </aside>

                {/* ========================================
          右ペイン：週間カレンダー（ドロップ先）
          ========================================
        */}
                <section className="flex-1 overflow-x-auto p-6">
                    <div className="grid grid-cols-7 gap-4 min-w-[800px] h-full">
                        {/* Day Column (Droppable Area) */}
                        {['月 (2/16)', '火 (2/17)', '水 (2/18)', '木 (2/19)', '金 (2/20)', '土 (2/21)', '日 (2/22)'].map((day, index) => (
                            <div key={day} className="flex flex-col bg-gray-100/50 rounded-xl p-2 border border-transparent hover:border-blue-200 transition-colors">
                                <div className="text-center font-bold text-gray-600 mb-4 pb-2 border-b">
                                    {day}
                                </div>

                                {/* Sortable Context for Items in this column */}
                                <div className="flex-1 space-y-3 min-h-[150px]">

                                    {/* Assigned Plan Card (Draggable between days) */}
                                    {index === 0 && ( // 月曜日のモック
                                        <div className="bg-white border rounded-lg p-3 shadow-sm cursor-grab active:cursor-grabbing">
                                            <div className="flex justify-between items-start mb-2">
                                                {/* ステータスバッジ */}
                                                <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
                                                    🟢 完了
                                                </span>
                                                <button className="text-gray-400 hover:text-red-500 text-xs">×</button>
                                            </div>
                                            <div className="font-bold text-sm text-gray-800">胸・三頭筋 (初心者)</div>
                                        </div>
                                    )}

                                    {index === 3 && ( // 木曜日のモック
                                        <div className="bg-white border rounded-lg p-3 shadow-sm cursor-grab active:cursor-grabbing">
                                            <div className="flex justify-between items-start mb-2">
                                                {/* ステータスバッジ */}
                                                <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600">
                                                    ⚪️ 未実施
                                                </span>
                                                <button className="text-gray-400 hover:text-red-500 text-xs">×</button>
                                            </div>
                                            <div className="font-bold text-sm text-gray-800">脚・腹筋 (基本)</div>
                                        </div>
                                    )}

                                    {/* ドロップ時のプレースホルダー（視覚的フィードバック）用 */}
                                </div>
                            </div>
                        ))}
                    </div>
                </section>
            </main>
        </div>
    );
}