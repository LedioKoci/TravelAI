const { verifyAccessToken } = require('../lib/tokens');

function extractBearerToken(req) {
    const header = req.headers.authorization || '';
    return header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : null;
}

/**
 * Requires a valid, unexpired access token. Sets req.userId on success.
 *
 * Returns 401 on a missing/expired/invalid token — see
 * docs/supabase-schema-design.md §4.5 for why 401 is the deliberate choice: it lets
 * the client's HTTP layer apply the same "silently refresh, then retry" handling to
 * any endpoint, without confusing an expired session with a genuinely missing resource.
 */
function authenticate(req, res, next) {
    const token = extractBearerToken(req);
    if (!token) {
        return res.status(401).json({ error: 'Authentication required' });
    }

    try {
        req.userId = verifyAccessToken(token).sub;
        next();
    } catch (err) {
        return res.status(401).json({ error: 'Access token expired or invalid' });
    }
}

/**
 * Like authenticate, but never rejects the request — it just sets req.userId when a
 * valid token happens to be present. Used by /api/generate-plan, which works for
 * logged-out guests but needs to know the caller's identity to apply the
 * "Departing from home?" fallback (docs §3.1) when they are logged in.
 */
function optionalAuthenticate(req, res, next) {
    const token = extractBearerToken(req);
    if (token) {
        try {
            req.userId = verifyAccessToken(token).sub;
        } catch (err) {
            // Invalid/expired token on an optional-auth route: proceed unauthenticated
            // rather than failing the request outright.
        }
    }
    next();
}

module.exports = { authenticate, optionalAuthenticate };
