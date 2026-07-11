import { supabase } from '@/lib/supabase';

export const CONSENT_VERSION = '2026-07-11';

type SaveUserConsentsParam = {
    userId: string;
    userType: 'trainer' | 'client';
};

/**
 * 利用規約・プライバシーポリシーへの同意を user_consents に記録する。
 * ベストエフォート: 失敗してもサインアップ自体は失敗させない（console.error のみ）。
 */
export const saveUserConsents = async ({ userId, userType }: SaveUserConsentsParam) => {
    const { error } = await supabase
        .from('user_consents')
        .insert([
            {
                user_id: userId,
                user_type: userType,
                document: 'terms',
                version: CONSENT_VERSION,
            },
            {
                user_id: userId,
                user_type: userType,
                document: 'privacy',
                version: CONSENT_VERSION,
            },
        ]);

    if (error) {
        console.error('同意記録の保存エラー：', error);
    }
}
