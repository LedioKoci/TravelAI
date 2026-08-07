const express = require('express');
const supabaseAdmin = require('../lib/supabaseAdmin');
const { authenticate } = require('../middleware/authenticate');
const asyncHandler = require('../lib/asyncHandler');

const router = express.Router();
router.use(authenticate);

function toClientShape(row) {
    return {
        displayName: row.display_name || null,
        homeCity: row.home_city || null
    };
}

// GET /api/profile
router.get('/', asyncHandler(async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('display_name, home_city')
        .eq('id', req.userId)
        .single();

    if (error) {
        console.error('Failed to load profile:', error.message);
        return res.status(500).json({ error: 'Failed to load profile' });
    }

    res.json(toClientShape(data));
}));

// PATCH /api/profile — partial update. Body may include displayName and/or homeCity;
// homeCity is what powers the "Departing from home?" search toggle (see
// docs/supabase-schema-design.md §3.1) — pass null/'' to clear it.
router.patch('/', asyncHandler(async (req, res) => {
    const { displayName, homeCity } = req.body || {};
    const updates = {};

    if (displayName !== undefined) {
        updates.display_name = displayName ? String(displayName).trim() : null;
    }
    if (homeCity !== undefined) {
        updates.home_city = homeCity ? String(homeCity).trim() : null;
    }

    if (Object.keys(updates).length === 0) {
        return res.status(400).json({ error: 'Nothing to update' });
    }

    const { data, error } = await supabaseAdmin
        .from('profiles')
        .update(updates)
        .eq('id', req.userId)
        .select('display_name, home_city')
        .single();

    if (error) {
        console.error('Failed to update profile:', error.message);
        return res.status(500).json({ error: 'Failed to update profile' });
    }

    res.json(toClientShape(data));
}));

module.exports = router;
