# Views: custom cache key support

This is probably not related directly to Express itself, but I think it's a nice feature to have and may cover some use cases. I refer specifically to Pug, but it may apply to any view engine.

# Use Case

A Pug user may want to use [filters](https://pugjs.org/language/filters.html) with dynamic content. But Pug compiles filters only once, they can't contain dynamic content. Express and Pug caches prevent to cache templates with a dynamic cache key, they use filename as a cache key instead. Most of the cache implementations support this, but Express and Pug don't, so you are unable to control how to cache templates.

*Some related discussions:*
https://github.com/pugjs/pug/issues/2603
https://github.com/pugjs/pug/issues/1782

# Suggested Solution

We can add the new option `cacheKey` to `render` method. And we can use it in `render` method to identify cached views. This is quite a small fix.

*Pros:*
- It's easy to implement and it won't be a breaking change.

*Cons:*
- It may complicate the API of the `render` method.
- It may require view engines to implement support for it. E.g. Pug has its own cache under the hood. But this should be very easy, just one line of code.

I'm going to submit PR for this one. Let me know your thoughts.

## Acceptance criteria

- AC-1: `app.render` takes a `cacheKey` option. With the view cache on, two renders of one view with different keys look the view up twice.
- AC-2: With the view cache on, two renders of one view with the same key look the view up once: the second render reads the cache.
- AC-3: Without `cacheKey`, the view name stays the cache key. The existing caching tests keep their expectations, moved onto a shared helper.
