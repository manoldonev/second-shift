# Use custom text as username

**Is your feature request related to a problem? Please describe.**
Right now full name is used in the stats header, but maybe the user wants to use his/her GitHub handler or a nickname

now:
![image](https://user-images.githubusercontent.com/13673443/88653665-a813d800-d0cc-11ea-97c8-3d940e27e0de.png)

wanted:
![image](https://user-images.githubusercontent.com/13673443/88653589-93cfdb00-d0cc-11ea-918f-597d7afaf01d.png)


**Describe the solution you'd like**
set custom user name as a customization option, maybe `custom_username=JJ`

**Describe alternatives you've considered**
I removed the title using `hide_title` and write it myself but it doesn't appear inside the card 

![image](https://user-images.githubusercontent.com/13673443/88653365-3e93c980-d0cc-11ea-91a8-dc658f228aae.png)

**Additional context**
Maybe allowing to customize the whole title will be a better solution

## Acceptance criteria

- AC-1: `/api?username=<user>&custom_title=<text>` serves a stats card whose title is `<text>`.
- AC-2: `/api/top-langs?username=<user>&custom_title=<text>` serves a top languages card whose title is `<text>`.
- AC-3: `/api/wakatime?username=<user>&custom_title=<text>` serves a WakaTime card whose title is `<text>`.
- AC-4: The readme lists `custom_title` under the options of each of the three cards.
