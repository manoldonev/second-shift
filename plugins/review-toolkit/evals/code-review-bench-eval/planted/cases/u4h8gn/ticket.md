# Changing color of the "ring"/circle around the rank

**Is your feature request related to a problem? Please describe.**
I'd like to be able to change the color of the circle surrounding the ranking, I couldn't find a way to do it without themes

**Describe the solution you'd like**
I guess make it possible just like when changing the background color and such

**Describe alternatives you've considered**
Themes, but meh

**Additional context**
[![Readme Card](https://github-readme-stats.vercel.app/api/?username=sxvxgee&show_icons=true&locale=en&title_color=FFFFFF&text_color=FFFFFF&icons_color=FFFFFF&bg_color=000000&border_color=0500DD&count_private=true)](https://github.com/Sxvxgee)

[![GitHub Streak](https://streak-stats.demolab.com?user=Sxvxgee&theme=highcontrast&border_radius=5&border=0500DD&ring=0500DD&fire=0500DD&currStreakLabel=DDDDDD)](https://github.com/Sxvxgee)

As you can see I have the "ring" color in the 2nd card customized, I'd like to be able to do that with the first card too

## Acceptance criteria

- AC-1: A `ring_color` query parameter on `/api` sets the stroke of the stats card's rank circle and its rim.
- AC-2: Without `ring_color`, the rank circle takes the theme's `ring_color` when the theme has one, and the card's title color otherwise.
- AC-3: A `ring_color` that is not a valid color falls back as in AC-2, the way the other color options fall back.
