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

console.log('Available keys:', Object.keys(env));

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);

async function main() {
    const { data, error } = await supabase.auth.admin.createUser({
        email: 'testuser3@example.com',
        password: 'password123',
        email_confirm: true
    });
    if (error) {
        console.error(error);
        return;
    }
    console.log('Created User ID:', data.user.id);
}

main();
