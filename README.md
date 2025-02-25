<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/DMAction-SDK-logo.png?raw=true" alt="DMAction-SDK-logo" height="200">
</p>

[![Swift](https://img.shields.io/badge/Swift-5\*-orange?style=flat-square)](https://img.shields.io/badge/Swift-5\*-blue?style=flat-square) [![Swift-tools-version](https://img.shields.io/badge/Swift--tools-6.0-darkorange?style=flat-square)](https://img.shields.io/badge/Swift--tools-6.0-darkorange?style=flat-square)

[![Platforms](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/DMAction.svg?style=flat-square)](https://img.shields.io/cocoapods/v/DMAction.svg)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
![Unit Tests coverage](https://img.shields.io/badge/Test_Coverage-99.4%25-darkgreen?style=flat-square)

- [DMAction Swift SDK](#dm-action-swift-sdk)
  - [Features](#features)
  - [UML Schema](#uml-schema)
  - [Installation](#installation)
    - [CocoaPods](#cocoaPods-installation)
    - [Swift Package Manager](#swift-package-manager-installation)
  - [Usage](#usage)
    - [Basic](#basic-usage)
    - [Using within UIKit](#using-within-ui_kit)
    - [Using within SWiftUI](#using-within-swift_ui)
    - [Full usage example](#full-usage-example)
  - [License](#license)

# DMAction Swift SDK

DMAction is a Swift SDK that provides a framework for defining and handling actions with retry and fallback mechanisms. It offers a flexible way to manage asynchronous actions and handle errors gracefully.

## Features

- Define actions with retry and fallback mechanisms
- Handle asynchronous actions with completion handlers
- Protocol-based design for easy integration
- Simple and intuitive API

## UML Schema

<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/Uml-schema.svg?raw=true" alt="Uml-schema" height="300">
</p>

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
    .package(url: "https://github.com/nikolay-dementiev/DMAction.git", from: "v1.0.3")
]
```
## Usage

### Basic (of course simple action closure works as expected). 
####   But the main power was explained in the section below [`A More Advanced Example`](#a-more-advanced-example):

```Swift
let buttonAction = DMButtonAction {
    print("Button action performed")
}

buttonAction { _ in
    ...
}
```

### Using within UIKit
```Swift

let buttonTest = UIButton(type: .system)

// If the result is completely uninteresting (muted)
buttonTest.addTarget(self,// `self` here is some UIKit object where the action's function exists
                     action: #selector(buttonTestActionWithMutedResult),
                     for: .touchUpInside)
// OR:
                     
// if you need to process the result
buttonTest.addTarget(self,// `self` here is some UIKit object where the action's function exists
                     action: #selector(buttonTestActionWithHandledResult),
                     for: .touchUpInside)
                     
@objc
func buttonTestActionWithMutedResult() {
    let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
    let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
    
    primaryButtonAction
        .retry(2)
        .fallbackTo(fallbackButtonAction)
        .simpleAction()
}

@objc
func buttonTestActionWithHandledResult() {
    let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
    let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
    
    primaryButtonAction
        .retry(2)
        .fallbackTo(fallbackButtonAction)() { result in
            // do something with result
        }
}
```

### Using within SWiftUI
```Swift
...
var body: some View {
    // If the result is completely uninteresting (muted)
    Button("Test button with muted result", action: buttonTestActionWithMutedResult)
    // if you need to process the result
    Button("Test button with handled result", action: buttonTestActionWithHandledResult)
}
...

@objc
func buttonTestActionWithMutedResult() {
    let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
    let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
    
    primaryButtonAction
        .retry(2)
        .fallbackTo(fallbackButtonAction)
        .simpleAction()
}

@objc
func buttonTestActionWithHandledResult() {
    let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
    let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
    
    primaryButtonAction
        .retry(2)
        .fallbackTo(fallbackButtonAction)() { result in
            // do something with result
        }
}
```


### A More Advanced Example

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
    
var resultOfAction: DMAction.ResultType?
actionWithFallback { result in
    // `unwrapValue()`: get rid of the wrapper - return the original result value that 
    // was passed via DMButtonAction' completion closure
    print("the result value: \(result.unwrapValue())")
    // `attemptCount`: contains UInt number of action's attemps
    print("attemptCount: \(result.attemptCount)")
    
    resultOfAction = result
}

if case .success(let copyableValue) = resultOfAction {
    ...
} else {
    ...
}
```

## License
This project is licensed under the MIT License - see the LICENSE file for details.
