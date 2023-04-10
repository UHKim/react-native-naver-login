import Foundation
import NaverThirdPartyLogin

@objc(RNNaverLogin)
class RNNaverLogin: NSObject {
    public override init() {
        super.init()
        initSDK()
    }
    
    private var connection: NaverThirdPartyLoginConnection {
        get {
            return NaverThirdPartyLoginConnection.getSharedInstance()
        }
    }
    
    private var loginPromiseResolver: RCTPromiseResolveBlock? = nil
    private var deleteTokenPromiseResolver: RCTPromiseResolveBlock? = nil
    private var deleteTokenPromiseRejector: RCTPromiseRejectBlock? = nil
    
    @objc
    static func requiresMainQueueSetup() -> Bool{
        return true;
    }
    
    func initSDK(serviceUrlScheme: String? = nil, consumerKey: String? = nil, consumerSecret: String? = nil,
                 appName: String? = nil, disableNaverAppAuth: Bool? = nil) {
        let dServiceUrlScheme: String? = Bundle.main.object(forInfoDictionaryKey: "naver_client_url_scheme") as? String
        let dConsumerKey: String? = Bundle.main.object(forInfoDictionaryKey: "naver_client_id") as? String
        let dConsumerSecret: String? = Bundle.main.object(forInfoDictionaryKey: "naver_client_secret") as? String
        let dAppName: String? = Bundle.main.object(forInfoDictionaryKey: "naver_client_name") as? String
        let dDisableNaverAppAuth: Bool? = Bundle.main.object(forInfoDictionaryKey: "naver_disable_naver_app_auth") as? Bool

        connection.serviceUrlScheme = serviceUrlScheme ?? dServiceUrlScheme ?? connection.serviceUrlScheme
        connection.consumerKey = consumerKey ?? dConsumerKey ?? connection.consumerKey
        connection.consumerSecret = consumerSecret ?? dConsumerSecret ?? connection.consumerSecret
        connection.appName = appName ?? dAppName ?? connection.appName
        connection.isNaverAppOauthEnable = (dDisableNaverAppAuth ?? disableNaverAppAuth ?? false) ? false : true
        
        connection.isInAppOauthEnable = true
        connection.delegate = self
    }
	
	@objc
	func login(_ serviceUrlScheme: String, consumerKey: String, consumerSecret: String,
			   appName: String, disableNaverAppAuth: Bool,
               resolve: @escaping RCTPromiseResolveBlock,
               reject: RCTPromiseRejectBlock){
		DispatchQueue.main.async { [unowned self] in
			loginPromiseResolver = resolve
            initSDK(serviceUrlScheme: serviceUrlScheme,
                    consumerKey: consumerKey,
                    consumerSecret: consumerSecret,
                    appName: appName,
                    disableNaverAppAuth: disableNaverAppAuth)
			connection.requestThirdPartyLogin()
		}
	}
	
	@objc
	func logout(_ resolve: @escaping RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
		DispatchQueue.main.async { [unowned self] in
			connection.resetToken()
			resolve(42)
		}
	}
	
	@objc
	func deleteToken(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
		DispatchQueue.main.async { [unowned self] in
			deleteTokenPromiseResolver = resolve
			deleteTokenPromiseRejector = reject
			connection.requestDeleteToken()
		}
	}
	
	
}

extension RNNaverLogin: NaverThirdPartyLoginConnectionDelegate {
	private func createLoginSuccessResponse() -> [String: Any] {
		return [
			"isSuccess": true,
			"successResponse": [
				"accessToken": connection.accessToken ?? "",
				"refreshToken": connection.refreshToken ?? "",
				"expiresAtUnixSecondString": "\(Int(connection.accessTokenExpireDate.timeIntervalSince1970))",
				"tokenType": connection.tokenType ?? "",
			],
		];
	}
	
	private func createLoginFailureResponse(isCancel: Bool, additionalMessage: String?) -> [String: Any] {
		return [
			"isSuccess": false,
			"failureResponse": [
				"isCancel": isCancel,
				"message": additionalMessage ?? "알 수 없는 에러입니다",
            ] as [String : Any],
		];
	}
	
	// Login Success
	func oauth20ConnectionDidFinishRequestACTokenWithAuthCode() {
		guard let resolver = loginPromiseResolver else { return }
		debugE("oauth20ConnectionDidFinishRequestACTokenWithAuthCode")
		
		resolver(createLoginSuccessResponse())
		loginPromiseResolver = nil
	}
	// Login Success
	func oauth20ConnectionDidFinishRequestACTokenWithRefreshToken() {
		guard let resolver = loginPromiseResolver else { return }
		debugE("oauth20ConnectionDidFinishRequestACTokenWithRefreshToken")
		
		resolver(createLoginSuccessResponse())
		loginPromiseResolver = nil
	}
	
	/* THIRDPARTYLOGIN_RECEIVE_TYPE
	 SUCCESS = 0,
	 PARAMETERNOTSET = 1,
	 CANCELBYUSER = 2,
	 NAVERAPPNOTINSTALLED = 3 ,
	 NAVERAPPVERSIONINVALID = 4,
	 OAUTHMETHODNOTSET = 5,
	 INVALIDREQUEST = 6,
	 CLIENTNETWORKPROBLEM = 7,
	 UNAUTHORIZEDCLIENT = 8,
	 UNSUPPORTEDRESPONSETYPE = 9,
	 NETWORKERROR = 10,
	 UNKNOWNERROR = 11
	 */
	
	private var receiveTypeToMessage: [String] {
		get {
			return [
				"SUCCESS",
				"PARAMETERNOTSET",
				"CANCELBYUSER",
				"NAVERAPPNOTINSTALLED",
				"NAVERAPPVERSIONINVALID",
				"OAUTHMETHODNOTSET",
				"INVALIDREQUEST",
				"CLIENTNETWORKPROBLEM",
				"UNAUTHORIZEDCLIENT",
				"UNSUPPORTEDRESPONSETYPE",
				"NETWORKERROR",
				"UNKNOWNERROR",
			]
		}
	}
	
	func oauth20Connection(_ oauthConnection: NaverThirdPartyLoginConnection!, didFailAuthorizationWithReceive receiveType: THIRDPARTYLOGIN_RECEIVE_TYPE) {
		guard let resolver = loginPromiseResolver else { return }
		debugE("oauth20Connection didFailAuthorizationWithReceive")
		
		let errorCode = Int(receiveType.rawValue)
		let isCancel = errorCode == 2
		
		resolver(createLoginFailureResponse(isCancel: isCancel, additionalMessage: receiveTypeToMessage[errorCode]))
		loginPromiseResolver = nil
	}
	
	
	// General Error handling
	func oauth20Connection(_ oauthConnection: NaverThirdPartyLoginConnection!, didFailWithError error: Error!) {
		debugE("oauth20Connection didFailWithError \(error.localizedDescription)")
		if let resolver = loginPromiseResolver { // error from login
			
			// TODO I can't sure this is correct
			let isCancel = error.localizedDescription.contains("access_denied")
			
			resolver(createLoginFailureResponse(isCancel: isCancel, additionalMessage: error.localizedDescription))
			loginPromiseResolver = nil
		} else if let rejector = deleteTokenPromiseRejector { // error from deleteToken
			rejector(error.localizedDescription, error.localizedDescription, error)
			deleteTokenPromiseResolver = nil
			deleteTokenPromiseRejector = nil
		}
	}
	
	// Delete token success
	func oauth20ConnectionDidFinishDeleteToken() {
		guard let resolver = deleteTokenPromiseResolver else { return }
		debugE("oauth20ConnectionDidFinishDeleteToken")
		
		resolver(42)
		deleteTokenPromiseResolver = nil
		deleteTokenPromiseRejector = nil
	}
}

fileprivate func debugE(_ msg: Any...){
#if DEBUG
	if msg.count == 0{
		print("🧩",msg,"🧩")
	}else{
		var msgs = ""
		for i in msg{
			msgs += "\(i) "
		}
		print("🧩",msgs,"🧩")
	}
#endif
}

