# [Bug] wakatime langs_count  is invalid when layout=compact

**Describe the bug**
wakatime langs_count  is invalid when layout=compact, **it does work when i don't make layout=compact.**

As follows, i make langs_count=6 and layout=compact, but it's invalid.

**Screenshots**
![image](https://user-images.githubusercontent.com/41513919/116766616-fe4be800-aa5d-11eb-804d-bb51376a1d1a.png)

## Acceptance criteria

- AC-1: With `layout=compact`, `langs_count` limits the languages in the progress bar and in the legend, as it does in the default layout.
- AC-2: With `layout=compact` and `langs_count` set, the progress bar is shared among the languages it shows and still fills its full width.
