package com.fitconnect.fit_connect_mobile

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast

// Health Connect の権限画面で「プライバシーポリシー」を押したときに開かれる画面。
// Android 13 以下は ACTION_SHOW_PERMISSIONS_RATIONALE の intent で、14 以上は
// AndroidManifest.xml の activity-alias（ViewPermissionUsageActivity）からここに入る。
// アプリ（Flutter）は起動せず、ブラウザでプライバシーポリシーを開いてすぐ閉じる
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            // アプリの設定画面・同意ダイアログと同じく、外部のブラウザで開く
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
        } catch (e: ActivityNotFoundException) {
            // ブラウザが無い端末でも落とさない。この画面はすぐ閉じるので、Toast は applicationContext で出す
            Toast.makeText(applicationContext, "プライバシーポリシーを開けませんでした", Toast.LENGTH_SHORT).show()
        }
        finish()
    }

    companion object {
        // lib/features/consent/legal_links.dart の LegalLinks.privacyUrl と同じ値。
        // test/features/consent/health_connect_privacy_policy_test.dart で照合している
        const val PRIVACY_POLICY_URL = "https://fit-connect-xi.vercel.app/privacy"
    }
}
