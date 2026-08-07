const express = require('express');
const supabaseAdmin = require('../lib/supabaseAdmin');
const { authenticate } = require('../middleware/authenticate');
const asyncHandler = require('../lib/asyncHandler');

const router = express.Router();

// Every route here requires a logged-in user — see docs/supabase-schema-design.md §8
// ("Login required to save"): there's no anonymous/local-only save path.
router.use(authenticate);

// Maps a saved_travels DB row to the exact JSON shape the Flutter client's
// SavedTravel.fromJson already expects, so the client model didn't need to change.
function toClientShape(row) {
    return {
        id: row.id,
        destinationCity: row.destination_city,
        departureCity: row.departure_city || '',
        startDate: row.start_date || 'flexible',
        endDate: row.end_date || 'flexible',
        savedAt: row.saved_at,
        travelPlan: row.travel_plan
    };
}

// The DB's start_date/end_date are real `date` columns; 'flexible' isn't a valid date,
// so it's stored as NULL and translated back to 'flexible' by toClientShape above.
function toDbDate(value) {
    return (!value || value === 'flexible') ? null : value;
}

// GET /api/travels — the caller's saved travels, most recent first (matches the
// existing client-side sort in travel_storage_service.dart).
router.get('/', asyncHandler(async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('saved_travels')
        .select('*')
        .eq('user_id', req.userId)
        .order('saved_at', { ascending: false });

    if (error) {
        console.error('Failed to list saved travels:', error.message);
        return res.status(500).json({ error: 'Failed to load saved travels' });
    }

    res.json(data.map(toClientShape));
}));

// POST /api/travels — save a generated plan. Body: { travelPlan }, the same full
// consolidated-plan object /api/generate-plan returns.
router.post('/', asyncHandler(async (req, res) => {
    const { travelPlan } = req.body || {};
    if (!travelPlan || typeof travelPlan !== 'object') {
        return res.status(400).json({ error: 'travelPlan is required' });
    }

    const planSummary = travelPlan.planSummary || {};

    const { data, error } = await supabaseAdmin
        .from('saved_travels')
        .insert({
            user_id: req.userId,
            destination_city: planSummary.destinationCity || 'Unknown City',
            departure_city: planSummary.departureCity || null,
            start_date: toDbDate(planSummary.startDate),
            end_date: toDbDate(planSummary.endDate),
            travel_plan: travelPlan
        })
        .select('*')
        .single();

    if (error) {
        console.error('Failed to save travel:', error.message);
        return res.status(500).json({ error: 'Failed to save travel' });
    }

    res.status(201).json(toClientShape(data));
}));

// DELETE /api/travels/:id — scoped to the caller's own rows. A saved travel that
// exists but belongs to someone else is indistinguishable from one that doesn't
// exist at all (404 either way), so ownership is never leaked.
router.delete('/:id', asyncHandler(async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('saved_travels')
        .delete()
        .eq('id', req.params.id)
        .eq('user_id', req.userId)
        .select('id')
        .maybeSingle();

    if (error) {
        console.error('Failed to delete saved travel:', error.message);
        return res.status(500).json({ error: 'Failed to delete saved travel' });
    }
    if (!data) {
        return res.status(404).json({ error: 'Saved travel not found' });
    }

    res.status(204).send();
}));

module.exports = router;
