<p align="center">
  <img width="200" height="200" src="https://cdn.bulbagarden.net/upload/thumb/b/ba/123Scyther.png/600px-123Scyther.png">
</p>

# Scyther

<p align="left">
  <img src="https://img.shields.io/badge/platform-iOS-blue"> <img src="https://img.shields.io/badge/spm-main-green"> <img src="https://img.shields.io/github/license/bstillitano/Scyther">
</p>

Just like scyther, this menu helps you cut through bugs in your iOS app. Scyther is a fully fledged debug menu that provides tools for developers, UAT (QA) members/testers, UI/UX teams, backend developers and even frontend developers who use your app.

- [Features](#features)
- [Component Libraries](#component-libraries)
- [Requirements](#requirements)
- [Migration Guides](#migration-guides)
- [Communication](#communication)
- [Installation](#installation)
- [Usage](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#using-alamofire)
    - [**Introduction -**](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#introduction) [Making Requests](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#making-requests), [Response Handling](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#response-handling), [Response Validation](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#response-validation), [Response Caching](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#response-caching)
	- **HTTP -** [HTTP Methods](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#http-methods), [Parameters and Parameter Encoder](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md##request-parameters-and-parameter-encoders), [HTTP Headers](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#http-headers), [Authentication](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#authentication)
	- **Large Data -** [Downloading Data to a File](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#downloading-data-to-a-file), [Uploading Data to a Server](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#uploading-data-to-a-server)
	- **Tools -** [Statistical Metrics](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#statistical-metrics), [cURL Command Output](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#curl-command-output)
- [Advanced Usage](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md)
	- **URL Session -** [Session Manager](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#session), [Session Delegate](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#sessiondelegate), [Request](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#request)
	- **Routing -** [Routing Requests](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#routing-requests), [Adapting and Retrying Requests](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#adapting-and-retrying-requests-with-requestinterceptor)
	- **Model Objects -** [Custom Response Handlers](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#customizing-response-handlers)
	- **Connection -** [Security](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#security), [Network Reachability](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#network-reachability)
- [FAQ](#faq)
- [Credits](#credits)
- [Donations](#donations)
- [License](#license)


## Why does Scyther exist?

Working on some of the most-widely used and distributed codebases developed in Australia, I noticed just how powerful some of the tooling that these teams had developed internally was. This coupled with experience at startups and some time on small projects, I noticed a huge gap when it came to readily-available tools/libraries for small teams and junior developers that help answe the constant questions that I get asked.

## Features

- [x] Chainable Request / Response Methods
- [x] Combine Support
- [x] URL / JSON Parameter Encoding
- [x] Upload File / Data / Stream / MultipartFormData
- [x] Download File using Request or Resume Data
- [x] Authentication with `URLCredential`
- [x] HTTP Response Validation
- [x] Upload and Download Progress Closures with Progress
- [x] cURL Command Output
- [x] Dynamically Adapt and Retry Requests
- [x] TLS Certificate and Public Key Pinning
- [x] Network Reachability
- [x] Comprehensive Unit and Integration Test Coverage
- [x] [Complete Documentation](https://alamofire.github.io/Alamofire)

## Component Libraries

In order to keep Alamofire focused specifically on core networking implementations, additional component libraries have been created by the [Alamofire Software Foundation](https://github.com/Alamofire/Foundation) to bring additional functionality to the Alamofire ecosystem.

- [AlamofireImage](https://github.com/Alamofire/AlamofireImage) - An image library including image response serializers, `UIImage` and `UIImageView` extensions, custom image filters, an auto-purging in-memory cache, and a priority-based image downloading system.
- [AlamofireNetworkActivityIndicator](https://github.com/Alamofire/AlamofireNetworkActivityIndicator) - Controls the visibility of the network activity indicator on iOS using Alamofire. It contains configurable delay timers to help mitigate flicker and can support `URLSession` instances not managed by Alamofire.

## Requirements

- iOS 10.0+
- Xcode 11+
- Swift 5.1+

## Migration Guides

- [Alamofire 5.0 Migration Guide](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Alamofire%205.0%20Migration%20Guide.md)
- [Alamofire 4.0 Migration Guide](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Alamofire%204.0%20Migration%20Guide.md)
- [Alamofire 3.0 Migration Guide](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Alamofire%203.0%20Migration%20Guide.md)
- [Alamofire 2.0 Migration Guide](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Alamofire%202.0%20Migration%20Guide.md)

## Communication
- If you **need help with making network requests** using Alamofire, use [Stack Overflow](https://stackoverflow.com/questions/tagged/alamofire) and tag `alamofire`.
- If you need to **find or understand an API**, check [our documentation](http://alamofire.github.io/Alamofire/) or [Apple's documentation for `URLSession`](https://developer.apple.com/documentation/foundation/url_loading_system), on top of which Alamofire is built.
- If you need **help with an Alamofire feature**, use [our forum on swift.org](https://forums.swift.org/c/related-projects/alamofire).
- If you'd like to **discuss Alamofire best practices**, use [our forum on swift.org](https://forums.swift.org/c/related-projects/alamofire).
- If you'd like to **discuss a feature request**, use [our forum on swift.org](https://forums.swift.org/c/related-projects/alamofire). 
- If you **found a bug**, open an issue here on GitHub and follow the guide. The more detail the better!
- If you **want to contribute**, submit a pull request!

## Installation

### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for managing the distribution of Swift code. It’s integrated with the Swift build system to automate the process of downloading, compiling, and linking dependencies. 

Once you have your Swift package set up, adding Scyther as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/bstillitano/Scyther.git", branch: "main")
]
```

## FAQ

### What's the origin of the name Alamofire?

Alamofire is named after the [Alamo Fire flower](https://aggie-horticulture.tamu.edu/wildseed/alamofire.html), a hybrid variant of the Bluebonnet, the official state flower of Texas.

## Credits

Alamofire is owned and maintained by the [Alamofire Software Foundation](http://alamofire.org). You can follow them on Twitter at [@AlamofireSF](https://twitter.com/AlamofireSF) for project updates and releases.

### Security Disclosure

If you believe you have identified a security vulnerability with Alamofire, you should report it as soon as possible via email to security@alamofire.org. Please do not post it to a public issue tracker.

## Donations

The [ASF](https://github.com/Alamofire/Foundation#members) is looking to raise money to officially stay registered as a federal non-profit organization.
Registering will allow Foundation members to gain some legal protections and also allow us to put donations to use, tax-free.
Donating to the ASF will enable us to:

- Pay our yearly legal fees to keep the non-profit in good status
- Pay for our mail servers to help us stay on top of all questions and security issues
- Potentially fund test servers to make it easier for us to test the edge cases
- Potentially fund developers to work on one of our projects full-time

The community adoption of the ASF libraries has been amazing.
We are greatly humbled by your enthusiasm around the projects and want to continue to do everything we can to move the needle forward.
With your continued support, the ASF will be able to improve its reach and also provide better legal safety for the core members.
If you use any of our libraries for work, see if your employers would be interested in donating.
Any amount you can donate today to help us reach our goal would be greatly appreciated.

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=W34WPEE74APJQ)

## License

Scyther is released under the MIT license. [See LICENSE](https://github.com/bstillitano/Scyther/blob/master/LICENSE) for details.