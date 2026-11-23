package com.fitconnect.fit_connect_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// health プラグインが Health Connect の権限リクエストに registerForActivityResult を使い、
// ComponentActivity を要求するため。FlutterActivity に戻すと権限リクエストが開かなくなる
class MainActivity : FlutterFragmentActivity()
