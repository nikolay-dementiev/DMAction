//
//  DMAction
//
//  Created by Mykola Dementiev
//

/// The result of a producer, as the Domain folder spells it. It is the same type as the public
/// `DMAction.ResultType`, so a result crosses between the two without a conversion.
typealias ProducerResult = Result<any Copyable, any Error>

/// A producer, as the Domain folder spells it. It is the same type as the public
/// `DMAction.ActionType`, so a producer of the facade is a `Producer` as it is.
typealias Producer = (@escaping (ProducerResult) -> Void) -> Void
