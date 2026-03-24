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
    Newspaper,
    Settings,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { getUnreadCounts } from '@/lib/supabase/getUnreadCounts';
import { Toaster } from 'sonner';

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
    {
        label: 'AIニュース',
        href: '/ai-news',
        icon: Newspaper,
    },
];

const settingsMenuItem = {
    label: '設定',
    href: '/settings',
    icon: Settings,
};

export default function Sidebar({ children }: { children: React.ReactNode }) {
    const pathname = usePathname();
    const router = useRouter();
    const [totalUnread, setTotalUnread] = useState(0);

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

    const renderNavItem = (item: typeof mainMenuItems[number] | typeof settingsMenuItem, showBadge = false) => {
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
                    {showBadge && totalUnread > 0 && (
                        <span className="absolute -top-1 -right-1 bg-[#14B8A6] text-white text-[9px] font-bold rounded-full min-w-[16px] h-[16px] flex items-center justify-center px-0.5 leading-none">
                            {totalUnread > 99 ? '99+' : totalUnread}
                        </span>
                    )}
                </div>
                <span className="text-[10px] font-medium leading-tight">{item.label}</span>
            </button>
        );
    };

    return (
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
                            renderNavItem(item, item.href === '/message')
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
                toastOptions={{
                    style: {
                        fontFamily: "'Noto Sans JP', 'Plus Jakarta Sans', sans-serif",
                    },
                }}
            />
        </main>
    );
}
