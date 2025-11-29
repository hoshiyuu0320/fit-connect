import { supabase } from '@/lib/supabase'

type LineUserParam = {
    lineUserid: string;
    name: string;
    trainerId: string;
}


export const saveLineUser = async ({lineUserid, name, trainerId} : LineUserParam) => {
    const { error } = await supabase
    .from('clients')
    .upsert({
        line_user_id: lineUserid,
        name: name,
        trainer_id: trainerId,
    });

    if (error) {
        console.error('保存に失敗しました', error)
        throw error
    }
}