# DMAction

<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/DMAction-SDK-logo.png?raw=true" alt="DMAction SDK logo" height="200">
</p>

[![Swift](https://img.shields.io/badge/Swift-5%2B-orange?style=flat-square)](https://swift.org) [![Swift tools version](https://img.shields.io/badge/Swift_tools-6.0-darkorange?style=flat-square)](https://swift.org/package-manager/)

[![Platforms](https://img.shields.io/badge/Platforms-iOS_17%2B_%7C_watchOS_7%2B-yellowgreen?style=flat-square)](#installation)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/DMAction.svg?style=flat-square)](https://cocoapods.org/pods/DMAction)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](#swift-package-manager)
[![CI](https://github.com/nikolay-dementiev/DMAction/actions/workflows/CI_tests.yml/badge.svg)](https://github.com/nikolay-dementiev/DMAction/actions/workflows/CI_tests.yml)

- [Overview](#overview)
- [Features](#features)
- [UML diagrams](#uml-diagrams)
- [Installation](#installation)
  - [CocoaPods](#cocoapods)
  - [Swift Package Manager](#swift-package-manager)
- [Usage](#usage)
  - [Basic usage](#basic-usage)
  - [Using with UIKit](#using-with-uikit)
  - [Using with SwiftUI](#using-with-swiftui)
  - [Retry and fallback example](#retry-and-fallback-example)
- [License](#license)
- [Additional resources](#additional-resources)

## Overview

DMAction is a Swift library for composing completion-based actions with retry and fallback behavior. It centralizes execution and result handling behind a protocol-oriented API shared by UIKit and SwiftUI clients.

## Features

- Compose actions with configurable retry and fallback behavior
- Receive asynchronous results through completion handlers
- Ignore results through `simpleAction` or handle them through `Result`
- Use the same small API from UIKit and SwiftUI

## UML diagrams
### Protocol overview

<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/Uml-schema.svg?raw=true" alt="DMAction protocol overview diagram" height="300">
</p>

### Retry mechanism

<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/Retry-Mechanism.svg?raw=true" alt="DMAction retry mechanism diagram" height="300">
</p>

### Fallback behavior

<p align="center">
  <img src="https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/Fallback-Behavior.svg?raw=true" alt="DMAction fallback behavior diagram" height="300">
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

To add `DMAction` through Swift Package Manager, include it in the `dependencies` array of your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/nikolay-dementiev/DMAction.git", from: "1.0.5")
]
```

## Usage

### Basic usage

For retry and fallback composition, see the [retry and fallback example](#retry-and-fallback-example).

```swift
import DMAction

let buttonAction = DMButtonAction {
    print("Button action performed")
}

buttonAction.simpleAction()
```

### Using with UIKit

```swift
import Foundation
import UIKit
import DMAction

final class ActionViewController: UIViewController {
    override func loadView() {
        let ignoreResultButton = UIButton(type: .system)
        ignoreResultButton.setTitle("Run and ignore result", for: .normal)
        ignoreResultButton.addTarget(
            self,
            action: #selector(performIgnoringResult),
            for: .touchUpInside
        )

        let handleResultButton = UIButton(type: .system)
        handleResultButton.setTitle("Run and handle result", for: .normal)
        handleResultButton.addTarget(
            self,
            action: #selector(performHandlingResult),
            for: .touchUpInside
        )

        let stackView = UIStackView(arrangedSubviews: [
            ignoreResultButton,
            handleResultButton
        ])
        stackView.axis = .vertical
        stackView.spacing = 12
        view = stackView
    }

    @objc
    private func performIgnoringResult() {
        makeAction().simpleAction()
    }

    @objc
    private func performHandlingResult() {
        let action = makeAction()
        action { result in
            // Handle the result.
        }
    }

    private func makeAction() -> DMActionWithFallback {
        let primaryAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackAction = DMButtonAction(makeActionWithSuccessResult)

        return primaryAction
            .retry(2)
            .fallbackTo(fallbackAction)
    }

    private func makeActionWithFailureResult(
        completion: @escaping (DMAction.ResultType) -> Void
    ) {
        completion(.failure(NSError(
            domain: "TestDomain",
            code: 404,
            userInfo: nil
        )))
    }

    private func makeActionWithSuccessResult(
        completion: @escaping (DMAction.ResultType) -> Void
    ) {
        let resultValue: Copyable = "\(#function) succeeded!"
        completion(.success(resultValue))
    }
}
```

### Using with SwiftUI

```swift
import Foundation
import SwiftUI
import DMAction

struct ActionButtonsView: View {
    var body: some View {
        VStack {
            Button("Run and ignore result", action: performIgnoringResult)
            Button("Run and handle result", action: performHandlingResult)
        }
    }

    private func performIgnoringResult() {
        makeAction().simpleAction()
    }

    private func performHandlingResult() {
        let action = makeAction()
        action { result in
            // Handle the result.
        }
    }

    private func makeAction() -> DMActionWithFallback {
        let primaryAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackAction = DMButtonAction(makeActionWithSuccessResult)

        return primaryAction
            .retry(2)
            .fallbackTo(fallbackAction)
    }

    private func makeActionWithFailureResult(
        completion: @escaping (DMAction.ResultType) -> Void
    ) {
        completion(.failure(NSError(
            domain: "TestDomain",
            code: 404,
            userInfo: nil
        )))
    }

    private func makeActionWithSuccessResult(
        completion: @escaping (DMAction.ResultType) -> Void
    ) {
        let resultValue: Copyable = "\(#function) succeeded!"
        completion(.success(resultValue))
    }
}
```


### Retry and fallback example

This example allows one retry after the primary action's initial attempt. If both attempts fail, DMAction invokes the fallback action.

```swift
import Foundation
import DMAction

let primaryButtonAction = DMButtonAction { completion in
    completion(.failure(NSError(domain: "TestError", code: 1, userInfo: nil)))
}

let fallbackButtonAction = DMButtonAction { completion in
    completion(.success("Fallback succeeded"))
}

let actionWithFallback = primaryButtonAction
    .retry(1)
    .fallbackTo(fallbackButtonAction)

actionWithFallback { result in
    let unwrappedResult = result.unwrapValue()
    print("Attempt count: \(result.attemptCount ?? 0)")

    switch unwrappedResult {
    case .success(let value):
        print("Result value: \(value)")
    case .failure(let error):
        print("Action failed: \(error)")
    }
}
```

## License

DMAction is available under the MIT License. See [LICENSE](LICENSE) for details.

## Additional resources

- [The Challenges of Retry Logic and Fallback Mechanisms in App Development](https://github.com/nikolay-dementiev/DMAction/blob/main/Resources/Article_sdk_for_handling_actions_in_swift_using_retry_and_fallback_feature.md)
