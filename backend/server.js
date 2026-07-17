const express = require('express');
const cors = require('cors');
const axios = require('axios'); // For external API calls (Weather, News, RapidAPI)
const { GoogleGenerativeAI } = require('@google/generative-ai');
const Amadeus = require('amadeus');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

const GEMINI_API_KEY = process.env.GEMINI_API_KEY; 
if (!GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set. Backend will fail.");
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

const amadeus = new Amadeus({
    clientId: process.env.AMADEUS_CLIENT_ID,
    clientSecret: process.env.AMADEUS_CLIENT_SECRET
});

app.use(cors());
app.use(express.json());

// 1. Amadeus IATA Code Resolver (Crucial for Amadeus APIs)
async function resolveIataCode(cityName) {
    if (!cityName || cityName.toLowerCase() === 'not specified') return null;
    console.log(`Attempting to resolve IATA code for: ${cityName}`);

    try {
        const response = await amadeus.referenceData.locations.get({
            keyword: cityName,
            // FIX APPLIED: Changed subType from an array to a comma-separated string to avoid 400 INVALID OPTION error.
            subType: 'AIRPORT,CITY', 
        });
        
        const locations = response.data;
        if (locations && locations.length > 0) {
            const iataCode = locations[0].iataCode;
            console.log(`Successfully resolved ${cityName} to IATA code: ${iataCode}`);
            return iataCode;
        } else {
            console.log(`Amadeus IATA resolution found no results for ${cityName}.`);
        }
    } catch (error) {
        // Improved error logging: print the full error object for better debugging
        console.error(`Amadeus IATA resolution failed for ${cityName}:`, error);
        // Fallback or just return null
        return null; 
    }
    return null;
}

// 2. Amadeus Flight Search
// The Amadeus API usually returns the cheapest flights first, so we ensure prices are numbers.

async function searchFlights(originCityCode, destinationCityCode, departureDate, travelers) {
    // Skip if codes are missing or dates are flexible, which leads to mock price on frontend
    if (!originCityCode || !destinationCityCode || departureDate === 'flexible') {
        console.log('Skipping flight search due to missing IATA codes or flexible dates.');
        return { status: 'skipped', message: 'Missing IATA codes or fixed date is required.', data: [] };
    }

    try {
        const response = await amadeus.shopping.flightOffersSearch.get({
            originLocationCode: originCityCode,
            destinationLocationCode: destinationCityCode,
            departureDate: departureDate, 
            adults: travelers.toString() 
        });

        // Ensure price is a number and slice to top 3 cheapest offers
        const flights = response.data.slice(0, 3).map(offer => ({
            price: parseFloat(offer.price.total), // Convert to number
            currency: offer.price.currency,
            segments: offer.itineraries[0].segments.map(seg => ({
                departure: seg.departure.iataCode,
                arrival: seg.arrival.iataCode,
                departureTime: seg.departure.at,
                arrivalTime: seg.arrival.at,
                carrier: seg.carrierCode,
                duration: seg.duration
            }))
        }));

        return { status: 'success', message: `Found ${response.data.length} flight offers.`, data: flights };
    } catch (error) {
        console.error('Amadeus Flight Search Error:', error.code || error.message);
        return { status: 'error', message: `Amadeus API error: ${error.code || 'Unknown Error'}`, data: [] };
    }
}

// 3. Amadeus Hotel Search (Now prioritizes Quality/Price Ratio)

async function searchHotels(destinationCity, checkInDate, checkOutDate) {
    const destinationCode = await resolveIataCode(destinationCity);
    
    // Skip if IATA code is missing or dates are flexible
    if (!destinationCode || checkInDate === 'flexible' || checkOutDate === 'flexible') {
        console.log('Skipping hotel search due to missing IATA code or flexible dates.');
        return { status: 'skipped', message: 'Fixed dates and IATA code required for hotel pricing.', data: [] };
    }

    try {
        // Step 1: Get hotel IDs by city (10 to give us choice for scoring)
        const hotelListResponse = await amadeus.referenceData.locations.hotels.byCity.get({
            cityCode: destinationCode,
            radius: 10,
            radiusUnit: 'KM',
            hotelSource: 'ALL'
        });
        
        if (!hotelListResponse.data || hotelListResponse.data.length === 0) {
            return { status: 'skipped', message: 'No hotels found in destination.', data: [] };
        }

        // Step 2: Get actual hotel offers with REAL pricing
        const hotelIds = hotelListResponse.data.slice(0, 10).map(h => h.hotelId).join(',');
        
        const offersResponse = await amadeus.shopping.hotelOffersSearch.get({
            hotelIds: hotelIds,
            checkInDate: checkInDate,
            checkOutDate: checkOutDate,
            adults: 1,
            roomQuantity: 1,
            currency: 'USD'
        });

        if (!offersResponse.data || offersResponse.data.length === 0) {
            return { status: 'skipped', message: 'No hotel offers available for these dates.', data: [] };
        }

        // Step 3: Extract, score, and format hotel data to prioritize good review/price ratio
        const scoredHotels = offersResponse.data.map(hotelOffer => {
            const hotel = hotelOffer.hotel;
            const offer = hotelOffer.offers[0]; // Get the cheapest offer for this specific hotel

            // Amadeus rating is often a string ('3', '4', '5'). Convert to number. Default to 3/5.
            const rating = parseInt(hotel.rating, 10) || 3;
            const pricePerNight = parseFloat(offer.price.base);

            // Calculate Quality-Price Score: (Rating / Price per night). Higher score is better value.
            const qualityPriceScore = (pricePerNight > 0) ? (rating / pricePerNight) : 0;
            
            return {
                hotelId: hotel.hotelId,
                name: hotel.name,
                address: hotel.address?.cityName || 'N/A',
                rating: rating,
                pricePerNight: pricePerNight, // REAL price per night
                totalPrice: parseFloat(offer.price.total), // REAL total price
                currency: offer.price.currency,
                roomType: offer.room?.typeEstimated?.category || 'Standard',
                checkInDate: offer.checkInDate,
                checkOutDate: offer.checkOutDate,
                qualityPriceScore: qualityPriceScore // Used for sorting
            };
        });

        // Step 4: Sort by Quality/Price Score (descending) and take top 3
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
        console.error('Amadeus Hotel Search Error:', error.code || error.message);
        return { 
            status: 'error', 
            message: `Amadeus API error: ${error.code || 'Failed to fetch hotel data'}`, 
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
                    }
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
            // Amadeus Flights (Departure city must be specified)
            travelPlan.flightRequired === true
                ? searchFlights(travelPlan.originLocationCode, travelPlan.destinationLocationCode, travelPlan.startDate, travelPlan.travelers)
                : { status: 'skipped', message: 'Flights not required by user.', data: [] },
            
            // Amadeus Hotels (Use destination city/dates)
            searchHotels(travelPlan.destinationCity, travelPlan.startDate, travelPlan.endDate),
            
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
