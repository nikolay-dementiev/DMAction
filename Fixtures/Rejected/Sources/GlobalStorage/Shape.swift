import DMAction

// Keeping a composed action in global storage.
enum Actions {
    static let reload = DMButtonAction { completion in
        completion(.success("done"))
    }
    .retry(2)
}
