//
//  DMAction
//
//  Created by Mykola Dementiev
//

import UIKit

extension UIViewController {
    func startViewLifecycle() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
}
