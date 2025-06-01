"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button";
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
            alert('ログインに成功しました');
        } catch (error) {
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

    return (
        <main className="flex flex-col items-center justify-center min-h-screen">
            <div className="w-[960px] h-[713px]">
                <h1 className="text-center text-22px font-bold mb-12 w-[960px] h-[60px]">Welcome back!</h1>
                <form onSubmit={handleLogin}>
                    <div className="flex flex-col">
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" >Email</label>
                            <input
                                type="email"
                                placeholder="example@mail.com"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                id="email" value={email}
                                onChange={handleEmailChange}
                            />
                        </div>
                        <div className="flex flex-col w-[448px] h-[112px]">
                            <label className="flex items-center text-16px font-medium w-[448px] h-[32px]" htmlFor="password">Password</label>
                            <input
                                type="password"
                                className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                                id="password"
                                value={password}
                                onChange={handlePasswordChange}
                            />
                        </div>
                        <div className="w-[960px] h-[37px]">
                            <Button
                                variant="link"
                                className="flex items-start justify-start text-left text-[#3D4D5C] text-[14px] font-regular w-[960px] h-[37px] p-0">
                                Forgot password?
                            </Button>
                        </div>
                        <div className="flex items-center w-[960px] h-[72px]">
                            <Button
                                variant="ghost"
                                className="bg-[#369EFF] text-white text-[14px] font-bold w-[480px] h-[40px] rounded-[8px]"
                                type="submit">
                                Log in
                            </Button>
                        </div>
                        <div className="flex items-start justify-center text-center w-[960px] h-[37px]">
                            <p className="text-[#3D4D5C] text-[14px] font-regular pt-[4px]">
                                Don't have an account?
                            </p>
                        </div>
                        <div className="flex items-center w-[960px] h-[72px]">
                            <Button
                                type="button"
                                onClick={moveSignUpPage}
                                variant="ghost"
                                className="bg-[#F0F2F5] text-black text-[14px] font-bold w-[480px] h-[40px] rounded-[8px]">
                                Sign up
                            </Button>
                        </div>
                    </div>
                </form>
            </div>
        </main>
    );
}