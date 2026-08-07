const crypto = require('crypto');

// A minimal in-memory stand-in for the subset of the supabase-js query builder our
// code actually uses (from/select/insert/update/delete/eq/is/order/single/maybeSingle,
// plus being awaitable directly). Good enough to exercise real route/lib logic against,
// without needing a live Supabase project in unit tests.
class FakeQueryBuilder {
    constructor(store, table) {
        this.store = store;
        this.table = table;
        this.op = null;
        this.payload = null;
        this.filters = [];
        this.orderCol = null;
        this.orderAsc = true;
        this.singleMode = null;
    }

    select() {
        if (!this.op) this.op = 'select';
        return this;
    }

    insert(payload) {
        this.op = 'insert';
        this.payload = payload;
        return this;
    }

    update(payload) {
        this.op = 'update';
        this.payload = payload;
        return this;
    }

    delete() {
        this.op = 'delete';
        return this;
    }

    eq(col, val) {
        this.filters.push((row) => row[col] === val);
        return this;
    }

    is(col, val) {
        this.filters.push((row) => (val === null ? row[col] == null : row[col] === val));
        return this;
    }

    order(col, opts = {}) {
        this.orderCol = col;
        this.orderAsc = opts.ascending !== false;
        return this;
    }

    single() {
        this.singleMode = 'single';
        return this._exec();
    }

    maybeSingle() {
        this.singleMode = 'maybeSingle';
        return this._exec();
    }

    // Makes the builder itself awaitable, matching supabase-js (no .single() call).
    then(onResolve, onReject) {
        return this._exec().then(onResolve, onReject);
    }

    _matchingRows() {
        const rows = this.store[this.table] || (this.store[this.table] = []);
        return rows.filter((row) => this.filters.every((f) => f(row)));
    }

    async _exec() {
        let resultRows;
        const now = new Date().toISOString();

        if (this.op === 'insert') {
            const row = { id: crypto.randomUUID(), created_at: now, updated_at: now, saved_at: now, ...this.payload };
            (this.store[this.table] = this.store[this.table] || []).push(row);
            resultRows = [row];
        } else if (this.op === 'update') {
            resultRows = this._matchingRows();
            resultRows.forEach((row) => Object.assign(row, this.payload, { updated_at: now }));
        } else if (this.op === 'delete') {
            resultRows = this._matchingRows();
            this.store[this.table] = (this.store[this.table] || []).filter((row) => !resultRows.includes(row));
        } else {
            resultRows = this._matchingRows();
            if (this.orderCol) {
                const col = this.orderCol;
                const asc = this.orderAsc;
                resultRows = [...resultRows].sort((a, b) => {
                    if (a[col] === b[col]) return 0;
                    const dir = a[col] > b[col] ? 1 : -1;
                    return asc ? dir : -dir;
                });
            }
        }

        if (this.singleMode === 'single') {
            return resultRows[0]
                ? { data: resultRows[0], error: null }
                : { data: null, error: { message: 'No rows found' } };
        }
        if (this.singleMode === 'maybeSingle') {
            return { data: resultRows[0] || null, error: null };
        }
        return { data: resultRows, error: null };
    }
}

function createFakeSupabaseAdmin() {
    const store = {};

    return {
        from: (table) => new FakeQueryBuilder(store, table),
        auth: {
            admin: {
                createUser: jest.fn()
            }
        },
        _store: store,
        // Test-only helper: seed rows directly, bypassing the query builder.
        _seed(table, rows) {
            (store[table] = store[table] || []).push(...rows);
        },
        // Test-only helper: wipe all tables and mock call history between tests, so
        // tests aren't order-dependent on what earlier tests happened to insert.
        _reset() {
            Object.keys(store).forEach((key) => delete store[key]);
            this.auth.admin.createUser.mockReset();
        }
    };
}

module.exports = { createFakeSupabaseAdmin };
