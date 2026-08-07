// Express 4 doesn't await async route handlers, so a rejected promise inside one
// (e.g. a Supabase call throwing) would otherwise be an unhandled rejection instead
// of a clean error response. Wrap every async handler with this.
function asyncHandler(fn) {
    return (req, res, next) => {
        Promise.resolve(fn(req, res, next)).catch((err) => {
            console.error(err);
            if (!res.headersSent) {
                res.status(500).json({ error: 'Internal server error' });
            }
        });
    };
}

module.exports = asyncHandler;
