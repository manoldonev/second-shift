# [1.0.0] Set-Cookie header in a response interceptor is not an array anymore

#### Describe the bug
In v1, accessing the 'Set-Cookie' header in a response interceptor yields the raw string value of the header.

#### To Reproduce

```js
const axios = require('axios'),
      http = require('http');

const server = http
        .createServer((req, res) => {
          res.setHeader('Set-Cookie', 'my=value');
          res.writeHead(200);
          res.write('Hi there');
          res.end();
        })
        .listen(0),
      request = axios.create();

request.interceptors.response.use((res) => {
  console.log(res.headers['set-cookie']);
});

request({ url: `http://localhost:${server.address().port}` }).then(() => server.close());
```

The produces `my=value`

#### Expected behavior
`[ 'my=value' ]`

#### Environment
 - Axios Version [e.g. 0.18.0]: 1.0.0
 - Adapter [e.g. XHR/HTTP]: http
 - Browser [e.g. Chrome, Safari]: N/A
 - Browser Version [e.g. 22]: N/A
 - Node.js Version [e.g. 13.0.1]: 16.13.0
 - OS: [e.g. iOS 12.1.0, OSX 10.13.4]: Ubuntu 20.04
 - Additional Library Versions [e.g. React 16.7, React Native 0.58.0]: N/A

#### Additional context/Screenshots

N/A

## Acceptance criteria

- AC-1: In a response interceptor, `res.headers['set-cookie']` is an array of the cookies the server set.
- AC-2: `AxiosHeaders#toJSON()` keeps an array value as an array of strings.
