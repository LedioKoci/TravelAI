process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';

const request = require('supertest');

// Mock the Gemini SDK so no real network call happens and we control the "AI" response.
const generateContentMock = jest.fn();
jest.mock('@google/generative-ai', () => ({
    GoogleGenerativeAI: jest.fn().mockImplementation(() => ({
        getGenerativeModel: jest.fn().mockReturnValue({
            generateContent: generateContentMock
        })
    }))
}));

function mockGeminiText(text) {
    generateContentMock.mockResolvedValueOnce({
        response: {
            candidates: [{ content: { parts: [{ text }] } }]
        }
    });
}

const app = require('../server');

describe('POST /api/generate-plan', () => {
    beforeEach(() => {
        generateContentMock.mockReset();
    });

    test('returns 400 when query is missing from the request body', async () => {
        const res = await request(app).post('/api/generate-plan').send({});

        expect(res.status).toBe(400);
        expect(res.body).toEqual({ error: 'Query is required' });
    });

    test('returns 400 when query is an empty string', async () => {
        const res = await request(app).post('/api/generate-plan').send({ query: '' });

        expect(res.status).toBe(400);
        expect(res.body).toEqual({ error: 'Query is required' });
    });

    test('returns 500 with the raw response when Gemini returns invalid JSON', async () => {
        mockGeminiText('not valid json');

        const res = await request(app)
            .post('/api/generate-plan')
            .send({ query: 'Plan a trip to Paris next month' });

        expect(res.status).toBe(500);
        expect(res.body.error).toBe('Failed to parse AI response');
        expect(res.body.rawResponse).toBe('not valid json');
    });
});
