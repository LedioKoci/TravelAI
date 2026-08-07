process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';
// Silences lib/supabaseAuth.js's module-level warning — this file never exercises
// login, but server.js pulls in routes/auth.js (and therefore supabaseAuth.js) too.
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

const USER_A = signAccessToken('user-a');
const USER_B = signAccessToken('user-b');

function authed(req, token = USER_A) {
    return req.set('Authorization', `Bearer ${token}`);
}

const samplePlan = {
    planSummary: {
        destinationCity: 'Paris',
        departureCity: 'London',
        startDate: '2026-09-01',
        endDate: '2026-09-05'
    },
    flights: { status: 'success', data: [] }
};

describe('auth requirement', () => {
    test('GET without a token is rejected with 401', async () => {
        const res = await request(app).get('/api/travels');
        expect(res.status).toBe(401);
    });

    test('POST without a token is rejected with 401', async () => {
        const res = await request(app).post('/api/travels').send({ travelPlan: samplePlan });
        expect(res.status).toBe(401);
    });
});

describe('GET /api/travels', () => {
    test('starts empty for a new user', async () => {
        const res = await authed(request(app).get('/api/travels'), signAccessToken('fresh-user'));
        expect(res.status).toBe(200);
        expect(res.body).toEqual([]);
    });
});

describe('POST /api/travels', () => {
    test('rejects a missing travelPlan', async () => {
        const res = await authed(request(app).post('/api/travels')).send({});
        expect(res.status).toBe(400);
    });

    test('saves a plan and returns the client SavedTravel shape', async () => {
        const res = await authed(request(app).post('/api/travels')).send({ travelPlan: samplePlan });

        expect(res.status).toBe(201);
        expect(res.body).toMatchObject({
            destinationCity: 'Paris',
            departureCity: 'London',
            startDate: '2026-09-01',
            endDate: '2026-09-05',
            travelPlan: samplePlan
        });
        expect(typeof res.body.id).toBe('string');
        expect(typeof res.body.savedAt).toBe('string');
    });

    test('falls back to sentinel values when planSummary fields are missing', async () => {
        const res = await authed(request(app).post('/api/travels')).send({ travelPlan: {} });

        expect(res.status).toBe(201);
        expect(res.body.destinationCity).toBe('Unknown City');
        expect(res.body.departureCity).toBe('');
        expect(res.body.startDate).toBe('flexible');
        expect(res.body.endDate).toBe('flexible');
    });
});

describe('ownership scoping', () => {
    test("a user only ever sees their own saved travels, never another user's", async () => {
        await authed(request(app).post('/api/travels'), USER_A).send({ travelPlan: samplePlan });
        await authed(request(app).post('/api/travels'), USER_B).send({
            travelPlan: { planSummary: { destinationCity: 'Tokyo' } }
        });

        const listA = await authed(request(app).get('/api/travels'), USER_A);
        const listB = await authed(request(app).get('/api/travels'), USER_B);

        expect(listA.body.map((t) => t.destinationCity)).toEqual(['Paris']);
        expect(listB.body.map((t) => t.destinationCity)).toEqual(['Tokyo']);
    });

    test("deleting another user's saved travel returns 404 and leaves it intact", async () => {
        const saveRes = await authed(request(app).post('/api/travels'), USER_A).send({ travelPlan: samplePlan });
        const travelId = saveRes.body.id;

        const deleteAsB = await authed(request(app).delete(`/api/travels/${travelId}`), USER_B);
        expect(deleteAsB.status).toBe(404);

        const listA = await authed(request(app).get('/api/travels'), USER_A);
        expect(listA.body.some((t) => t.id === travelId)).toBe(true);
    });
});

describe('DELETE /api/travels/:id', () => {
    test('returns 404 for an id that was never saved', async () => {
        const res = await authed(request(app).delete('/api/travels/does-not-exist'));
        expect(res.status).toBe(404);
    });

    test('deletes an owned saved travel', async () => {
        const owner = signAccessToken('delete-owner');
        const saveRes = await authed(request(app).post('/api/travels'), owner).send({ travelPlan: samplePlan });
        const travelId = saveRes.body.id;

        const deleteRes = await authed(request(app).delete(`/api/travels/${travelId}`), owner);
        expect(deleteRes.status).toBe(204);

        const listRes = await authed(request(app).get('/api/travels'), owner);
        expect(listRes.body).toEqual([]);
    });
});
