# 4.19.0 breaks passing new URL() into res.redirect(...)

Understandably, res.redirect(...) should take a string.  But for years we have been successfully passing a new URL().  We can certainly fix this on our side, but wanted to give a heads-up that this change might cause others to run into the same thing.

Error ultimately is thrown here:

reponse.js:915
  var lowerLoc = loc.toLowerCase();

## Acceptance criteria

- AC-1: `res.location(new URL('http://google.com/'))` sets the `Location` header to `http://google.com/` again, so `res.redirect` with a URL works as it did before 4.19.0.
- AC-2: History.md notes the change under the unreleased heading.
