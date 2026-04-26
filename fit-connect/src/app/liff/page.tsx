"use client";
import { useEffect, useState } from "react";
import liff from "@line/liff";
import { saveLineUser } from "@/lib/supabase/saveLineUser";

export default function LiffPage() {

    const [status, setStatus] = useState<string>("読み込み中...");
    useEffect(() => {
        const initLiff = async () => {
            try {
                // LIFF初期化
                await liff.init({ liffId: process.env.NEXT_PUBLIC_LIFF_ID! });
                console.log("LIFF初期化完了");

                // 未ログインならLINEログインへ
                if (!liff.isLoggedIn()) {
                    liff.login();
                    return;
                }

                // LINEプロフィール取得
                const profileData = await liff.getProfile();
                console.log("lineProfileData", profileData);

                // URLからtrainerId取得
                const trainerId = new URLSearchParams(window.location.search).get("trainerId");
                console.log("trainerId", trainerId);
                if (!trainerId) {
                    console.log("トレーナーIDが指定されていません", trainerId);
                    setStatus("トレーナーIDが指定されていません");
                    return;
                }
                try {
                    await saveLineUser({
                        lineUserid: profileData.userId,
                        name: profileData.displayName,
                        trainerId: trainerId,
                    });
                } catch (err) {
                    console.error("Supabase保存エラー:", err);
                    setStatus("保存に失敗しました");
                }
                setStatus("登録が完了しました！友達追加に進みます...");

                window.location.href = 'https://line.me/R/ti/p/%40993qduho';
            } catch (err) {
                console.error("LIFF初期化エラー:", err);
                setStatus("エラーが発生しました");
            }
        };

        initLiff();
    }, []);

    return (
        <div className="flex flex-col items-center justify-center min-h-screen p-6 bg-white">
            {status}
        </div>
    );
}