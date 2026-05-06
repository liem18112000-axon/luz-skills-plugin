# Why is my PostgreSQL query slow?

Great question! There are actually several reasons your query might be running slowly, and I'd be happy to walk you through the most common ones.

The first thing you should probably look at is the query plan. You can get it by prepending `EXPLAIN ANALYZE` to your query, like this:

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE created_at > '2026-01-01';
```

This will show you exactly what PostgreSQL is doing under the hood. The output is somewhat dense at first, but once you get used to it, it becomes really useful.

## Common causes

There are basically four common causes for slow queries that I see all the time:

1. **Missing indexes.** If you're filtering on a column that doesn't have an index, PostgreSQL has to scan every single row in the table. For a table with 10 million rows, this is going to be extremely slow. The fix is to add an index on the column you're filtering on, like `CREATE INDEX idx_users_created_at ON users (created_at);`.

2. **Sequential scans on large tables.** Even when you have an index, PostgreSQL might decide that a sequential scan is faster than using the index. This usually happens when the planner thinks more than about 5% of the rows will match the filter. You can sometimes work around this by running `ANALYZE` to update statistics.

3. **Inefficient joins.** If you're joining several tables together and the join order isn't optimal, the query can be much slower than it needs to be. Look at the `Hash Join` or `Nested Loop` nodes in the EXPLAIN output to spot these.

4. **Too much data being returned.** Sometimes the query itself is fine, but it's pulling back 500000 rows when you only need 100. Make sure you're using `LIMIT` and only selecting the columns you actually need.

## What to do next

I would recommend that you start by running `EXPLAIN ANALYZE` on the slow query and looking at the actual times reported for each step. The step that takes the most time is usually where the bottleneck is. Feel free to share the output with me and I can help you figure out what to optimize next.

Hope this helps! Let me know if you have any other questions about query optimization.
