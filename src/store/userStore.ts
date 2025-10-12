import { create } from 'zustand';
import { persist } from 'zustand/middleware';

type UserState = {
    userName: string;
    setUserName: (name: string) => void;
};

export const useUserStore = 
// create<UserState>((set) => ({
//     userName: '',
//     setUserName: (name) => set({ userName: name}),
// }));
create(
    persist<UserState>(
        (set) => ({
            userName: '',
            setUserName: (name) => set({ userName: name}),
        }),
        {
            name: 'user-storage', // localStorage　に保存されるキー名
        }
    )
)

