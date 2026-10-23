# Uploading large files > 512 MB fails 

### Uploading large files fails with an exception

I'm using axios.put together with raw data to be uploaded to a server which doesn't accept multipart/form data. This works fine as long as the data to be uploaded is smaller than 512 MB. As soon as I try to use larger packages the axios.put fails with the following exception:

Node:buffer:798

return this.utf8Slice(0, this.length);
^
Error: Cannot create a string longer than 0x1fffffe8 characters
at Buffer.toString (node:buffer:798:17)
at Object.isFormData (file:///mytest/node_modules/axios/lib/utils.js:195:42)
at Object.transformRequest (file:///mytest/node_modules/axios/lib/defaults/index.js:55:30)
at transform (file:///mytest/node_modules/axios/lib/core/transformData.js:22:15)
at Object.forEach (file:///mytest/node_modules/axios/lib/utils.js:251:10)
at Object.transformData (file:///mytest/node_modules/axios/lib/core/transformData.js:21:9)
at Axios.dispatchRequest (file:///mytest/node_modules/axios/lib/core/dispatchRequest.js:40:31)
at process.processTicksAndRejections (node:internal/process/task_queues:95:5) {
code: 'ERR_STRING_TOO_LONG'

Why does axios try to interpret my request data as string even if Content-Type is set to "application/octet-stream"

### To Reproduce

      const buffer = fs.readFileSync(path);

      const config: AxiosRequestConfig = {
        url: url,
        method: options.method,
        headers: options.headers,
        data: buffer
      };

      const ax  = axios.create();
      ax.request(config).then(axiosResponse => {
        //do something with the response 
     })

### Axios Version

1.3.5

### Node.js Version

18.15.0

### OS

Windows 10 22H2

## Acceptance criteria

- AC-1: `utils.isFormData` never calls `toString` on a built-in object such as a Buffer, with or without an `append` method, so a Buffer body of any size is sent as it is.
- AC-2: A FormData that is not the global class, such as one from a polyfill, is still detected by its `Symbol.toStringTag` of `FormData` and its `append` method.
