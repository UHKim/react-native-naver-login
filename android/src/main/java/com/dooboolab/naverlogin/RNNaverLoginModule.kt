package com.dooboolab.naverlogin

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.util.Log
import com.facebook.react.bridge.*
import com.navercorp.nid.NaverIdLoginSDK
import com.navercorp.nid.oauth.NidOAuthErrorCode
import com.navercorp.nid.oauth.NidOAuthLogin
import com.navercorp.nid.oauth.OAuthLoginCallback

class RNNaverLoginModule(private val reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(
    reactContext
) {
    override fun getName() = "RNNaverLogin"

    fun initSDK(context: Context?, consumerKey: String?, consumerSecret: String?, appName: String?): Boolean {
        val naverConsumerKey = reactContext.resources.getString(
            reactContext.resources.getIdentifier("naver_client_id", "string", reactContext.packageName))
        val naverConsumerSecret = reactContext.resources.getString(
            reactContext.resources.getIdentifier("naver_client_secret", "string", reactContext.packageName))
        val naverAppName = reactContext.resources.getString(
            reactContext.resources.getIdentifier("naver_client_name", "string", reactContext.packageName))

        NaverIdLoginSDK.initialize(
            context ?: reactContext,
            consumerKey ?: naverConsumerKey,
            consumerSecret ?: naverConsumerSecret,
            appName ?: naverAppName,
        )
    }

    @ReactMethod
    fun logout(promise: Promise) = UiThreadUtil.runOnUiThread {
        callLogout()
        promise.safeResolve(null)
    }

    private fun callLogout() = try {
        NaverIdLoginSDK::logout
    } catch(e: Throwable) {
        Log.d(name, "callLogout failed: $e")
    }

    @ReactMethod
    fun login(
        consumerKey: String, consumerSecret: String, appName: String, promise: Promise
    ) = UiThreadUtil.runOnUiThread {
        loginPromise = promise
        if (currentActivity == null) {
            onLoginFailure("현재 실행중인 Activity 를 찾을 수 없습니다")
            return@runOnUiThread
        }
        try {
            NaverIdLoginSDK.initialize(
                currentActivity!!,
                consumerKey,
                consumerSecret,
                appName,
            )

            callLogout()
            NaverIdLoginSDK.authenticate(currentActivity!!, object : OAuthLoginCallback {
                override fun onSuccess() {
                    onLoginSuccess()
                }

                override fun onFailure(httpStatus: Int, message: String) {
                    onLoginFailure(message)
                }

                override fun onError(errorCode: Int, message: String) {
                    onLoginFailure(message)
                }
            })
        } catch (je: Exception) {
            onLoginFailure(je.localizedMessage)
        }
    }

    @ReactMethod
    fun deleteToken(promise: Promise) = UiThreadUtil.runOnUiThread {
        NidOAuthLogin().callDeleteTokenApi(currentActivity!!, object : OAuthLoginCallback {
            override fun onSuccess() = promise.safeResolve(null)
            override fun onFailure(httpStatus: Int, message: String) = promise.safeReject(message, message)
            override fun onError(errorCode: Int, message: String) = promise.safeReject(message, message)
        })
    }

    companion object {
        private var loginPromise: Promise? = null

        private fun onLoginSuccess() = loginPromise?.run {
            safeResolve(createLoginSuccessResponse())
            loginPromise = null
        }

        private fun onLoginFailure(message: String?) = loginPromise?.run {
            safeResolve(createLoginFailureResponse(message))
            loginPromise = null
        }

        private fun createLoginSuccessResponse() = Arguments.createMap().apply {
            putBoolean("isSuccess", true)
            putMap("successResponse", Arguments.createMap().apply {
                putString("accessToken", NaverIdLoginSDK.getAccessToken())
                putString("refreshToken", NaverIdLoginSDK.getRefreshToken())
                putString("expiresAtUnixSecondString", NaverIdLoginSDK.getExpiresAt().toString())
                putString("tokenType", NaverIdLoginSDK.getTokenType())
            })
        }

        private fun createLoginFailureResponse(additionalMessage: String?) = Arguments.createMap().apply {
            putBoolean("isSuccess", false)
            putMap("failureResponse", Arguments.createMap().apply {

                val (errorCode, errorDescription) = try {
                    NaverIdLoginSDK.getLastErrorCode().code to NaverIdLoginSDK.getLastErrorDescription()
                } catch (e: Exception) {
                    val errorMessage =
                        "failed to call NaverIdLoginSDK.getLastErrorCode() or NaverIdLoginSDK.getLastErrordescription()"
                    errorMessage to errorMessage
                }

                val isCancel =
                    errorCode == NidOAuthErrorCode.CLIENT_USER_CANCEL.code || (errorCode == "access_denied" && errorDescription == "Canceled By User")

                putString("message", additionalMessage ?: "알 수 없는 에러입니다")
                putString("lastErrorCodeFromNaverSDK", errorCode)
                putString("lastErrorDescriptionFromNaverSDK", errorDescription)
                putBoolean("isCancel", isCancel)
            })
        }
    }
}