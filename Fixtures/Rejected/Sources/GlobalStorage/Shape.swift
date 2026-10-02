import DMAction

// Keeping a composed action in global storage.
// expected-error: static property 'reload' is not concurrency-safe
enum Actions {
    static let reload = DMButtonAction { completion in
        completion(.success("done"))
    }
    .retry(2)
}
