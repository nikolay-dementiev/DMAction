//
//  DMAction
//
//  Created by Mykola Dementiev
//

import UIKit

@MainActor
final class MockMyViewController: UIViewController {
    
    lazy var button: UIButton = {
        let button = UIButton()
        button.setTitle("Tap me", for: .normal)
        button.backgroundColor = .blue
        button.addTarget(self,
                         action: #selector(buttonTapped),
                         for: .touchUpInside)
        view.addSubview(button)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        button.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        return button
    }()
    lazy var tapGesture: UITapGestureRecognizer = {
        let tapGesture = UITapGestureRecognizer(target: self,
                                                action: #selector(viewTapped))
        view.addGestureRecognizer(tapGesture)
        return tapGesture
    }()
    
    var buttonTappedClosure: (() -> Void)?
    var viewTappedClosure: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        _ = button
        _ = tapGesture
        
        buttonTappedClosure = buttonTapped
        viewTappedClosure = viewTapped
    }
    
    @objc func buttonTapped() {
        buttonTappedClosure?()
    }
    
    @objc func viewTapped() {
        viewTappedClosure?()
    }
}
