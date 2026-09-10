package com.agentusagebar.android

import android.app.Application
import com.agentusagebar.android.data.credentials.SettingsStore
import com.agentusagebar.android.data.repository.UsageRepository
import com.agentusagebar.android.worker.UsageRefreshScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AgentUsageBarApp : Application() {
    lateinit var repository: UsageRepository
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        val settingsStore = SettingsStore(this)
        repository = UsageRepository(this, settingsStore = settingsStore)
        UsageRefreshScheduler.ensureScheduled(this)
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            settingsStore.wipeLegacyCredentialsOnce()
        }
    }

    companion object {
        lateinit var instance: AgentUsageBarApp
            private set
    }
}
