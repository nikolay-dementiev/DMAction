# ``DMAction``

Compose callback-based work with fallbacks and retries, and get one result back.

## Overview

An action wraps a producer: a closure that receives a completion and calls it once with a result.
``DMAction/fallbackTo(_:)`` and ``DMAction/retry(_:)`` combine actions into new ones and run nothing.
Running an action calls its producers in order until one succeeds, and delivers one result. A
success carries an attempt label: the action's ``DMAction/currentAttempt``, 0 unless it was set,
plus the number of attempts of that run that failed before it.

```swift
import DMAction
import Foundation

// Stand-ins for your own service and cache.
func fetchQuote(_ handler: @escaping (String?, (any Error)?) -> Void) {
    handler(nil, URLError(.timedOut))
}
let lastCachedQuote = "Kept from the last visit"

let fresh = DMButtonAction { completion in
    fetchQuote { quote, error in
        if let quote {
            completion(.success(quote))
        } else {
            completion(.failure(error ?? URLError(.unknown)))
        }
    }
}
let cached = DMButtonAction { completion in
    completion(.success(lastCachedQuote))
}

let quote = fresh.retry(2).fallbackTo(cached)
quote { result in
    switch result.unwrapValue() {
    case .success(let value):
        print(value, "after", result.attemptCount ?? 0, "failed attempts")
    case .failure(let error):
        print(error)
    }
}
// Prints "Kept from the last visit after 3 failed attempts"
```

The fetch runs at most three times. The stand-in fails every time, so the cached quote is
delivered, labelled 3.

## Topics

### Actions

- ``DMAction/DMAction``
- ``DMButtonAction``
- ``DMActionWithFallback``

### Results

- ``DMActionResultValue``
- ``DMActionResultValueProtocol``
- ``PlaceholderCopyable``

### Running actions

- <doc:RunningActions>
