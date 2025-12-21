# Network Debugging

Inspect HTTP requests and responses to debug API interactions.

@Metadata {
    @PageColor(green)
}

## Overview

Scyther automatically intercepts all HTTP requests made through `URLSession` and logs them for inspection. This helps you debug API issues, verify request formatting, and understand network timing.

## Automatic Logging

Once Scyther is started, network logging is enabled automatically. All requests show up in the **Network Logs** section of the Scyther menu.

Each logged request includes:
- URL and HTTP method
- Request headers
- Request body (formatted for JSON)
- Response status code
- Response headers
- Response body
- Timing information
- cURL command for reproduction

## Viewing Requests

Open the Scyther menu and navigate to **Network Logs** to see all captured requests. Tap any request to see its full details.

### Request Details

The detail view shows:
- **Overview**: Method, URL, status code, duration
- **Request**: Headers and body sent to the server
- **Response**: Headers and body received from the server
- **cURL**: A ready-to-use cURL command to reproduce the request

## Accessing Network Data Programmatically

### Device IP Address

Get the device's public IP address:

```swift
let ip = await Scyther.network.ipAddress
print("Device IP: \(ip)")
```

### Streaming Requests

The ``NetworkLogger`` uses `AsyncStream` for real-time request updates:

```swift
// In your debug view
for await request in NetworkLogger.shared.requests {
    print("New request: \(request.url)")
}
```

## Filtering Requests

In the Network Logs UI, you can filter requests by:
- HTTP method (GET, POST, PUT, DELETE, etc.)
- Status code (success, client error, server error)
- URL pattern

## Exporting cURL Commands

Every request can be exported as a cURL command. This is useful for:
- Sharing with backend developers
- Testing in terminal
- Creating API documentation
- Debugging in tools like Postman

Example exported cURL:

```bash
curl -X POST 'https://api.example.com/users' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer token123' \
  -d '{"name": "John", "email": "john@example.com"}'
```

## Best Practices

### 1. Sensitive Data

Be aware that network logs may contain sensitive data like:
- Authentication tokens
- Personal information
- API keys

Scyther is automatically disabled in App Store builds to prevent exposure.

### 2. Large Responses

Very large response bodies are truncated for performance. If you need to inspect a large response, use the cURL export to replay the request.

### 3. Binary Data

Binary responses (images, files) are noted but not displayed inline. Use the cURL command to download them separately.

## Troubleshooting

### Requests Not Appearing

If requests aren't being logged:

1. Ensure `Scyther.start()` was called before making requests
2. Check that you're using `URLSession` (not custom networking)
3. Verify the app isn't an App Store build

### Custom URLSession Configurations

If you're using a custom `URLSessionConfiguration`, Scyther's protocol may not be automatically registered. Ensure you're using standard session configurations.

## See Also

- ``NetworkLogger``
- ``NetworkLoggerRequest``
- ``Network``

