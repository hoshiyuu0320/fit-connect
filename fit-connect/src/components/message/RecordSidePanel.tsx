"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { X, ClipboardList } from "lucide-react";
import type { Message } from "@/types/client";
import type { DailyNutritionPoint } from "@/lib/nutrition/aggregate";
import type { RecordCardType } from "@/components/message/recordCardParser";
import { RecordCard } from "@/components/message/RecordCard";
import { PfcBalanceCard } from "@/components/clients/PfcBalanceCard";
import { WeightNutritionChart } from "@/components/clients/WeightNutritionChart";
import { extractRecordLog, filterByType } from "@/components/message/recordLog";
import { ResizeHandle } from "@/components/message/ResizeHandle";
import { useResizablePanel } from "@/hooks/useResizablePanel";

interface RecordSidePanelProps {
  messages: Message[];
  clientId: string;
  nutritionData: DailyNutritionPoint[];
  targetWeight?: number;
  summaryLoading?: boolean;
  width: number;
  isResizing: boolean;
  resizeHandleProps: Record<string, unknown>;
  onClose: () => void;
  onImageClick: (url: string) => void;
}

const TYPE_TABS: { value: RecordCardType | "all"; label: string }[] = [
  { value: "all", label: "すべて" },
  { value: "meal", label: "食事" },
  { value: "weight", label: "体重" },
  { value: "exercise", label: "運動" },
];

export function RecordSidePanel({
  messages,
  clientId,
  nutritionData,
  targetWeight,
  summaryLoading,
  width,
  isResizing,
  resizeHandleProps,
  onClose,
  onImageClick,
}: RecordSidePanelProps) {
  const [typeFilter, setTypeFilter] = useState<RecordCardType | "all">("all");

  // サマリー上限をウィンドウ高さに動的追従させるための計測用 ref
  const asideRef = useRef<HTMLElement>(null);
  const headerRef = useRef<HTMLDivElement>(null);
  const filterRef = useRef<HTMLDivElement>(null);
  // 動的 max（SSR/初期値は従来の 680）
  const [maxSummaryHeight, setMaxSummaryHeight] = useState(680);

  // 記録ログの最小ピーク / サマリー上限の上限・下限ガード
  const LOG_MIN = 8;
  const SUMMARY_MAX_CAP = 1000;
  const SUMMARY_MAX_FLOOR = 320;

  // サマリー↔記録ログの高さ配分（縦ドラッグ・localStorage 永続化）
  const summaryResize = useResizablePanel({
    axis: "y",
    storageKey: "fc.message.recordSummaryHeight",
    defaultSize: 440,
    min: 80,
    max: maxSummaryHeight,
    edge: "bottom",
  });

  // 利用可能高さ（aside − header − filter − LOG_MIN）を max に反映。ウィンドウ/幅変更にも追従
  useEffect(() => {
    const aside = asideRef.current;
    if (!aside) return;
    const recompute = () => {
      const headerH = headerRef.current?.offsetHeight ?? 0;
      const filterH = filterRef.current?.offsetHeight ?? 0;
      const available = aside.clientHeight - headerH - filterH;
      const next = Math.min(
        SUMMARY_MAX_CAP,
        Math.max(SUMMARY_MAX_FLOOR, available - LOG_MIN)
      );
      setMaxSummaryHeight(next);
    };
    recompute();
    const ro = new ResizeObserver(recompute);
    ro.observe(aside);
    return () => ro.disconnect();
  }, []);

  const logItems = useMemo(() => {
    const all = extractRecordLog(messages);
    // filterByType('all') は元配列をそのまま返すため slice() で複製してから reverse（in-place 破壊防止）
    return filterByType(all, typeFilter).slice().reverse();
  }, [messages, typeFilter]);

  return (
    <aside
      ref={asideRef}
      style={{ width }}
      className="relative shrink-0 bg-white border-l border-[#E2E8F0] flex flex-col h-full overflow-hidden"
    >
      {/* 左端リサイズハンドル */}
      <ResizeHandle
        side="left"
        isDragging={isResizing}
        ariaLabel="記録パネルの幅を調整"
        handleProps={resizeHandleProps}
      />

      {/* ヘッダー */}
      <div
        ref={headerRef}
        className="flex items-center justify-between px-4 py-3 border-b border-[#E2E8F0] flex-shrink-0"
      >
        <div className="flex items-center gap-2">
          <ClipboardList
            className="w-4 h-4 text-[#64748B]"
            aria-hidden="true"
          />
          <span className="text-sm font-semibold text-[#0F172A]">記録</span>
        </div>
        <button
          type="button"
          aria-label="記録パネルを閉じる"
          onClick={onClose}
          className="cursor-pointer p-1 rounded-md text-[#64748B] hover:text-[#0F172A] hover:bg-[#F1F5F9] transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
        >
          <X className="w-4 h-4" aria-hidden="true" />
        </button>
      </div>

      {/* サマリーセクション（高さ可変・内部スクロール） */}
      {/* 外側は relative のみ。overflow-hidden は付けない（下端ハンドルの translate-y-1/2 がクリップされるため） */}
      <div
        className="relative flex-shrink-0"
        style={{ height: summaryResize.size }}
      >
        <div className="h-full overflow-y-auto border-b border-[#E2E8F0]">
          {/* min-h-full でサマリーが高い時は満たし、低い時は内容がはみ出してスクロール */}
          <div className="min-h-full flex flex-col px-4 pt-4 pb-2">
            <p className="text-xs text-[#64748B] uppercase tracking-wide font-semibold mb-3 flex-shrink-0">
              サマリー
            </p>

            {/* 体重 × 栄養トレンドグラフ（flex-1 で拡大、最低 320px は確保） */}
            {/* relative + absolute inset-0 で確定高さを与える（recharts height="100%" が flex 由来の高さでは 0 に解決するため） */}
            <div className="flex-1 min-h-[320px] mb-4 relative">
              <div className="absolute inset-0">
                <WeightNutritionChart
                  fillHeight
                  data={nutritionData}
                  targetWeight={targetWeight}
                  loading={summaryLoading}
                />
              </div>
            </div>

            {/* PFCバランスカード */}
            <div className="overflow-x-auto flex-shrink-0">
              <PfcBalanceCard data={nutritionData} />
            </div>
          </div>
        </div>

        {/* 下端リサイズハンドル（サマリー/フィルタ境界） */}
        <ResizeHandle
          side="bottom"
          isDragging={summaryResize.isDragging}
          ariaLabel="サマリーと記録ログの高さを調整"
          handleProps={summaryResize.handleProps}
        />
      </div>

      {/* 種別フィルタ chips */}
      <div
        ref={filterRef}
        className="flex items-center gap-2 px-4 py-3 border-b border-[#E2E8F0] flex-shrink-0 flex-wrap"
      >
        {TYPE_TABS.map((tab) => {
          const isActive = typeFilter === tab.value;
          return (
            <button
              key={tab.value}
              type="button"
              onClick={() => setTypeFilter(tab.value)}
              className={[
                "cursor-pointer px-3 py-1 text-xs font-medium rounded-md border transition-colors duration-200",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]",
                isActive
                  ? "bg-[#14B8A6] text-white border-[#14B8A6]"
                  : "bg-white text-[#64748B] border-[#E2E8F0] hover:border-[#14B8A6] hover:text-[#0F172A]",
              ].join(" ")}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* 記録ログ */}
      <div className="flex-1 overflow-y-auto">
        {logItems.length === 0 ? (
          /* Empty state */
          <div className="flex flex-col items-center justify-center h-full px-6 py-12 text-center">
            <ClipboardList
              className="w-10 h-10 text-[#94A3B8] mb-3"
              aria-hidden="true"
            />
            <p className="text-sm font-semibold text-[#0F172A]">
              記録がありません
            </p>
            <p className="text-xs text-[#64748B] mt-2 leading-relaxed">
              クライアントが食事・体重・運動を記録すると、ここに表示されます
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-[#E2E8F0]">
            {logItems.map((item) => (
              <li key={item.message.id} className="px-4 py-3">
                <RecordCard
                  data={item.card}
                  clientId={clientId}
                  imageUrls={item.message.image_urls}
                  onImageClick={onImageClick}
                />
                <p className="text-[10px] text-[#94A3B8] mt-1.5">
                  {new Date(item.message.created_at).toLocaleString("ja-JP", {
                    month: "numeric",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </aside>
  );
}
