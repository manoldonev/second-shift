# Add pie chart style to language card

**Is your feature request related to a problem? Please describe.**

As discussed in https://github.com/anuraghazra/github-readme-stats/discussions/945 it would be nice to give users the ability to display their most used languages as a pie chart.

**Describe the solution you'd like**

![pie_Chart](https://user-images.githubusercontent.com/17570430/158536097-c04d1db8-f3b7-4ebc-8794-e8286eaea0a9.png)

## Acceptance criteria

- AC-1: `layout=donut` on `/api/top-langs` renders the top languages as a donut chart, one arc per language sized by its share, beside a legend with each language's name and percent.
- AC-2: Each arc of the donut takes its language's color, the same color the legend dot beside it shows.
- AC-3: The donut card grows with the number of languages, so the legend and the donut stay inside the card.
