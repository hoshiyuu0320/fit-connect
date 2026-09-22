// components/Layout.tsx
"use client";

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useRouter } from "next/navigation";
import {
    LayoutDashboard,
    Users,
    MessageCircle,
    FileText,
    BookOpen,
    Calendar,
    Settings,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { getUnreadCounts } from '@/lib/supabase/getUnreadCounts';
import { triageBadgeLabel } from '@/lib/triage/triageLabels';
import { useTriageBadgeStore } from '@/store/triageBadgeStore';
import { Toaster } from 'sonner';
import AppHeader from '@/components/AppHeader';

const mainMenuItems = [
    {
        label: 'ダッシュボード',
        href: '/dashboard',
        icon: LayoutDashboard,
    },
    {
        label: '顧客管理',
        href: '/clients',
        icon: Users,
    },
    {
        label: 'メッセージ',
        href: '/message',
        icon: MessageCircle,
    },
    {
        label: 'レポート',
        href: '/report',
        icon: FileText,
    },
    {
        label: 'チケット',
        href: '/tickets',
        icon: BookOpen,
    },
    {
        label: 'スケジュール',
        href: '/schedule',
        icon: Calendar,
    },
];

const settingsMenuItem = {
    label: '設定',
    href: '/settings',
    icon: Settings,
};

/** ナビ項目のバッジ（0 のときは出さない） */
type NavBadge = {
    count: number;
    /** 読み上げ用の名前（例:「今日の対応 3人」） */
    label: string;
    /** 背景色・文字色のクラス */
    colorClassName: string;
};

// バッジはアクセント色（red / amber は重要度の表示だけに使う）
const ACCENT_BADGE_COLOR = 'bg-[#14B8A6] text-white';

export default function Sidebar({ children }: { children: React.ReactNode }) {
    const pathname = usePathname();
    const router = useRouter();
    const [totalUnread, setTotalUnread] = useState(0);
    const triageCount = useTriageBadgeStore((state) => state.count);
    const refreshTriageBadge = useTriageBadgeStore((state) => state.refresh);

    // 「今日の対応」のバッジ: 表示時と画面を移るたびに数え直す
    // （Realtime は使わない。アラートの検知は1日1回、未返信は画面遷移・タブ復帰・返信の後に取り直す。
    //   「今日の対応」の操作の後は TriageSection が、返信の後はメッセージ画面が数え直す）
    useEffect(() => {
        void refreshTriageBadge();
    }, [pathname, refreshTriageBadge]);

    // タブに戻ったときも数え直す（朝の検知の後、開きっぱなしのタブに反映する）
    useEffect(() => {
        const handleVisibilityChange = () => {
            if (document.visibilityState === 'visible') void refreshTriageBadge();
        };
        document.addEventListener('visibilitychange', handleVisibilityChange);
        return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
    }, [refreshTriageBadge]);

    // 未読数取得 + Realtime購読
    useEffect(() => {
        let channel: ReturnType<typeof supabase.channel> | null = null;
        let debounceTimer: NodeJS.Timeout | null = null;

        const fetchUnread = async () => {
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) return;

            const refreshCount = () => {
                getUnreadCounts(user.id).then((counts) => {
                    let total = 0;
                    counts.forEach((count) => { total += count; });
                    setTotalUnread(total);
                });
            };

            refreshCount();

            const debouncedRefresh = () => {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(refreshCount, 300);
            };

            channel = supabase
                .channel('sidebar-unread')
                .on('postgres_changes', {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'messages',
                    filter: `receiver_id=eq.${user.id}`,
                }, (payload) => {
                    // 新着メッセージ: read_atがnullなら即+1（体感リアルタイム）
                    if (payload.new && !(payload.new as { read_at: string | null }).read_at) {
                        setTotalUnread((prev) => prev + 1);
                    }
                })
                .on('postgres_changes', {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'messages',
                    filter: `receiver_id=eq.${user.id}`,
                }, debouncedRefresh)
                .subscribe();
        };

        fetchUnread();

        return () => {
            if (channel) supabase.removeChannel(channel);
            if (debounceTimer) clearTimeout(debounceTimer);
        };
    }, []);

    // 項目ごとのバッジ（値・読み上げ・色）
    const navBadges: Record<string, NavBadge> = {
        '/dashboard': {
            count: triageCount,
            label: triageBadgeLabel(triageCount),
            colorClassName: ACCENT_BADGE_COLOR,
        },
        '/message': {
            count: totalUnread,
            label: `未読 ${totalUnread}件`,
            colorClassName: ACCENT_BADGE_COLOR,
        },
    };

    const renderNavItem = (item: typeof mainMenuItems[number] | typeof settingsMenuItem, badge?: NavBadge) => {
        const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
        const Icon = item.icon;

        return (
            <button
                key={item.href}
                onClick={() => router.push(item.href)}
                className={`
                    flex flex-col items-center gap-1 py-2 px-1 w-16 rounded-md
                    transition-colors duration-150
                    ${isActive
                        ? 'bg-[#F0FDFA] text-[#14B8A6]'
                        : 'text-[#94A3B8] hover:bg-[#F8FAFC]'
                    }
                `}
            >
                <div className="relative">
                    <Icon size={20} strokeWidth={1.75} />
                    {badge && badge.count > 0 && (
                        // 数字だけでは何の数か伝わらないので、読み上げには label を使う
                        <span
                            role="img"
                            aria-label={badge.label}
                            className={`absolute -top-1 -right-1 ${badge.colorClassName} text-[9px] font-bold rounded-full min-w-[16px] h-[16px] flex items-center justify-center px-0.5 leading-none`}
                        >
                            {badge.count > 99 ? '99+' : badge.count}
                        </span>
                    )}
                </div>
                <span className="text-[10px] font-medium leading-tight">{item.label}</span>
            </button>
        );
    };

    return (
        <>
        <AppHeader />
        {/* コンテンツは全て fixed 配置（top-14 で AppHeader 分をオフセット）のため、main 自体の padding は不要 */}
        <main className="!pt-0">
            {/* fixed top-14 left-0 right-0 bottom-0 は子要素をスクロールさせないため */}
            <div className="fixed flex h-screen top-14 left-0 right-0 bottom-0">
                <aside
                    className="
                        w-20 flex-shrink-0
                        h-[calc(100vh-56px)]
                        bg-white
                        border-r border-[#E2E8F0]
                        fixed left-0 top-14
                        z-40
                        flex flex-col
                    "
                >
                    {/* メインナビゲーション */}
                    <nav className="flex flex-col items-center gap-1 py-3 flex-1">
                        {mainMenuItems.map((item) =>
                            renderNavItem(item, navBadges[item.href])
                        )}
                    </nav>

                    {/* 設定ボタン（下部固定） */}
                    <footer className="flex flex-col items-center pb-4 border-t border-[#E2E8F0] pt-3">
                        {renderNavItem(settingsMenuItem)}
                    </footer>
                </aside>

                {/* メインコンテンツ */}
                <section className="flex-1 bg-[#F8FAFC] ml-20 overflow-y-auto">
                    {children}
                </section>
            </div>
            <Toaster
                position="top-right"
                // 読み上げの名前（Alt+T でトーストに移り、「元に戻す」をキーボードで押せる）
                containerAriaLabel="通知"
                toastOptions={{
                    style: {
                        fontFamily: "'Noto Sans JP', 'Plus Jakarta Sans', sans-serif",
                    },
                }}
            />
        </main>
        </>
    );
}
