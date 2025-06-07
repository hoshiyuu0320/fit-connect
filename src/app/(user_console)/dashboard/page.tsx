"use client"

import Image from "next/image";
import { useState } from "react"
import { Button } from "@/components/ui/button";
import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';

export default function DashboardPage() {
    return (
        <main>
            <h1>Welcome to the Dashboard</h1>
        </main>
    );
}