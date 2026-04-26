"use client"

import { useState } from "react"
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';

export default function LoginPage() {
    const [password, setPassword] = useState("")
    const [email, setEmail] = useState("")
    const router = useRouter();

    const handleLogin = async (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        try {
            const { error: signUpError } = await supabase.auth.signInWithPassword({
                email: email,
                password: password,
            })
            if (signUpError) {
                throw signUpError;
            }
            router.push('/dashboard');
        } catch {
            alert('エラーが発生しました');
        }
    }

    const moveSignUpPage = () => {
        router.push('/signup');
    }

    const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setPassword(e.target.value)
    }

    const handleEmailChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setEmail(e.target.value)
    }

    const handleGoogleLogin = async () => {
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
                    <span className="text-[#0F172A] text-xl font-bold tracking-widest">FIT CONNECT</span>
                </div>

                {/* Card */}
                <div className="bg-white border border-[#E2E8F0] rounded-md p-8">
                    <h1 className="text-[#0F172A] text-xl font-bold mb-2">おかえりなさい</h1>
                    <p className="text-[#475569] text-sm mb-8">アカウントにサインインしてください</p>

                    <form onSubmit={handleLogin} className="space-y-5">
                        {/* Email */}
                        <div className="space-y-1.5">
                            <label
                                htmlFor="email"
                                className="block text-sm font-medium text-[#0F172A]"
                            >
                                メールアドレス
                            </label>
                            <input
                                type="email"
                                id="email"
                                placeholder="example@mail.com"
                                value={email}
                                onChange={handleEmailChange}
                                className="w-full h-10 bg-white border border-[#E2E8F0] rounded-md px-3 py-2 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                            />
                        </div>

                        {/* Password */}
                        <div className="space-y-1.5">
                            <label
                                htmlFor="password"
                                className="block text-sm font-medium text-[#0F172A]"
                            >
                                パスワード
                            </label>
                            <input
                                type="password"
                                id="password"
                                value={password}
                                onChange={handlePasswordChange}
                                className="w-full h-10 bg-white border border-[#E2E8F0] rounded-md px-3 py-2 text-sm text-[#0F172A] placeholder:text-[#94A3B8] focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 transition-colors"
                            />
                        </div>

                        {/* Submit */}
                        <button
                            type="submit"
                            className="w-full h-11 bg-[#14B8A6] hover:bg-[#0D9488] text-white text-sm font-semibold rounded-md transition-colors cursor-pointer"
                        >
                            ログイン
                        </button>
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
                        onClick={handleGoogleLogin}
                        className="w-full flex items-center justify-center gap-2 h-11 bg-white border border-[#E2E8F0] rounded-md text-sm font-medium text-[#0F172A] hover:bg-[#F8FAFC] transition-colors cursor-pointer"
                    >
                        <svg width="18" height="18" viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
                            <path d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615Z" fill="#4285F4"/>
                            <path d="M9 18c2.43 0 4.467-.806 5.956-2.184l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18Z" fill="#34A853"/>
                            <path d="M3.964 10.706A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.706V4.962H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.038l3.007-2.332Z" fill="#FBBC05"/>
                            <path d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.962L3.964 7.294C4.672 5.163 6.656 3.58 9 3.58Z" fill="#EA4335"/>
                        </svg>
                        Googleでログイン
                    </button>

                    {/* Forgot password */}
                    <div className="mt-6 text-center">
                        <button
                            type="button"
                            className="text-sm text-[#14B8A6] hover:text-[#0D9488] transition-colors cursor-pointer"
                        >
                            パスワードをお忘れですか？
                        </button>
                    </div>
                </div>

                {/* Sign up */}
                <div className="mt-6 text-center">
                    <span className="text-sm text-[#475569]">アカウントをお持ちでないですか？</span>
                    <button
                        type="button"
                        onClick={moveSignUpPage}
                        className="ml-1.5 text-sm font-medium text-[#14B8A6] hover:text-[#0D9488] transition-colors cursor-pointer"
                    >
                        新規登録
                    </button>
                </div>
            </div>
        </main>
    );
}
