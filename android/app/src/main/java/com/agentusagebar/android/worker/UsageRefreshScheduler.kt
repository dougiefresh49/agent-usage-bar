package com.agentusagebar.android.worker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.agentusagebar.android.AgentUsageBarApp
import com.agentusagebar.android.data.credentials.SettingsStore
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit

class UsageRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        return try {
            AgentUsageBarApp.instance.repository.refreshAll()
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }
}

object UsageRefreshScheduler {
    private const val UNIQUE_WORK = "usage_refresh_periodic"

    fun ensureScheduled(context: Context, forceReschedule: Boolean = false) {
        val appContext = context.applicationContext
        // WorkManager minimum periodic interval is 15 minutes.
        val request = PeriodicWorkRequestBuilder<UsageRefreshWorker>(15, TimeUnit.MINUTES)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .build()

        WorkManager.getInstance(appContext).enqueueUniquePeriodicWork(
            UNIQUE_WORK,
            if (forceReschedule) ExistingPeriodicWorkPolicy.UPDATE else ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    suspend fun currentPollingMinutes(context: Context): Int {
        return SettingsStore(context).settings.first().pollingMinutes
    }
}

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            UsageRefreshScheduler.ensureScheduled(context, forceReschedule = true)
        }
    }
}
