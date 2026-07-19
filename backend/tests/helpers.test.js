process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'test-key';

const { _internal } = require('../server');
const { resolveGuestNationality, IATA_CODE_PATTERN, toDateOnly, formatDate, mapForecastDay } = _internal;

describe('resolveGuestNationality', () => {
    test('maps a known country name to its ISO2 code', () => {
        expect(resolveGuestNationality('Germany')).toBe('DE');
    });

    test('is case-insensitive and trims whitespace', () => {
        expect(resolveGuestNationality('  united kingdom  ')).toBe('GB');
        expect(resolveGuestNationality('FRANCE')).toBe('FR');
    });

    test('handles country name aliases (usa/uk)', () => {
        expect(resolveGuestNationality('USA')).toBe('US');
        expect(resolveGuestNationality('UK')).toBe('GB');
    });

    test('falls back to US for unrecognized country names', () => {
        expect(resolveGuestNationality('Narnia')).toBe('US');
    });

    test('falls back to US when passportCountry is missing', () => {
        expect(resolveGuestNationality(undefined)).toBe('US');
        expect(resolveGuestNationality(null)).toBe('US');
        expect(resolveGuestNationality('')).toBe('US');
    });
});

describe('IATA_CODE_PATTERN', () => {
    test('matches valid 3-letter uppercase IATA codes', () => {
        expect(IATA_CODE_PATTERN.test('JFK')).toBe(true);
        expect(IATA_CODE_PATTERN.test('LHR')).toBe(true);
    });

    test('rejects lowercase codes', () => {
        expect(IATA_CODE_PATTERN.test('jfk')).toBe(false);
    });

    test('rejects city names or codes of the wrong length', () => {
        expect(IATA_CODE_PATTERN.test('New York')).toBe(false);
        expect(IATA_CODE_PATTERN.test('JF')).toBe(false);
        expect(IATA_CODE_PATTERN.test('JFKK')).toBe(false);
    });
});

describe('toDateOnly', () => {
    test('strips the time component from a date', () => {
        const d = toDateOnly(new Date('2026-07-19T15:42:31Z'));
        expect(d.getHours()).toBe(0);
        expect(d.getMinutes()).toBe(0);
        expect(d.getSeconds()).toBe(0);
        expect(d.getMilliseconds()).toBe(0);
    });

    test('does not mutate the input date', () => {
        const original = new Date('2026-07-19T15:42:31Z');
        const originalTime = original.getTime();
        toDateOnly(original);
        expect(original.getTime()).toBe(originalTime);
    });
});

describe('formatDate', () => {
    test('formats a Date object as YYYY-MM-DD', () => {
        const d = new Date('2026-07-19T00:00:00.000Z');
        expect(formatDate(d)).toBe('2026-07-19');
    });
});

describe('mapForecastDay', () => {
    test('extracts the fields the frontend expects from a WeatherAPI forecastday object', () => {
        const rawDay = {
            date: '2026-07-19',
            day: {
                condition: { text: 'Sunny', icon: '//cdn.weatherapi.com/sunny.png' },
                maxtemp_c: 30,
                mintemp_c: 18
            }
        };

        expect(mapForecastDay(rawDay)).toEqual({
            date: '2026-07-19',
            condition: 'Sunny',
            icon: '//cdn.weatherapi.com/sunny.png',
            maxTempC: 30,
            minTempC: 18
        });
    });
});
