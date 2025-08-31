"use client"

import { useEffect, useState } from "react";
import { supabase } from '@/lib/supabase';
import { getProfile } from '@/lib/supabase/getProfile';
import { useUserStore } from '@/store/userStore';
import React from 'react';

export default function DashboardPage() {
    const [loading, setLoading] = useState(true);
    const [name, setName] = useState<string | null>(null)
    const userName = useUserStore((state) => state.userName)
    const setUserName = useUserStore((state) => state.setUserName);

    const today = new Date();
    const formatted = today.toLocaleDateString('ja-JP', {
        month: 'long',
        day: 'numeric',
        weekday: 'short', // または 'long'
    });

    useEffect(() => {
        const fetchProfile = async () => {
            setLoading(true); // ローディング開始

            const {
                data: { user },
            } = await supabase.auth.getUser()

            if (user) {
                try {
                    const profile = await getProfile(user.id)
                    if (profile?.name) {
                        setUserName(profile.name);
                    }
                } catch (err) {
                    console.log('プロフィール取得エラー:', err)
                }
            }
            setLoading(false); // ローディング終了
        }
        fetchProfile()
    }, [setUserName])

    if (loading) {
        return (
            <div className="flex items-center justify-center h-screen">
                <div className="animate-spin rounded-full h-8 w-8 border-4 border-gray-300 border-t-transparent"></div>
            </div>
        );
    }

    return (
        <main>
            <div>
                <p className="text-[#3b4b5b] tracking-light text-[32px] font-bold leading-tight">{`おはようございます ${userName}さん！`}</p>
                <div className="flex pt-[64px]">
                    <h2 className="text-[#111418] w-[691px] h-[76px] text-[22px] font-bold leading-tight tracking-[-0.015em] px-4 pb-3">{formatted}</h2>
                    <div className="flex-col">
                        <div className="flex">
                            <h2 className="text-[#111418] w-[369px] text-[22px] font-bold leading-tight tracking-[-0.015em] px-4 pb-3">本日の予定</h2>
                            <p className="flex items-center text-[#859bb4] tracking-light text-[18px] leading-tight">3</p>
                        </div>
                        <div className="h-[160px]">
                            <p className="text-[#141414] font-medium leading-normal px-4">Upcoming Sessions</p>
                        </div>
                        <div className="flex">
                            <h2 className="text-[#111418] w-[369px] text-[22px] font-bold leading-tight tracking-[-0.015em] px-4 pb-3">本日の通知</h2>
                            <p className="flex items-center text-[#859bb4] tracking-light text-[18px] leading-tight">3</p>
                        </div>
                        <div className="h-[160px]">

                        </div>
                    </div>
                </div>
            </div>
        </main>
    );
}