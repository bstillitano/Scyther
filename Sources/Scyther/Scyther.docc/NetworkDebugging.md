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

The Network Logs screen offers two ways to narrow the list, and they combine.

**Search** matches the URL, GraphQL operation name, status code, or HTTP method.

**Filter chips** sit above the list. Tap a chip to open a sheet with a multi-select checklist:

- **Method**: the HTTP methods present in the captured requests
- **Status**: 2xx success, 3xx redirect, 4xx client error, 5xx server error, or pending / no response
- **Host**: the request hosts present in the captured requests. An Include / Exclude segmented
  control in the list header decides whether the selected hosts are the only ones shown or the
  ones hidden
- **Type**: JSON, XML, HTML, Image, or Other, based on the detected response content type
- **API**: REST or GraphQL
- **GraphQL**: Query, Mutation, Subscription, or Batch / Unknown for GraphQL requests with no
  single operation type. REST requests never match a GraphQL selection
- **Duration**: under 100ms, 100ms to 500ms, 500ms to 1s, 1s to 3s, or over 3s. Requests still
  awaiting a response have no duration and never match a duration selection
- **Code**: the exact response status codes present in the captured requests
- **Recency**: last minute, 5 minutes, 15 minutes, or hour, measured from when the filter runs.
  Single-select, since each window contains the shorter ones

The icon-only chip at the start of the row opens a full-height Filters sheet that lists every
dimension, grouped into Request, Response, and Timing, with a summary of its selection. Tapping a row pushes that dimension's checklist, with
a Reset for that dimension alone; the root Filters screen offers Reset for everything.

Selections apply immediately behind the sheet. Chips combine with AND, values within a chip with
OR (Recency allows one value). Active chips are fully tinted and show the selected value when exactly one is chosen, or the
dimension name with a count when several are. A Reset button appears in each
sheet while it has a selection, and a red Clear chip appears in the bar whenever any filter is active.
Filters are held in memory for the current session only.

## Exporting cURL Commands

Every request can be exported as a cURL command from the request details page. Tap the
share button in the top-trailing corner of the navigation bar, or the "Export cURL request"
row in the Developer Info section; both present the same system share sheet. This is useful for:
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

