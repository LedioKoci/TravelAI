process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';

jest.mock('../lib/supabaseAdmin', () => require('./testUtils/fakeSupabaseAdmin').createFakeSupabaseAdmin());
jest.mock('../lib/supabaseAuth', () => ({ verifyPassword: jest.fn() }));

const request = require('supertest');
const supabaseAdmin = require('../lib/supabaseAdmin');
const { verifyPassword } = require('../lib/supabaseAuth');
const { verifyAccessToken, _internal } = require('../lib/tokens');
const app = require('../server');

function mockCreateUser(result) {
    supabaseAdmin.auth.admin.createUser.mockResolvedValueOnce(result);
}

beforeEach(() => {
    supabaseAdmin._reset();
    verifyPassword.mockReset();
});

describe('POST /api/auth/signup', () => {
    test('rejects an invalid email', async () => {
        const res = await request(app).post('/api/auth/signup').send({ email: 'not-an-email', password: 'longenough' });
        expect(res.status).toBe(400);
    });

    test('rejects a password shorter than 8 characters', async () => {
        const res = await request(app).post('/api/auth/signup').send({ email: 'a@b.com', password: 'short' });
        expect(res.status).toBe(400);
    });

    test('creates the user and returns an access/refresh pair on success', async () => {
        mockCreateUser({ data: { user: { id: 'user-1', email: 'a@b.com' } }, error: null });

        const res = await request(app)
            .post('/api/auth/signup')
            .send({ email: 'a@b.com', password: 'longenough1', displayName: 'Ada' });

        expect(res.status).toBe(201);
        expect(res.body.user).toEqual({ id: 'user-1', email: 'a@b.com' });
        expect(verifyAccessToken(res.body.accessToken).sub).toBe('user-1');
        expect(typeof res.body.refreshToken).toBe('string');

        // Refresh token is persisted hashed, not raw.
        const row = supabaseAdmin._store.refresh_tokens.find((r) => r.user_id === 'user-1');
        expect(row.token_hash).toBe(_internal.hashRefreshToken(res.body.refreshToken));
    });

    test('sets display_name on the profile when provided', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-2', display_name: null, home_city: null }]);
        mockCreateUser({ data: { user: { id: 'user-2', email: 'b@b.com' } }, error: null });

        await request(app).post('/api/auth/signup').send({ email: 'b@b.com', password: 'longenough1', displayName: 'Bea' });

        const profile = supabaseAdmin._store.profiles.find((p) => p.id === 'user-2');
        expect(profile.display_name).toBe('Bea');
    });

    test('returns 409 when the email is already registered', async () => {
        mockCreateUser({ data: null, error: { status: 422, message: 'User already registered' } });

        const res = await request(app).post('/api/auth/signup').send({ email: 'dupe@b.com', password: 'longenough1' });
        expect(res.status).toBe(409);
    });
});

describe('POST /api/auth/login', () => {
    test('rejects missing credentials', async () => {
        const res = await request(app).post('/api/auth/login').send({ email: 'a@b.com' });
        expect(res.status).toBe(400);
    });

    test('returns 401 on invalid credentials', async () => {
        verifyPassword.mockResolvedValueOnce(null);

        const res = await request(app).post('/api/auth/login').send({ email: 'a@b.com', password: 'wrongpass1' });
        expect(res.status).toBe(401);
    });

    test('returns an access/refresh pair on valid credentials', async () => {
        verifyPassword.mockResolvedValueOnce({ id: 'user-3', email: 'c@b.com' });

        const res = await request(app).post('/api/auth/login').send({ email: 'c@b.com', password: 'correctpass1' });

        expect(res.status).toBe(200);
        expect(verifyAccessToken(res.body.accessToken).sub).toBe('user-3');
        expect(typeof res.body.refreshToken).toBe('string');
    });
});

describe('POST /api/auth/refresh', () => {
    async function loginAndGetRefreshToken(userId = 'user-4') {
        verifyPassword.mockResolvedValueOnce({ id: userId, email: 'd@b.com' });
        const loginRes = await request(app).post('/api/auth/login').send({ email: 'd@b.com', password: 'correctpass1' });
        return loginRes.body.refreshToken;
    }

    test('rejects a missing refresh token', async () => {
        const res = await request(app).post('/api/auth/refresh').send({});
        expect(res.status).toBe(400);
    });

    test('rejects an unknown refresh token', async () => {
        const res = await request(app).post('/api/auth/refresh').send({ refreshToken: 'bogus' });
        expect(res.status).toBe(401);
    });

    test('rotates a valid refresh token to a new access/refresh pair', async () => {
        const refreshToken = await loginAndGetRefreshToken();

        const res = await request(app).post('/api/auth/refresh').send({ refreshToken });

        expect(res.status).toBe(200);
        expect(res.body.refreshToken).not.toBe(refreshToken);
        expect(verifyAccessToken(res.body.accessToken).sub).toBe('user-4');
    });

    test('rejects reuse of a token that was already rotated away', async () => {
        const refreshToken = await loginAndGetRefreshToken('user-5');
        await request(app).post('/api/auth/refresh').send({ refreshToken });

        const replay = await request(app).post('/api/auth/refresh').send({ refreshToken });
        expect(replay.status).toBe(401);
    });
});

describe('POST /api/auth/logout', () => {
    test('revokes the refresh token so it cannot be used again', async () => {
        verifyPassword.mockResolvedValueOnce({ id: 'user-6', email: 'e@b.com' });
        const loginRes = await request(app).post('/api/auth/login').send({ email: 'e@b.com', password: 'correctpass1' });
        const refreshToken = loginRes.body.refreshToken;

        const logoutRes = await request(app).post('/api/auth/logout').send({ refreshToken });
        expect(logoutRes.status).toBe(204);

        const refreshRes = await request(app).post('/api/auth/refresh').send({ refreshToken });
        expect(refreshRes.status).toBe(401);
    });
});
