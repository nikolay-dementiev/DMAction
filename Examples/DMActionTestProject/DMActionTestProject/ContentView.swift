//
//  DMActionTestProject
//
//  Created by Mykola Dementiev
//

import SwiftUI
import DMAction

struct ContentView: View {
    var body: some View {
        VStack {
            // If the result is completely uninteresting (muted)
            Button("Test button with muted result",
                   action: buttonTestActionWithMutedResult)
            // if you need to process the result
            Button("Test button with handled result",
                   action: buttonTestActionWithHandledResult)
        }
        .padding()
    }
}

private extension ContentView {
    func buttonTestActionWithMutedResult() {
        let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)

        primaryButtonAction
            .retry(2)
            .fallbackTo(fallbackButtonAction)
            .simpleAction()

        print("\(#function) done")
    }

    func buttonTestActionWithHandledResult() {
        let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)

        primaryButtonAction
            .retry(3)
            .fallbackTo(fallbackButtonAction)() { result in
                print("Attempt count: `\(result.attemptCount!)`")
                print("The result is: `\(result.unwrapValue())")

                // do something with result
            }

        print("`\(#function)` done")
    }

    func makeActionWithFailureResult(completion: @escaping (DMButtonAction.ResultType) -> Void) {

        // ... do something

        completion(.failure(NSError(domain: "TestDomain",
                                    code: 404,
                                    userInfo: nil)))
    }

    func makeActionWithSuccessResult(completion: @escaping (DMButtonAction.ResultType) -> Void) {

        // ... do something

        let yourResultVaue: Copyable = "\(#function) succeded!"
        completion(.success(yourResultVaue))
    }
}

#Preview {
    ContentView()
}
