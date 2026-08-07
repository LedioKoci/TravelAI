const { createClient } = require('@supabase/supabase-js');
// supabase-js always spins up a RealtimeClient in its constructor, even though this
// backend never subscribes to realtime channels. On Node <22 (no global WebSocket)
// that constructor throws unless an explicit transport is supplied. `ws` satisfies it.
const WebSocket = require('ws');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set. Auth and saved-travels sync will fail.');
}

// Privileged client used server-side only: bypasses RLS (service-role key), so every
// query built on top of this must scope itself to the caller's user_id in application
// code. Never send this key to the Flutter client. Also used for admin.createUser at
// signup, since that requires service-role privileges.
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    },
    realtime: {
        transport: WebSocket
    }
});

module.exports = supabaseAdmin;
