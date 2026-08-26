package com.goodusestudios.weldinggaswallet

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import com.goodusestudios.weldinggaswallet.ui.WalletApp
import java.util.Locale

class MainActivity : ComponentActivity() {
    private lateinit var graph: WalletAppGraph
    private val viewModel: WalletViewModel by viewModels { WalletViewModel.Factory(graph) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = WalletAppGraph(
            context = applicationContext,
            activityProvider = { this },
            initialLocale = Locale.getDefault().toLanguageTag(),
        )
        setContent {
            val notificationPermissionLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestPermission()
            ) { viewModel.onResume() }
            WalletApp(
                viewModel = viewModel,
                requestNotificationPermission = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                },
            )
        }
    }

    override fun onResume() {
        super.onResume()
        if (::graph.isInitialized) viewModel.onResume()
    }
}
