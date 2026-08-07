const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const supabaseAdmin = require('./supabaseAdmin');

// See docs/supabase-schema-design.md §4 for the full token design writeup.

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
    console.error('JWT_SECRET not set. Access tokens cannot be signed/verified.');
}

const ACCESS_TOKEN_TTL = '15m';
const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

/**
 * Thrown by rotateRefreshToken when the presented refresh token can't be honored.
 * `reason` is one of 'missing' | 'invalid' | 'expired' | 'reused' — routes map all of
 * these to a 401 asking the client to log in again (see docs §4.5 for why the access
 * token's own expiry uses 401 rather than 404; refresh failures follow the same code
 * for consistency, since both mean "the client needs to re-authenticate").
 */
class RefreshTokenError extends Error {
    constructor(reason) {
        super(`Refresh token ${reason}`);
        this.name = 'RefreshTokenError';
        this.reason = reason;
    }
}

function signAccessToken(userId) {
    return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: ACCESS_TOKEN_TTL });
}

/** Verifies signature + expiry. Throws (jsonwebtoken's TokenExpiredError/JsonWebTokenError) on failure. */
function verifyAccessToken(token) {
    return jwt.verify(token, JWT_SECRET);
}

function generateRawRefreshToken() {
    return crypto.randomBytes(32).toString('base64url');
}

function hashRefreshToken(rawToken) {
    return crypto.createHash('sha256').update(rawToken).digest('hex');
}

/** Inserts a new refresh_tokens row and returns its id plus the raw (unhashed) token. */
async function createRefreshTokenRow(userId, userAgent) {
    const rawToken = generateRawRefreshToken();
    const now = Date.now();

    const { data, error } = await supabaseAdmin
        .from('refresh_tokens')
        .insert({
            user_id: userId,
            token_hash: hashRefreshToken(rawToken),
            issued_at: new Date(now).toISOString(),
            expires_at: new Date(now + REFRESH_TOKEN_TTL_MS).toISOString(),
            user_agent: userAgent || null
        })
        .select('id')
        .single();

    if (error) {
        throw new Error(`Failed to persist refresh token: ${error.message}`);
    }

    return { id: data.id, rawToken };
}

/** Mints a brand-new access/refresh pair for a user (login, signup). */
async function issueSession(userId, { userAgent } = {}) {
    const { rawToken } = await createRefreshTokenRow(userId, userAgent);
    return { accessToken: signAccessToken(userId), refreshToken: rawToken };
}

/**
 * Exchanges a still-valid refresh token for a new access/refresh pair, rotating the
 * refresh token in the process: the old row is marked revoked and linked to the new
 * one via `replaced_by`, so it can never be used again.
 *
 * If a refresh token that's already revoked is presented, that means it was replayed
 * after being rotated away — a signal the token was stolen and used by both the
 * legitimate client and an attacker — so every session for that user is revoked,
 * forcing a full re-login everywhere.
 */
async function rotateRefreshToken(rawToken, { userAgent } = {}) {
    if (!rawToken) {
        throw new RefreshTokenError('missing');
    }

    const tokenHash = hashRefreshToken(rawToken);
    const { data: row, error } = await supabaseAdmin
        .from('refresh_tokens')
        .select('id, user_id, expires_at, revoked_at')
        .eq('token_hash', tokenHash)
        .maybeSingle();

    if (error) {
        throw new Error(`Failed to look up refresh token: ${error.message}`);
    }
    if (!row) {
        throw new RefreshTokenError('invalid');
    }
    if (row.revoked_at) {
        await revokeAllForUser(row.user_id);
        throw new RefreshTokenError('reused');
    }
    if (new Date(row.expires_at).getTime() < Date.now()) {
        throw new RefreshTokenError('expired');
    }

    const { id: newRowId, rawToken: newRawToken } = await createRefreshTokenRow(row.user_id, userAgent);

    const { error: revokeError } = await supabaseAdmin
        .from('refresh_tokens')
        .update({ revoked_at: new Date().toISOString(), replaced_by: newRowId })
        .eq('id', row.id);

    if (revokeError) {
        throw new Error(`Failed to revoke rotated-out refresh token: ${revokeError.message}`);
    }

    return {
        userId: row.user_id,
        accessToken: signAccessToken(row.user_id),
        refreshToken: newRawToken
    };
}

/** Revokes a single refresh token (logout on one device). No-ops silently if already gone/revoked. */
async function revokeRefreshToken(rawToken) {
    if (!rawToken) return;

    await supabaseAdmin
        .from('refresh_tokens')
        .update({ revoked_at: new Date().toISOString() })
        .eq('token_hash', hashRefreshToken(rawToken))
        .is('revoked_at', null);
}

/** Revokes every active refresh token for a user (reuse detection, or a future "log out everywhere"). */
async function revokeAllForUser(userId) {
    const { error } = await supabaseAdmin
        .from('refresh_tokens')
        .update({ revoked_at: new Date().toISOString() })
        .eq('user_id', userId)
        .is('revoked_at', null);

    if (error) {
        throw new Error(`Failed to revoke sessions for user: ${error.message}`);
    }
}

module.exports = {
    RefreshTokenError,
    signAccessToken,
    verifyAccessToken,
    issueSession,
    rotateRefreshToken,
    revokeRefreshToken,
    revokeAllForUser,
    // Exposed for unit testing of pure helper logic only.
    _internal: { generateRawRefreshToken, hashRefreshToken, ACCESS_TOKEN_TTL, REFRESH_TOKEN_TTL_MS }
};
