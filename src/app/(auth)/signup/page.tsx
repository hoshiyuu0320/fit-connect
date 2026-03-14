"use client"

import { useState } from "react"
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { createTrainer } from '@/lib/supabase/createTrainer'


export default function SignUpPage() {
    const [fullName, setFullName] = useState("");
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const router = useRouter();

    const handleSignUp = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();

        if (password !== confirmPassword) {
            alert('パスワードが一致しません');
            return;
        }
        if (password.length < 6) {
            alert('パスワードは6文字以上である必要があります');
            return;
        }

        try {
            const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
                email: email,
                password: password,
                options: {
                    emailRedirectTo: `${location.origin}/auth/callback`,
                },
            })

            if (signUpError) {
                throw signUpError;
            }

            alert('登録完了メールを確認してください');
            const userId = signUpData.user?.id;
            if (!userId) return;

            await createTrainer(userId, fullName, email)
        } catch (error: unknown) {
            console.error('Signup error:', error);
            const message = error instanceof Error ? error.message : 'エラーが発生しました';
            alert(message);
        }
    }

    const moveLoginPage = () => {
        router.push('/login');
    }

    const handleFullNameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setFullName(e.target.value)
    }

    const handleEmailChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setEmail(e.target.value)
    }

    const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setPassword(e.target.value)
    }

    const handleConfirmPasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setConfirmPassword(e.target.value)
    }

    const handleGoogleSignUp = async () => {
        const { error } = await supabase.auth.signInWithOAuth({
            provider: 'google',
            options: { redirectTo: `${location.origin}/auth/callback` },
        })
        if (error) alert('Google認証に失敗しました')
    }


    return (
        <main className="flex flex-col items-center justify-center min-h-screen bg-[#F8FAFC] px-4">
            <div className="w-full max-w-md">
                {/* Logo */}
                <div className="text-center mb-8">
                    <span className="text-[#0F172A] text-xl font-bold tracking-widest uppercase">
                        FIT CONNECT
                    </span>
                </div>

                {/* Card */}
                <div className="bg-white border border-[#E2E8F0] rounded-md p-8">
                    <div className="mb-6">
                        <h1 className="text-xl font-bold text-[#0F172A]">アカウント作成</h1>
                        <p className="text-sm text-[#475569] mt-1">トレーナーアカウントを作成してください</p>
                    </div>

                    <form onSubmit={handleSignUp} className="space-y-5">
                        <div className="space-y-1.5">
                            <label
                                className="block text-sm font-medium text-[#0F172A]"
                                htmlFor="fullName"
                            >
                                お名前
                            </label>
                            <input
                                id="fullName"
                                type="text"
                                placeholder="山田 太郎"
                                className="w-full bg-white border border-[#E2E8F0] rounded-md px-3 py-2.5 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                                value={fullName}
                                onChange={handleFullNameChange}
                                required
                            />
                        </div>

                        <div className="space-y-1.5">
                            <label
                                className="block text-sm font-medium text-[#0F172A]"
                                htmlFor="email"
                            >
                                メールアドレス
                            </label>
                            <input
                                id="email"
                                type="email"
                                placeholder="you@example.com"
                                className="w-full bg-white border border-[#E2E8F0] rounded-md px-3 py-2.5 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                                value={email}
                                onChange={handleEmailChange}
                                required
                            />
                        </div>

                        <div className="space-y-1.5">
                            <label
                                className="block text-sm font-medium text-[#0F172A]"
                                htmlFor="password"
                            >
                                パスワード
                            </label>
                            <input
                                id="password"
                                type="password"
                                placeholder="パスワードを入力"
                                className="w-full bg-white border border-[#E2E8F0] rounded-md px-3 py-2.5 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                                value={password}
                                onChange={handlePasswordChange}
                                required
                            />
                            <p className="text-xs text-[#94A3B8]">6文字以上で入力してください</p>
                        </div>

                        <div className="space-y-1.5">
                            <label
                                className="block text-sm font-medium text-[#0F172A]"
                                htmlFor="confirmPassword"
                            >
                                パスワード確認
                            </label>
                            <input
                                id="confirmPassword"
                                type="password"
                                placeholder="パスワードを再入力"
                                className="w-full bg-white border border-[#E2E8F0] rounded-md px-3 py-2.5 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                                value={confirmPassword}
                                onChange={handleConfirmPasswordChange}
                                required
                            />
                        </div>

                        <div className="pt-1">
                            <button
                                type="submit"
                                className="w-full h-11 bg-[#14B8A6] hover:bg-[#0D9488] text-white text-sm font-semibold rounded-md px-4 py-2.5 transition-colors cursor-pointer"
                            >
                                新規登録
                            </button>
                        </div>
                    </form>

                    {/* Divider */}
                    <div className="flex items-center gap-3 my-6">
                        <div className="flex-1 h-px bg-[#E2E8F0]" />
                        <span className="text-xs text-[#94A3B8]">または</span>
                        <div className="flex-1 h-px bg-[#E2E8F0]" />
                    </div>

                    {/* Social Auth */}
                    <button
                        type="button"
                        onClick={handleGoogleSignUp}
                        className="w-full flex items-center justify-center gap-2 h-11 bg-white border border-[#E2E8F0] rounded-md text-sm font-medium text-[#0F172A] hover:bg-[#F8FAFC] transition-colors cursor-pointer"
                    >
                        <svg width="18" height="18" viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
                            <path d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615Z" fill="#4285F4"/>
                            <path d="M9 18c2.43 0 4.467-.806 5.956-2.184l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18Z" fill="#34A853"/>
                            <path d="M3.964 10.706A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.706V4.962H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.038l3.007-2.332Z" fill="#FBBC05"/>
                            <path d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.962L3.964 7.294C4.672 5.163 6.656 3.58 9 3.58Z" fill="#EA4335"/>
                        </svg>
                        Googleで登録
                    </button>

                    {/* Login link */}
                    <div className="mt-6 text-center">
                        <span className="text-sm text-[#475569]">すでにアカウントをお持ちですか？</span>
                        <button
                            type="button"
                            onClick={moveLoginPage}
                            className="ml-1.5 text-sm font-medium text-[#14B8A6] hover:text-[#0D9488] transition-colors cursor-pointer"
                        >
                            ログイン
                        </button>
                    </div>
                </div>
            </div>
        </main>
    );
}
