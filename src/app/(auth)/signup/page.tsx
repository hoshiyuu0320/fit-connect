"use client"

import Image from "next/image";
import { useState } from "react"
import { Button } from "@/components/ui/button";
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { createProfile } from '@/lib/supabase/createProfile'


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

            await createProfile(userId, fullName, email)
        } catch (error: any) {
            console.error('Signup error:', error);
            alert(error.message || 'エラーが発生しました');
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

    return (
        <main className="flex flex-col items-center justify-center min-h-screen">
            <div className="w-[960px] h-[906px] pt-[20px]">
                <div className="w-[960px] h-[242px]">
                    <Image
                        src="/signup_background.svg"
                        alt="header"
                        width={928}
                        height={218}
                        priority
                    />
                </div>
                <div className="text-center w-[960px] h-[67px]">
                    <h1 className="text-22px font-bold w-[928px] h-[35px]">Create your account</h1>
                </div>
                <form onSubmit={handleSignUp}>
                    <div className="flex flex-col">
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" >Full name</label>
                            <input
                                type="text"
                                placeholder="Your  full name"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                value={fullName}
                                onChange={handleFullNameChange}
                            />
                        </div>
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" htmlFor="email">Email</label>
                            <input
                                type="email"
                                placeholder="you@example.com"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                id="email"
                                value={email}
                                onChange={handleEmailChange}
                            />
                        </div>
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" htmlFor="password">Password</label>
                            <input
                                type="password"
                                placeholder="Create a password"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                id="password"
                                value={password}
                                onChange={handlePasswordChange}
                            />
                        </div>
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" htmlFor="password">Confirm Password</label>
                            <input
                                type="password"
                                placeholder="Re-enter  your password"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                id="password"
                                value={confirmPassword}
                                onChange={handleConfirmPasswordChange}
                            />
                        </div>
                        <div className="flex items-center w-[960px] h-[72px]">
                            <Button
                                type="submit"
                                variant="ghost"
                                className="bg-[#369EFF] text-white text-[14px] font-bold w-[480px] h-[40px] rounded-[8px]">
                                Sign up
                            </Button>
                        </div>
                        <div className="w-[960px] h-[37px]">
                            <Button
                                type="button"
                                onClick={moveLoginPage}
                                variant="link"
                                className="flex items-start justify-center text-center w-full text-[#3D4D5C] text-[14px] font-regular w-[928px] h-[21px]">
                                Already have an account?
                            </Button>
                        </div>
                    </div>
                </form>
            </div >
        </main >
    );
}