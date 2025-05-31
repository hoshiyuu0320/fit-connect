"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button";
import { supabase } from '@/lib/supabase';

export default function LoginPage() {
    const [password, setPassword] = useState("")
    const [email, setEmail] = useState("")

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
            alert('登録完了メールを確認してください');
        } catch (error) {
            alert('エラーが発生しました');
        }
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
                        <label className="text-16px font-medium w-[448px] h-[32px]" htmlFor="email">Email</label>
                        <input className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px]" id="email" type="email" value={email} onChange={handleEmailChange} />
                        <div className="p-[12px]"></div>
                        <label className="text-16px font-medium w-[448px] h-[32px]" htmlFor="password">Password</label>
                        <input className="bg-[#F0F2F5] w-[448px] h-[56px] rounded-[8px]" id="password" type="password" value={password} onChange={handlePasswordChange} />
                        <Button className="text-left w-full text-[#3D4D5C] text-[14px] font-regular w-[960px] h-[37px] p-0">Forgot password?</Button>
                        <Button
                            variant="ghost"
                            className="bg-[#369EFF] text-white text-[14px] font-bold w-[480px] h-[40px] rounded-[8px]"
                            type="submit">
                            Log in
                        </Button>
                        <div className="p-[12px]"></div>
                        <div className="flex justify-center">
                            <Button className="text-[#3D4D5C] text-[14px] font-regular">Don't have an account?</Button>
                        </div>
                        <div className="p-[12px]"></div>
                        <Button
                            variant="ghost"
                            className="bg-[#F0F2F5] text-black text-[14px] font-bold w-[480px] h-[40px] rounded-[8px]">
                            Sign up
                        </Button>
                    </div>
                </form>
            </div>
        </main>
    );
}