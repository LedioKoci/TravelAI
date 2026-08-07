process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret';
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'test-anon-key';

jest.mock('../lib/supabaseAdmin', () => require('./testUtils/fakeSupabaseAdmin').createFakeSupabaseAdmin());

const supabaseAdmin = require('../lib/supabaseAdmin');
const { _internal } = require('../server');
const { applyDepartingFromHomeFallback } = _internal;

beforeEach(() => {
    supabaseAdmin._reset();
});

// See docs/supabase-schema-design.md §3.1: home_city must never reach the Gemini
// prompt, and must never override text the user actually typed. These tests exercise
// the deterministic post-processing fallback that replaces that approach.
describe('applyDepartingFromHomeFallback', () => {
    test('leaves an explicit departure city untouched, even with a home city on file', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-1', home_city: 'Bergamo' }]);
        const travelPlan = { departureCity: 'London' };

        await applyDepartingFromHomeFallback(travelPlan, 'user-1');

        expect(travelPlan.departureCity).toBe('London');
    });

    test('fills in the home city when Gemini left the departure city unspecified', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-2', home_city: 'Bergamo' }]);
        const travelPlan = { departureCity: 'not specified' };

        await applyDepartingFromHomeFallback(travelPlan, 'user-2');

        expect(travelPlan.departureCity).toBe('Bergamo');
    });

    test('is case-insensitive when detecting the "not specified" sentinel', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-3', home_city: 'Bergamo' }]);
        const travelPlan = { departureCity: 'Not Specified' };

        await applyDepartingFromHomeFallback(travelPlan, 'user-3');

        expect(travelPlan.departureCity).toBe('Bergamo');
    });

    test('does nothing for a logged-out caller (no userId)', async () => {
        const travelPlan = { departureCity: 'not specified' };

        await applyDepartingFromHomeFallback(travelPlan, undefined);

        expect(travelPlan.departureCity).toBe('not specified');
    });

    test('does nothing when the signed-in user has no home city on file', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-4', home_city: null }]);
        const travelPlan = { departureCity: 'not specified' };

        await applyDepartingFromHomeFallback(travelPlan, 'user-4');

        expect(travelPlan.departureCity).toBe('not specified');
    });

    test('treats a missing departureCity field the same as "not specified"', async () => {
        supabaseAdmin._seed('profiles', [{ id: 'user-5', home_city: 'Bergamo' }]);
        const travelPlan = {};

        await applyDepartingFromHomeFallback(travelPlan, 'user-5');

        expect(travelPlan.departureCity).toBe('Bergamo');
    });
});
