"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabase"

type DevLoginButtonInnerProps = {
    email: string
    password: string
}

function DevLoginButtonInner({ email, password }: DevLoginButtonInnerProps) {
    const [loading, setLoading] = useState(false)
    const router = useRouter()

    const handleDevLogin = async () => {
        setLoading(true)
        try {
            const { error } = await supabase.auth.signInWithPassword({ email, password })
            if (error) {
                throw error
            }
            router.push("/dashboard")
        } catch (error) {
            console.error("[DevLoginButton] テストログインに失敗しました", error)
            alert("テストログインに失敗しました")
            setLoading(false)
        }
    }

    return (
        <button
            type="button"
            onClick={handleDevLogin}
            disabled={loading}
            className="mt-3 w-full flex items-center justify-center gap-2 h-11 bg-white border border-dashed border-[#94A3B8] rounded-md text-sm font-medium text-[#475569] hover:bg-[#F8FAFC] hover:text-[#0F172A] transition-colors cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
        >
            <span className="px-1.5 py-0.5 border border-[#E2E8F0] rounded text-[10px] font-semibold text-[#94A3B8] leading-none">
                開発用
            </span>
            {loading ? "ログイン中..." : "テストログイン"}
        </button>
    )
}

/**
 * 開発用のテストログインボタン。
 * `next dev`（NODE_ENV === 'development'）でのみ描画される。
 * 本番ビルドでは NODE_ENV が 'production' としてインライン化されるため、
 * このガード内の環境変数参照（認証情報）とボタン本体はデッドコードとして除去される。
 */
export default function DevLoginButton() {
    if (process.env.NODE_ENV === "development") {
        const email = process.env.NEXT_PUBLIC_DEV_LOGIN_EMAIL ?? ""
        const password = process.env.NEXT_PUBLIC_DEV_LOGIN_PASSWORD ?? ""
        if (email && password) {
            return <DevLoginButtonInner email={email} password={password} />
        }
    }
    return null
}
