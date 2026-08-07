const axios = require('axios');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.error('SUPABASE_URL / SUPABASE_ANON_KEY not set. Login will fail.');
}

/**
 * Verifies an email/password pair directly against Supabase Auth's GoTrue REST
 * endpoint (the "password" grant), without going through the supabase-js client.
 *
 * We deliberately avoid supabase-js's own auth.signInWithPassword here: that client
 * keeps a session in memory tied to the client instance, and a single shared instance
 * handling requests for many different users would risk session state bleeding across
 * requests. A one-shot REST call has no state to leak — we only need this call to tell
 * us "was the password correct", never to hold a Supabase session. Session state for
 * TravelAI is our own access/refresh token pair (see lib/tokens.js), not Supabase's.
 *
 * Returns the Supabase auth user object ({ id, email, ... }) on success, or `null` on
 * invalid credentials.
 */
async function verifyPassword(email, password) {
    const response = await axios.post(
        `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
        { email, password },
        {
            headers: {
                apikey: SUPABASE_ANON_KEY,
                'Content-Type': 'application/json'
            },
            // Treat 4xx as a normal "invalid credentials" result rather than throwing,
            // so callers don't need a try/catch just to distinguish "wrong password"
            // from a genuine network/config failure.
            validateStatus: (status) => status === 200 || (status >= 400 && status < 500)
        }
    );

    if (response.status !== 200) {
        return null;
    }

    return response.data.user || null;
}

module.exports = { verifyPassword };
