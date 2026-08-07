process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'test-anon-key';

jest.mock('../lib/supabaseAdmin', () => require('./testUtils/fakeSupabaseAdmin').createFakeSupabaseAdmin());

const request = require('supertest');
const supabaseAdmin = require('../lib/supabaseAdmin');
const { signAccessToken } = require('../lib/tokens');
const app = require('../server');

beforeEach(() => {
    supabaseAdmin._reset();
});

function authed(req, token) {
    return req.set('Authorization', `Bearer ${token}`);
}

function seedProfile(id, overrides = {}) {
    supabaseAdmin._seed('profiles', [{ id, display_name: null, home_city: null, ...overrides }]);
    return signAccessToken(id);
}

describe('auth requirement', () => {
    test('GET without a token is rejected with 401', async () => {
        const res = await request(app).get('/api/profile');
        expect(res.status).toBe(401);
    });

    test('PATCH without a token is rejected with 401', async () => {
        const res = await request(app).patch('/api/profile').send({ homeCity: 'Bergamo' });
        expect(res.status).toBe(401);
    });
});

describe('GET /api/profile', () => {
    test('returns the caller’s own profile', async () => {
        const token = seedProfile('user-1', { display_name: 'Ada', home_city: 'Milan' });

        const res = await authed(request(app).get('/api/profile'), token);
        expect(res.status).toBe(200);
        expect(res.body).toEqual({ displayName: 'Ada', homeCity: 'Milan' });
    });

    test('returns nulls for an unset profile rather than throwing', async () => {
        const token = seedProfile('user-2');

        const res = await authed(request(app).get('/api/profile'), token);
        expect(res.status).toBe(200);
        expect(res.body).toEqual({ displayName: null, homeCity: null });
    });
});

describe('PATCH /api/profile', () => {
    test('rejects an empty update', async () => {
        const token = seedProfile('user-3');
        const res = await authed(request(app).patch('/api/profile'), token).send({});
        expect(res.status).toBe(400);
    });

    test('sets homeCity — the field that powers the "Departing from home?" toggle', async () => {
        const token = seedProfile('user-4');

        const res = await authed(request(app).patch('/api/profile'), token).send({ homeCity: 'Bergamo' });

        expect(res.status).toBe(200);
        expect(res.body.homeCity).toBe('Bergamo');
        expect(supabaseAdmin._store.profiles.find((p) => p.id === 'user-4').home_city).toBe('Bergamo');
    });

    test('clears homeCity when explicitly set to null', async () => {
        const token = seedProfile('user-5', { home_city: 'Bergamo' });

        const res = await authed(request(app).patch('/api/profile'), token).send({ homeCity: null });

        expect(res.status).toBe(200);
        expect(res.body.homeCity).toBeNull();
    });

    test('only touches the caller’s own profile', async () => {
        const tokenA = seedProfile('user-6', { home_city: 'Rome' });
        seedProfile('user-7', { home_city: 'Paris' });

        await authed(request(app).patch('/api/profile'), tokenA).send({ homeCity: 'Florence' });

        expect(supabaseAdmin._store.profiles.find((p) => p.id === 'user-6').home_city).toBe('Florence');
        expect(supabaseAdmin._store.profiles.find((p) => p.id === 'user-7').home_city).toBe('Paris');
    });
});
