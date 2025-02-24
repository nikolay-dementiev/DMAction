<img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/DMAction-SDK-logo.png?raw=true" alt="DMAction-SDK-logo" height="200">
[![Swift](https://img.shields.io/badge/Swift-5*-orange?style=flat-square)](https://img.shields.io/badge/Swift-5*-blue?style=flat-square)
[![Swift-tools-version](https://img.shields.io/badge/Swift--tools-6.0-darkorange?style=flat-square)](https://img.shields.io/badge/Swift--tools-6.0-darkorange?style=flat-square)

[![Platforms](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/DMAction.svg?style=flat-square)](https://img.shields.io/cocoapods/v/DMAction.svg)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

# DMAction Swift SDK

DMAction is a Swift SDK that provides a framework for defining and handling actions with retry and fallback mechanisms. It offers a flexible way to manage asynchronous actions and handle errors gracefully.

## Features

- Define actions with retry and fallback mechanisms
- Handle asynchronous actions with completion handlers
- Protocol-based design for easy integration
- Simple and intuitive API

## Installation

### CocoaPods

To integrate `DMAction` into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
pod 'DMAction'
```

Then, run the following command:

```bash
pod install
```

### Swift Package Manager

To integrate DMAction into your Xcode project using Swift Package Manager, add it to the dependencies array in your Package.swift file:

```Swift
dependencies: [
    .package(url: "https://github.com/nikolay-dementiev/DMAction.git", from: "1.0.0")
]
```
## Usage

### Full flow structure
- An example with two different actions (primaryButtonAction and fallbackButtonAction) combined 
into a single execution chain using `.retry(1)`:
    - `1` represents the maximum number of retry attempts for `primaryButtonAction`. It will be executed until either it succeeds or the retry limit is reached.
    - If `primaryButtonAction` fails after the maximum attempts,`fallbackButtonAction` will be triggered via `fallbackTo(...)`.
```Swift


// Primary action
let primaryButtonAction = DMButtonAction { completion in
    completion(.failure(NSError(domain: "TestError", code: 1, userInfo: nil)))
}

// Fallback action
let fallbackButtonAction = DMButtonAction { completion in
    completion(.success(MockCopyable(value: "Fallback Success")))
}

// Create execution chain
let actionWithFallback = primaryButtonAction
    .retry(1) //The number of retry action before fallback
    .fallbackTo(fallbackButtonAction)
    
actionWithFallback { output in
    // `unwrapValue()`: get rid of the wrapper - return the original result value that was passed via DMButtonAction' completion closure
    result = output.unwrapValue()
    // `attemptCount`: contains UInt number of action's attemps
    attemptExecuted = output.attemptCount
}

if case .success(let copyable) = result {
    ...
} else {
    ...
}
```

## License
This project is licensed under the MIT License - see the LICENSE file for details.
