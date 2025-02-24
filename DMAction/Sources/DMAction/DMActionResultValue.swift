//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

public struct DMActionResultValue: DMActionResultValueProtocol {
    public let attemptCount: UInt?
    public let value: Copyable
    
    public init(value: Copyable,
                attemptCount: UInt? = nil) {
        self.value = value
        self.attemptCount = attemptCount
    }
}

public struct PlaceholderCopyable: Copyable {
    public init() { }
}
