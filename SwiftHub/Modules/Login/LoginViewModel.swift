//
//  LoginViewModel.swift
//  SwiftHub
//
//  Created by Khoren Markosyan on 7/12/18.
//  Copyright © 2018 Khoren Markosyan. All rights reserved.
//

import Foundation
import RxCocoa
import RxSwift
import SafariServices

private let loginURL = URL(string: "http://github.com/login/oauth/authorize?client_id=\(Keys.github.appId)&scope=user+repo+notifications")!
private let callbackURLScheme = "swifthub"

class LoginViewModel: ViewModel, ViewModelType {

    struct Input {
        let segmentSelection: Driver<LoginSegments>
        let basicLoginTrigger: Driver<Void>
        let oAuthLoginTrigger: Driver<Void>
    }

    struct Output {
        let basicLoginTriggered: Driver<Void>
        let oAuthLoginTriggered: Driver<Void>
        let basicLoginButtonEnabled: Driver<Bool>
        let hidesBasicLoginView: Driver<Bool>
        let hidesOAuthLoginView: Driver<Bool>
    }

    let login = BehaviorRelay(value: "")
    let password = BehaviorRelay(value: "")

    var tokenSaved = PublishSubject<Void>()

    func transform(input: Input) -> Output {
        let basicLoginTriggered = input.basicLoginTrigger
        let oAuthLoginTriggered = input.oAuthLoginTrigger

        basicLoginTriggered.drive(onNext: { [weak self] () in
            if let login = self?.login.value,
                let password = self?.password.value,
                let authHash = "\(login):\(password)".base64Encoded {
                AuthManager.setToken(token: Token(basicToken: "Basic \(authHash)"))
                self?.tokenSaved.onNext(())
            }
        }).disposed(by: rx.disposeBag)

        oAuthLoginTriggered.drive(onNext: { () in
            logDebug("oAuth login coming soon.")
        }).disposed(by: rx.disposeBag)

        tokenSaved.flatMapLatest { () -> Observable<RxSwift.Event<User>> in
            return self.provider.profile()
                .trackActivity(self.loading)
                .trackError(self.error)
                .materialize()
            }.subscribe(onNext: { (event) in
                switch event {
                case .next(let user):
                    user.save()
                    AuthManager.tokenValidated()
                    if let login = user.login {
                        analytics.log(SwifthubEvent.login(login: login))
                    }
                case .error(let error):
                    logError(error.localizedDescription)
                default: break
                }
            }).disposed(by: rx.disposeBag)

        let basicLoginButtonEnabled = BehaviorRelay.combineLatest(login, password, self.loading.asObservable()) {
            return $0.isNotEmpty && $1.isNotEmpty && !$2
        }.asDriver(onErrorJustReturn: false)

        let hidesBasicLoginView = input.segmentSelection.map { $0 != LoginSegments.basic }
        let hidesOAuthLoginView = input.segmentSelection.map { $0 != LoginSegments.oAuth }

        return Output(basicLoginTriggered: basicLoginTriggered,
                      oAuthLoginTriggered: oAuthLoginTriggered,
                      basicLoginButtonEnabled: basicLoginButtonEnabled,
                      hidesBasicLoginView: hidesBasicLoginView,
                      hidesOAuthLoginView: hidesOAuthLoginView)
    }
}
