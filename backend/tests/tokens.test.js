process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';

jest.mock('../lib/supabaseAdmin', () => require('./testUtils/fakeSupabaseAdmin').createFakeSupabaseAdmin());

const supabaseAdmin = require('../lib/supabaseAdmin');
const {
    RefreshTokenError,
    signAccessToken,
    verifyAccessToken,
    issueSession,
    rotateRefreshToken,
    revokeRefreshToken,
    revokeAllForUser,
    _internal
} = require('../lib/tokens');

const USER_ID = 'user-123';

beforeEach(() => {
    supabaseAdmin._reset();
});

describe('access tokens', () => {
    test('signAccessToken produces a token verifyAccessToken can read back', () => {
        const token = signAccessToken(USER_ID);
        expect(verifyAccessToken(token).sub).toBe(USER_ID);
    });

    test('verifyAccessToken throws on a tampered token', () => {
        const token = signAccessToken(USER_ID);
        expect(() => verifyAccessToken(`${token}tampered`)).toThrow();
    });

    test('access tokens are issued with a 15-minute expiry', () => {
        expect(_internal.ACCESS_TOKEN_TTL).toBe('15m');
    });
});

describe('hashRefreshToken', () => {
    test('never stores the raw token — only its hash is persisted', async () => {
        const { refreshToken } = await issueSession(USER_ID);
        const rows = supabaseAdmin._store.refresh_tokens;

        expect(rows).toHaveLength(1);
        expect(rows[0].token_hash).toBe(_internal.hashRefreshToken(refreshToken));
        expect(JSON.stringify(rows[0])).not.toContain(refreshToken);
    });

    test('hashing is deterministic and collision-free for different inputs', () => {
        const a = _internal.generateRawRefreshToken();
        const b = _internal.generateRawRefreshToken();
        expect(_internal.hashRefreshToken(a)).toBe(_internal.hashRefreshToken(a));
        expect(_internal.hashRefreshToken(a)).not.toBe(_internal.hashRefreshToken(b));
    });
});

describe('issueSession', () => {
    test('returns a working access token and a persisted, unrevoked refresh token', async () => {
        const { accessToken, refreshToken } = await issueSession(USER_ID);

        expect(verifyAccessToken(accessToken).sub).toBe(USER_ID);

        const row = supabaseAdmin._store.refresh_tokens.find(
            (r) => r.token_hash === _internal.hashRefreshToken(refreshToken)
        );
        expect(row).toBeDefined();
        expect(row.user_id).toBe(USER_ID);
        expect(row.revoked_at).toBeUndefined();
    });
});

describe('rotateRefreshToken', () => {
    test('rejects a missing token', async () => {
        await expect(rotateRefreshToken(undefined)).rejects.toMatchObject({ reason: 'missing' });
        await expect(rotateRefreshToken('')).rejects.toBeInstanceOf(RefreshTokenError);
    });

    test('rejects a refresh token that was never issued', async () => {
        await expect(rotateRefreshToken('not-a-real-token')).rejects.toMatchObject({ reason: 'invalid' });
    });

    test('rejects an expired refresh token', async () => {
        const { refreshToken } = await issueSession(USER_ID);
        const row = supabaseAdmin._store.refresh_tokens.find(
            (r) => r.token_hash === _internal.hashRefreshToken(refreshToken)
        );
        row.expires_at = new Date(Date.now() - 1000).toISOString();

        await expect(rotateRefreshToken(refreshToken)).rejects.toMatchObject({ reason: 'expired' });
    });

    test('on success, issues a new pair and revokes the old refresh token, linking it via replaced_by', async () => {
        const { refreshToken: firstToken } = await issueSession(USER_ID);
        const rotated = await rotateRefreshToken(firstToken);

        expect(rotated.userId).toBe(USER_ID);
        expect(rotated.refreshToken).not.toBe(firstToken);
        expect(verifyAccessToken(rotated.accessToken).sub).toBe(USER_ID);

        const oldRow = supabaseAdmin._store.refresh_tokens.find(
            (r) => r.token_hash === _internal.hashRefreshToken(firstToken)
        );
        const newRow = supabaseAdmin._store.refresh_tokens.find(
            (r) => r.token_hash === _internal.hashRefreshToken(rotated.refreshToken)
        );

        expect(oldRow.revoked_at).toBeDefined();
        expect(oldRow.replaced_by).toBe(newRow.id);
        expect(newRow.revoked_at).toBeUndefined();
    });

    test('reuse of an already-rotated token is rejected and revokes every session for that user', async () => {
        const { refreshToken: sessionA } = await issueSession(USER_ID);
        const { refreshToken: sessionB } = await issueSession(USER_ID);

        const { refreshToken: rotatedFromA } = await rotateRefreshToken(sessionA);

        // Replaying the now-dead sessionA token looks like theft: reject it, and burn
        // every other active session for the user too (sessionB, and the token that
        // legitimately replaced sessionA).
        await expect(rotateRefreshToken(sessionA)).rejects.toMatchObject({ reason: 'reused' });
        await expect(rotateRefreshToken(sessionB)).rejects.toMatchObject({ reason: 'reused' });
        await expect(rotateRefreshToken(rotatedFromA)).rejects.toMatchObject({ reason: 'reused' });
    });
});

describe('revokeRefreshToken', () => {
    test('a revoked token can no longer be rotated', async () => {
        const { refreshToken } = await issueSession(USER_ID);
        await revokeRefreshToken(refreshToken);

        await expect(rotateRefreshToken(refreshToken)).rejects.toMatchObject({ reason: 'reused' });
    });

    test('revoking an unknown token is a silent no-op', async () => {
        await expect(revokeRefreshToken('never-issued')).resolves.toBeUndefined();
    });
});

describe('revokeAllForUser', () => {
    test('revokes every active session for a user without touching other users', async () => {
        const { refreshToken: mineA } = await issueSession(USER_ID);
        const { refreshToken: mineB } = await issueSession(USER_ID);
        const { refreshToken: someoneElses } = await issueSession('another-user');

        await revokeAllForUser(USER_ID);

        await expect(rotateRefreshToken(mineA)).rejects.toMatchObject({ reason: 'reused' });
        await expect(rotateRefreshToken(mineB)).rejects.toMatchObject({ reason: 'reused' });

        // Untouched: rotating still succeeds (proves it wasn't swept up too).
        await expect(rotateRefreshToken(someoneElses)).resolves.toMatchObject({ userId: 'another-user' });
    });
});
