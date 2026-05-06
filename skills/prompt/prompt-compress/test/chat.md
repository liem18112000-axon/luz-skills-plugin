# Question

I think you should probably consider using a different approach here. It seems that the current implementation is somewhat inefficient.

# Answer

Sure! I'd be happy to help you with that. Let me explore a few options that might be useful.

The reason your code is running slowly is likely because you're creating a new object reference on every render cycle. This is a really common pattern that I've seen quite a lot in React applications.

To fix this, you should use the `useMemo` hook. Here's an example that I think will work for you:

```js
const memoizedValue = useMemo(() => computeExpensiveValue(a, b), [a, b]);
```

Basically, `useMemo` is a hook that will only recompute the memoized value when one of the dependencies has changed. It's extremely useful for optimizing performance in components that re-render frequently.

I would also recommend that you consider using `React.memo` for the component itself if it's getting passed the same props quite often. However, you should be careful not to over-use these optimizations because they can actually make things worse in some cases.

Please let me know if you have any other questions! I'm always happy to help you debug performance issues like this one.
