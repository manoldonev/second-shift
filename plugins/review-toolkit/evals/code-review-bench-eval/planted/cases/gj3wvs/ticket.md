# Support Extracting Hostnames From Multiple Certificates

### Description

As a corporate developer, I load in multiple certificates when using Vite, and would like automatic URL hostname detection to work the same as it does for a single certificate.

Node explicitly allows [multiple certificates and keys to be used](https://nodejs.org/api/tls.html#tlscreatesecurecontextoptions), and this seems like an arbitrary, undocumented, Vite limitation.

### Suggested solution

The [resolveServerUrls](https://github.com/vitejs/vite/blob/e899bc7c73a27cdf327875e5d696c50d396a7fc2/packages/vite/src/node/utils.ts#L1049) function handles a single certificate.  The logic could easily be expanded to handle multiple certificates.

> httpsOptions?.cert && !Array.isArray(httpsOptions.cert)

### Alternative

Support more than one "host" in the `server` config section.

Adding custom host URLs involves writing a plugin with the following:

```ts
export function MyPlugin(): VitePlugin {
  return {
    name: "MultipleUrlPlugin",
    async configureServer(this: MinimalPluginContextWithoutEnvironment, server: ViteDevServer): Promise<void> {
      httpsServer.on('listening', () => {
        server.resolvedUrls = customResolveServerUrls(...)
      })
    }
  }
}
```

### Additional context

Node v22 has some problems with multiple certificates, and can use PFX files as well as cert/key pairs.  Bugs/Feature requests relating to those are outside the scope of this.

## Acceptance criteria

- AC-1: `extractHostnamesFromCerts`, given a list that holds a certificate for `localhost`, `foo.localhost` and `*.vite.localhost` once or twice, returns `localhost`, `foo.localhost` and `vite.vite.localhost`, each once.
- AC-2: `resolveServerUrls`, given that certificate once or twice in `httpsOptions.cert`, lists `https://localhost:3000/`, `https://foo.localhost:3000/` and `https://vite.vite.localhost:3000/` among the local URLs, for an IPv4 and an IPv6 server address.
- AC-3: a value in `httpsOptions.cert` that is not a certificate is skipped without an error, and the server's own local URL is still listed.
