const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const envPath = path.resolve(__dirname, '../.env.local');
const envConfig = fs.readFileSync(envPath, 'utf8');
const env = {};
envConfig.split('\n').forEach(line => {
    const [key, value] = line.split('=');
    if (key && value) env[key.trim()] = value.trim();
});

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

async function main() {
    console.log('Signing in...');
    const { error: authError } = await supabase.auth.signInWithPassword({
        email: 'testuser3@example.com',
        password: 'password123'
    });
    if (authError) {
        console.error('Auth Error:', authError);
        return;
    }

    console.log('Fetching from weight_records...');
    // First get a client ID
    const { data: clients } = await supabase.from('clients').select('client_id').limit(1);
    const clientId = clients[0]?.client_id;
    console.log('Client ID:', clientId);

    if (!clientId) return;

    const { data, error } = await supabase
        .from('weight_records')
        .select('client_id, recorded_at')
        .in('client_id', [clientId])
        .gte('recorded_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString());

    if (error) {
        console.error('Error:', error);
    } else {
        console.log('Data:', data);
    }
}

main();
