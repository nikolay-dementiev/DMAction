# ``DMAction``

Compose callback-based work with fallbacks and retries, and get one result back.

## Overview

An action wraps a producer: a closure that receives a completion and calls it once with a result.
``DMAction/fallbackTo(_:)`` and ``DMAction/retry(_:)`` combine actions into new ones and run nothing.
Running an action calls its producers in order until one succeeds, and delivers one result. A
success carries an attempt label: how many attempts of that run failed before it.

```swift
import DMAction

let fresh = DMButtonAction { completion in
    quoteService.fetchQuote { quote, error in
        if let quote {
            completion(.success(quote))
        } else {
            completion(.failure(error ?? URLError(.unknown)))
        }
    }
}
let cached = DMButtonAction { completion in
    completion(.success(quoteCache.lastQuote))
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
```

The fetch runs at most three times. When all three attempts fail, the cached quote is delivered,
labelled 3.

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
