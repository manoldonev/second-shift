# Query parameter `show`

I had doubts that my decision to use `&show_total_reviews=true` instead of `&show=[reviews]` inside #1404 was correct. I have looked at the open issues and I assume that in the future such optional data as the number coauthored commits, open and answered discussions etc. may also be added to the statistics card. These changes will lead to an increase in the number of query parameters:

```
&show_total_reviews=true&show_total_answered_discussions=true&show_total_opened_discussions=true&show_total_coauthored_commits=true
```

VS

```
&show=[reviews, answered_discussions, opened_discussions, coauthored_commits]
```
I think given that this change was made recently and while almost no one is using it, we can change it. What do you think, @rickstaa?

## Acceptance criteria

- AC-1: The stats card takes a `show` list. When it holds `reviews`, the card adds the total PR reviews line and grows by one row.
- AC-2: `/api?show=reviews` reads `show` as a comma-separated list and passes it to the card, so the card it sends carries the reviews line. `show_total_reviews` is no longer read.
