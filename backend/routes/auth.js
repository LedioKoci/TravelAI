const express = require('express');
const supabaseAdmin = require('../lib/supabaseAdmin');
const { verifyPassword } = require('../lib/supabaseAuth');
const { issueSession, rotateRefreshToken, revokeRefreshToken, RefreshTokenError } = require('../lib/tokens');
const asyncHandler = require('../lib/asyncHandler');

const router = express.Router();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD_LENGTH = 8;

function isValidEmail(email) {
    return typeof email === 'string' && EMAIL_PATTERN.test(email.trim());
}

function isValidPassword(password) {
    return typeof password === 'string' && password.length >= MIN_PASSWORD_LENGTH;
}

// POST /api/auth/signup — creates the Supabase Auth user, then immediately issues our
// own access/refresh pair (auto-login after signup) so the client doesn't need a
// separate login round trip. Skips email confirmation (email_confirm: true) since
// there's no confirmation-email flow built yet — see README for the caveat.
router.post('/signup', asyncHandler(async (req, res) => {
    const { email, password, displayName } = req.body || {};

    if (!isValidEmail(email)) {
        return res.status(400).json({ error: 'A valid email is required' });
    }
    if (!isValidPassword(password)) {
        return res.status(400).json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters` });
    }

    const { data, error } = await supabaseAdmin.auth.admin.createUser({
        email: email.trim(),
        password,
        email_confirm: true
    });

    if (error) {
        const alreadyExists = error.status === 422 || /already.*registered/i.test(error.message || '');
        return res
            .status(alreadyExists ? 409 : 500)
            .json({ error: alreadyExists ? 'An account with this email already exists' : 'Failed to create account' });
    }

    const user = data.user;

    if (displayName) {
        const { error: profileError } = await supabaseAdmin
            .from('profiles')
            .update({ display_name: String(displayName).trim() })
            .eq('id', user.id);
        if (profileError) {
            console.error('Failed to set display_name after signup:', profileError.message);
        }
    }

    const { accessToken, refreshToken } = await issueSession(user.id, { userAgent: req.headers['user-agent'] });

    res.status(201).json({ accessToken, refreshToken, user: { id: user.id, email: user.email } });
}));

// POST /api/auth/login
router.post('/login', asyncHandler(async (req, res) => {
    const { email, password } = req.body || {};

    if (!isValidEmail(email) || typeof password !== 'string' || !password) {
        return res.status(400).json({ error: 'Email and password are required' });
    }

    const user = await verifyPassword(email.trim(), password);
    if (!user) {
        return res.status(401).json({ error: 'Invalid email or password' });
    }

    const { accessToken, refreshToken } = await issueSession(user.id, { userAgent: req.headers['user-agent'] });

    res.json({ accessToken, refreshToken, user: { id: user.id, email: user.email } });
}));

// POST /api/auth/refresh — exchanges a still-valid refresh token for a new
// access/refresh pair, rotating the refresh token (see docs §4.4 for reuse detection).
router.post('/refresh', asyncHandler(async (req, res) => {
    const { refreshToken } = req.body || {};

    if (!refreshToken) {
        return res.status(400).json({ error: 'refreshToken is required' });
    }

    try {
        const rotated = await rotateRefreshToken(refreshToken, { userAgent: req.headers['user-agent'] });
        res.json({ accessToken: rotated.accessToken, refreshToken: rotated.refreshToken });
    } catch (err) {
        if (err instanceof RefreshTokenError) {
            return res.status(401).json({ error: 'Refresh token invalid or expired, please log in again' });
        }
        throw err;
    }
}));

// POST /api/auth/logout — revokes the refresh token so it can't be replayed. The
// (already short-lived) access token is left to simply expire client-side.
router.post('/logout', asyncHandler(async (req, res) => {
    const { refreshToken } = req.body || {};
    await revokeRefreshToken(refreshToken);
    res.status(204).send();
}));

module.exports = router;
