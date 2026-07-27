package com.agentusagebar.android

import android.app.Application
import com.agentusagebar.android.data.repository.UsageRepository
import com.agentusagebar.android.worker.UsageRefreshScheduler

class AgentUsageBarApp : Application() {
    lateinit var repository: UsageRepository
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        repository = UsageRepository(this)
        UsageRefreshScheduler.ensureScheduled(this)
    }

    companion object {
        lateinit var instance: AgentUsageBarApp
            private set
    }
}
