# req.hostname: check first comma-delimited host

I have a nodejs application using express that is deployed on Openshift that brings a HAProxy LB that adds `X-Forwarded` headers and an Apache HTTP that acts as WAF (web application firewall - mod_security) in front of app. The Apache extends the `X-Forwarded` headers so I end up with:
```
'x-forwarded-host': 'first.example.com:3000, second.example.com:3000'
```
But this doesn't work with `req.hostname` as it currently assumes there's only one proxy.

See also #1646

## Acceptance criteria

- AC-1: With `trust proxy` enabled, `X-Forwarded-Host: example.com, foobar.com` gives `req.hostname` `example.com`.
- AC-2: Optional whitespace around the comma is removed: `X-Forwarded-Host: example.com , foobar.com` gives `example.com`.
- AC-3: The port of the first host is stripped: `X-Forwarded-Host: example.com:8080 , foobar.com:8888` gives `example.com`.
- AC-4: History.md notes the change under the unreleased heading.
