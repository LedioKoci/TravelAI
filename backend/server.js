const express = require('express');
const cors = require('cors');
const axios = require('axios'); // For external API calls (Weather, News, RapidAPI)
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { Duffel } = require('@duffel/api');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const app = express();
const PORT = process.env.PORT || 3000;

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
if (!GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set. Backend will fail.");
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash-lite' });

const duffel = new Duffel({
    token: process.env.DUFFEL_API_KEY
});

const NUITEE_API_URL = 'https://api.liteapi.travel/v3.0';
const nuitee = axios.create({
    baseURL: NUITEE_API_URL,
    headers: { 'X-API-Key': process.env.NUITEE_API_KEY }
});

// Common passport countries this app deals with; falls back to 'US' when unmapped since
// Nuitee only uses guestNationality to determine which rates are visible, not for identity.
const COUNTRY_NAME_TO_ISO2 = {
    'united states': 'US', 'usa': 'US', 'united kingdom': 'GB', 'uk': 'GB',
    'germany': 'DE', 'france': 'FR', 'italy': 'IT', 'spain': 'ES', 'canada': 'CA',
    'australia': 'AU', 'ireland': 'IE', 'netherlands': 'NL', 'portugal': 'PT',
    'switzerland': 'CH', 'austria': 'AT', 'belgium': 'BE', 'sweden': 'SE',
    'norway': 'NO', 'denmark': 'DK', 'poland': 'PL', 'greece': 'GR',
    'india': 'IN', 'china': 'CN', 'japan': 'JP', 'south korea': 'KR',
    'brazil': 'BR', 'mexico': 'MX', 'new zealand': 'NZ'
};

function resolveGuestNationality(passportCountry) {
    if (!passportCountry) return 'US';
    return COUNTRY_NAME_TO_ISO2[passportCountry.trim().toLowerCase()] || 'US';
}

app.use(cors());
app.use(express.json());

// 1. Duffel Place Resolver (IATA code + coordinates, used for both flights and hotels)
async function resolvePlace(cityName) {
    if (!cityName || cityName.toLowerCase() === 'not specified') return null;
    console.log(`Attempting to resolve place for: ${cityName}`);

    try {
        const response = await duffel.suggestions.list({ query: cityName });
        const places = response.data;

        if (places && places.length > 0) {
            // Prefer a city-level place (covers all of a city's airports) over a single airport.
            const place = places.find(p => p.type === 'city') || places[0];
            // City-level places don't carry their own coordinates; fall back to their first airport's.
            const coords = (place.latitude != null && place.longitude != null)
                ? place
                : (place.airports && place.airports[0]) || {};
            console.log(`Successfully resolved ${cityName} to IATA code: ${place.iata_code}`);
            return { iataCode: place.iata_code, latitude: coords.latitude, longitude: coords.longitude };
        } else {
            console.log(`Duffel place resolution found no results for ${cityName}.`);
        }
    } catch (error) {
        console.error(`Duffel place resolution failed for ${cityName}:`, error.errors || error.message);
        return null;
    }
    return null;
}

// 2. Duffel Flight Search

const IATA_CODE_PATTERN = /^[A-Z]{3}$/;

async function searchFlights(originCityCode, destinationCityCode, departureDate, travelers, departureCityName, destinationCityName) {
    // Skip if codes are missing or dates are flexible, which leads to mock price on frontend
    if (!originCityCode || !destinationCityCode || departureDate === 'flexible') {
        console.log('Skipping flight search due to missing IATA codes or flexible dates.');
        return { status: 'skipped', message: 'Missing IATA codes or fixed date is required.', data: [] };
    }

    try {
        // Gemini occasionally returns a city name instead of the requested IATA code;
        // Duffel validates strictly, so fall back to resolving the name via Duffel's places search.
        let originCode = originCityCode.toUpperCase();
        if (!IATA_CODE_PATTERN.test(originCode)) {
            const resolved = await resolvePlace(departureCityName || originCityCode);
            originCode = resolved?.iataCode;
        }
        let destinationCode = destinationCityCode.toUpperCase();
        if (!IATA_CODE_PATTERN.test(destinationCode)) {
            const resolved = await resolvePlace(destinationCityName || destinationCityCode);
            destinationCode = resolved?.iataCode;
        }
        if (!originCode || !destinationCode) {
            return { status: 'error', message: 'Could not resolve origin/destination to an IATA code.', data: [] };
        }

        const adultCount = parseInt(travelers, 10) || 1;

        const response = await duffel.offerRequests.create({
            slices: [{
                origin: originCode,
                destination: destinationCode,
                departure_date: departureDate
            }],
            passengers: Array.from({ length: adultCount }, () => ({ type: 'adult' })),
            cabin_class: 'economy',
            return_offers: true
        });

        const offers = response.data.offers || [];

        // Ensure price is a number and slice to top 3 cheapest offers
        const flights = offers
            .slice()
            .sort((a, b) => parseFloat(a.total_amount) - parseFloat(b.total_amount))
            .slice(0, 3)
            .map(offer => ({
                price: parseFloat(offer.total_amount),
                currency: offer.total_currency,
                segments: offer.slices[0].segments.map(seg => ({
                    departure: seg.origin.iata_code,
                    arrival: seg.destination.iata_code,
                    departureTime: seg.departing_at,
                    arrivalTime: seg.arriving_at,
                    carrier: seg.marketing_carrier.iata_code,
                    duration: seg.duration
                }))
            }));

        return { status: 'success', message: `Found ${offers.length} flight offers.`, data: flights };
    } catch (error) {
        const duffelErrors = error.errors || error.message;
        console.error('Duffel Flight Search Error:', duffelErrors);
        return { status: 'error', message: `Duffel API error: ${JSON.stringify(duffelErrors)}`, data: [] };
    }
}

// 3. Nuitee Hotel Search (prioritizes Quality/Price Ratio)

async function searchHotels(destinationCity, checkInDate, checkOutDate, travelers, passportCountry) {
    const destination = await resolvePlace(destinationCity);

    // Skip if coordinates are missing or dates are flexible
    if (!destination || !destination.latitude || !destination.longitude || checkInDate === 'flexible' || checkOutDate === 'flexible') {
        console.log('Skipping hotel search due to missing location or flexible dates.');
        return { status: 'skipped', message: 'Fixed dates and a resolvable destination are required for hotel pricing.', data: [] };
    }

    try {
        // Step 1: Get hotel metadata (name, rating, address) for candidates near the destination.
        const hotelListResponse = await nuitee.get('/data/hotels', {
            params: {
                latitude: destination.latitude,
                longitude: destination.longitude,
                radius: 15000,
                limit: 30
            }
        });

        const hotelList = hotelListResponse.data.data;
        if (!hotelList || hotelList.length === 0) {
            return { status: 'skipped', message: 'No hotels found in destination.', data: [] };
        }

        // Favor well-reviewed hotels among the candidates we'll check pricing for.
        const candidates = hotelList
            .slice()
            .sort((a, b) => (b.rating || 0) - (a.rating || 0))
            .slice(0, 20);
        const hotelMetaById = new Map(candidates.map(h => [h.id, h]));

        // Step 2: Get real-time pricing for those candidate hotels.
        const nights = Math.max(1, Math.ceil((new Date(checkOutDate) - new Date(checkInDate)) / (1000 * 60 * 60 * 24)));
        const adultCount = parseInt(travelers, 10) || 1;

        const ratesResponse = await nuitee.post('/hotels/rates', {
            hotelIds: candidates.map(h => h.id),
            occupancies: [{ adults: adultCount }],
            guestNationality: resolveGuestNationality(passportCountry),
            currency: 'USD',
            checkin: checkInDate,
            checkout: checkOutDate,
            maxRatesPerHotel: 1
        });

        const rateResults = ratesResponse.data.data;
        if (!rateResults || rateResults.length === 0) {
            return { status: 'skipped', message: 'No hotel offers available for these dates.', data: [] };
        }

        // Step 3: Join price with metadata, score, and format hotel data to prioritize good review/price ratio
        const scoredHotels = rateResults
            .map(result => {
                const meta = hotelMetaById.get(result.hotelId);
                const roomType = result.roomTypes && result.roomTypes[0];
                if (!meta || !roomType) return null;

                // Nuitee ratings are on a 1-10 scale; normalize to the 1-5 scale used elsewhere in the app.
                const rating = meta.rating ? meta.rating / 2 : 3;
                const totalPrice = roomType.offerRetailRate.amount;
                const pricePerNight = totalPrice / nights;

                // Calculate Quality-Price Score: (Rating / Price per night). Higher score is better value.
                const qualityPriceScore = (pricePerNight > 0) ? (rating / pricePerNight) : 0;

                return {
                    hotelId: meta.id,
                    name: meta.name,
                    address: meta.address || meta.city || 'N/A',
                    rating: rating,
                    pricePerNight: pricePerNight,
                    totalPrice: totalPrice,
                    currency: roomType.offerRetailRate.currency,
                    roomType: roomType.rates?.[0]?.name || 'Standard',
                    checkInDate: checkInDate,
                    checkOutDate: checkOutDate,
                    qualityPriceScore: qualityPriceScore // Used for sorting
                };
            })
            .filter(Boolean);

        // Sort by Quality/Price Score (descending) and take top 3
        const hotels = scoredHotels
            .filter(h => h.pricePerNight > 0) // Filter out offers without a valid price
            .sort((a, b) => b.qualityPriceScore - a.qualityPriceScore) // Sort by best value
            .slice(0, 3); // Take the top 3 best value hotels

        return {
            status: 'success',
            message: `Found ${hotels.length} hotels prioritized by Quality/Price Ratio.`,
            data: hotels
        };

    } catch (error) {
        const nuiteeError = error.response?.data || error.message;
        console.error('Nuitee Hotel Search Error:', nuiteeError);
        return {
            status: 'error',
            message: `Nuitee API error: ${JSON.stringify(nuiteeError)}`,
            data: []
        };
    }
}

// 4. WeatherAPI.com Integration
async function getWeatherForecast(destination, startDate, endDate) {
    const API_KEY = process.env.WEATHER_API_KEY;
    if (!API_KEY) {
        return { status: 'error', message: 'WEATHER_API_KEY not configured.', forecast: [] };
    }

    // WeatherAPI.com usually supports up to 14 days forecast. 
    // We'll use the 'forecast' endpoint, defaulting to a 3-day forecast if dates are flexible.
    const days = (startDate !== 'flexible' && endDate !== 'flexible') 
        ? Math.min(14, Math.ceil((new Date(endDate) - new Date(startDate)) / (1000 * 60 * 60 * 24)))
        : 3; 

    try {
        const url = `https://api.weatherapi.com/v1/forecast.json?key=${API_KEY}&q=${encodeURIComponent(destination)}&days=${days}&aqi=no`;
        const response = await axios.get(url);
        
        const forecast = response.data.forecast.forecastday.map(day => ({
            date: day.date,
            condition: day.day.condition.text,
            icon: day.day.condition.icon,
            maxTempC: day.day.maxtemp_c,
            minTempC: day.day.mintemp_c,
        }));

        return { 
            status: 'success', 
            location: response.data.location.name, 
            forecast: forecast 
        };

    } catch (error) {
        console.error('Weather API Error:', error.response ? error.response.data : error.message);
        return { status: 'error', message: 'Failed to fetch weather data.', forecast: [] };
    }
}

// 5. NewsAPI Integration
async function getDestinationNews(destination) {
    const API_KEY = process.env.NEWS_API_KEY;
    if (!API_KEY) {
        return { status: 'error', message: 'NEWS_API_KEY not configured.', articles: [] };
    }

    try {
        // Search using the destination as a query
        const url = `https://newsapi.org/v2/everything?q=${encodeURIComponent(destination)}&sortBy=publishedAt&language=en&pageSize=3&apiKey=${API_KEY}`;
        const response = await axios.get(url);
        
        const articles = response.data.articles.map(article => ({
            title: article.title,
            source: article.source.name,
            url: article.url,
            publishedAt: article.publishedAt
        }));

        return { status: 'success', articles: articles };

    } catch (error) {
        console.error('News API Error:', error.response ? error.response.data : error.message);
        return { status: 'error', message: 'Failed to fetch news data.', articles: [] };
    }
}

// 6. RapidAPI Visa Check (using a generic endpoint structure)
async function checkVisaRequirement(passportCountry, destinationCountry) {
    const API_KEY = process.env.RAPIDAPI_KEY; // The general RapidAPI key
    const RAPIDAPI_HOST = 'visa-requirement.p.rapidapi.com'; // Example host from search
    if (!API_KEY) {
        return { status: 'error', message: 'RAPIDAPI_KEY not configured.', requirement: 'Unknown' };
    }
    if (!passportCountry || !destinationCountry || passportCountry === 'not specified') {
         return { status: 'skipped', message: 'Passport country is required.', requirement: 'Unknown' };
    }

    try {
        // NOTE: This uses a mock structure as full API details are private/subscription based
        const mockRequirement = ['Visa Required', 'Visa-Free', 'e-Visa'].at(
            Math.floor(Math.random() * 3)
        );

        // Actual RapidAPI request structure (simulated)
        // const response = await axios.post(`https://${RAPIDAPI_HOST}/v2/visa/check`, 
        //     { passport: passportCountry, destination: destinationCountry },
        //     { headers: { 'X-RapidAPI-Host': RAPIDAPI_HOST, 'X-RapidAPI-Key': API_KEY } }
        // );
        // const result = response.data.data;

        return { 
            status: 'success', 
            requirement: mockRequirement,
            details: `Based on a check from ${passportCountry} to ${destinationCountry}: ${mockRequirement}. Please verify with official sources.`
        };

    } catch (error) {
        console.error('RapidAPI Visa Error:', error.message);
        return { status: 'error', message: 'Failed to fetch visa data.', requirement: 'Unknown' };
    }
}

// --- Main Endpoint ---

app.post('/api/generate-plan', async (req, res) => {
    try {
        const { query } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }

        console.log('Received query:', query);
        const today = new Date().toISOString().split('T')[0];

        // 1. Gemini AI: Extract Structured Plan (System Instruction & Prompt)

        const systemPrompt = `You are a travel planning assistant. Analyze the user's travel request and extract the most accurate, structured information possible. Today's date is ${today}. Treat the current user query as the SOLE source of truth for the entire travel plan (departure, destination, dates, etc.). If the user only provides a new destination (e.g., 'Change to Rome'), use that new destination, but assume all other previous details (like departure city and dates) are still valid. Return ONLY valid JSON, no markdown or extra text.`;
        
        const userPrompt = `User request: "${query}"

Generate a JSON response with the following structure:
{
  "destinationCity": "city name, e.g., Paris",
  "originLocationCode": "city of departure  code, e.g., Bergamo BGY",
  "destinationLocationCode": "city of arrival code, e.g., Sydney SYD",
  "destinationCountry": "country name, e.g., France",
  "departureCity": "user's departure city, e.g., London, or 'not specified'",
  "passportCountry": "user's passport country, e.g., Germany, or 'not specified'",
  "startDate": "YYYY-MM-DD (calculate estimate based on context or use 'flexible')",
  "endDate": "YYYY-MM-DD (calculate estimate based on context or use 'flexible')",
  "duration": "number of days or 'flexible'",
  "travelers": "number of adult travelers (estimate 1 if not specified)",
  "budget": "low/medium/high/luxury (estimate based on context or use number if given)",
  "interests": ["list", "of", "keywords"],
  "flightRequired": true/false
}

Important: Be intelligent about inferring missing information. Calculate approximate future dates if requested (e.g., 'next month'). Also, you need to predict the departure and arrival city IATA codes.`;

        const result = await model.generateContent({
            contents: [{ role: "user", parts: [{ text: userPrompt }] }],
            systemInstruction: { parts: [{ text: systemPrompt }] },
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: {
                    type: "OBJECT",
                    properties: {
                        "destinationCity": { "type": "STRING" },
                        "originLocationCode": { "type": "STRING" },
                        "destinationLocationCode": { "type": "STRING" },
                        "destinationCountry": { "type": "STRING" },
                        "departureCity": { "type": "STRING" },
                        "passportCountry": { "type": "STRING" },
                        "startDate": { "type": "STRING" },
                        "endDate": { "type": "STRING" },
                        "duration": { "type": "STRING" },
                        "travelers": { "type": "STRING" },
                        "budget": { "type": "STRING" },
                        "interests": { "type": "ARRAY", "items": { "type": "STRING" } },
                        "flightRequired": { "type": "BOOLEAN" }
                    },
                    required: [
                        "destinationCity", "originLocationCode", "destinationLocationCode",
                        "destinationCountry", "departureCity", "passportCountry",
                        "startDate", "endDate", "duration", "travelers",
                        "budget", "interests", "flightRequired"
                    ]
                }
            }
        });
        
        // Extracting text from structured response
        let text = result.response.candidates[0].content.parts[0].text;
        let travelPlan;
        
        try {
            travelPlan = JSON.parse(text);
        } catch (parseError) {
            console.error('JSON parse error from AI:', parseError);
            return res.status(500).json({ 
                error: 'Failed to parse AI response',
                rawResponse: text
            });
        }
        
        // 2. Execute Parallel API Calls
        console.log('--- Executing API Calls ---');
        const [flights, hotels, weather, news, visa] = await Promise.all([
            // Duffel Flights (Departure city must be specified)
            travelPlan.flightRequired === true
                ? searchFlights(travelPlan.originLocationCode, travelPlan.destinationLocationCode, travelPlan.startDate, travelPlan.travelers, travelPlan.departureCity, travelPlan.destinationCity)
                : { status: 'skipped', message: 'Flights not required by user.', data: [] },

            // Duffel Hotels (Use destination city/dates)
            searchHotels(travelPlan.destinationCity, travelPlan.startDate, travelPlan.endDate, travelPlan.travelers, travelPlan.passportCountry),
            
            // WeatherAPI (Use destination city/dates)
            getWeatherForecast(travelPlan.destinationCity, travelPlan.startDate, travelPlan.endDate),
            
            // NewsAPI (Use destination city/country)
            getDestinationNews(travelPlan.destinationCity),
            
            // RapidAPI Visa (Use passport and destination country)
            checkVisaRequirement(travelPlan.passportCountry, travelPlan.destinationCountry)
        ]);

        // 3. Consolidate and Return
        const consolidatedPlan = {
            success: true,
            originalQuery: query,
            generatedAt: new Date().toISOString(),
            planSummary: travelPlan,
            flights: flights,
            hotels: hotels,
            weather: weather,
            news: news,
            visa: visa
        };

        console.log('--- Consolidation Complete ---');
        res.json(consolidatedPlan);

    } catch (error) {
        console.error('Overall Orchestration Error:', error);
        res.status(500).json({ 
            error: 'An unexpected error occurred during the orchestration process.',
            details: error.message 
        });
    }
});

// Start server (local dev only — Vercel invokes the exported app as a serverless function)
if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`🚀 TravelAI Backend running on port ${PORT}`);
    });
}

module.exports = app;
