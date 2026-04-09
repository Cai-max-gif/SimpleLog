package com.SimpleLog.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class BeeCountWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val TAG = "BeeCountWidget"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        Log.d(TAG, "onUpdate called for ${appWidgetIds.size} widgets")
        appWidgetIds.forEach { widgetId ->
            Log.d(TAG, "Updating widget $widgetId")

            val views = RemoteViews(context.packageName, R.layout.beecount_widget).apply {
                // Load the rendered widget image
                val imagePath = widgetData.getString("widgetImage", null)
                Log.d(TAG, "Image path from SharedPreferences: $imagePath")

                if (imagePath != null) {
                    val file = File(imagePath)
                    Log.d(TAG, "File exists: ${file.exists()}, size: ${if(file.exists()) file.length() else 0}")

                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap != null) {
                        Log.d(TAG, "Bitmap decoded successfully: ${bitmap.width}x${bitmap.height}")
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    } else {
                        Log.e(TAG, "Failed to decode bitmap from file")
                        setImageViewResource(R.id.widget_image, R.mipmap.ic_launcher)
                    }
                } else {
                    Log.w(TAG, "No image path in SharedPreferences, showing placeholder")
                    setImageViewResource(R.id.widget_image, R.mipmap.ic_launcher)
                }

                // Set click action to open app
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { intent ->
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    val pendingIntent = PendingIntent.getActivity(
                        context,
                        widgetId,
                        intent,
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        } else {
                            PendingIntent.FLAG_UPDATE_CURRENT
                        }
                    )
                    setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
