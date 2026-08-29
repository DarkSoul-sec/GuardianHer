package com.guardianher.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen launcher widget for the SOS flow.
 *
 * Tapping the widget launches the app (MainActivity) with a
 * `guardianher://sos` URI using home_widget's launch intent. The Flutter side
 * reads that URI via [HomeWidget.initiallyLaunchedFromHomeWidget] /
 * [HomeWidget.widgetClicked] and routes straight to the SOS screen. The widget
 * itself never runs app logic, captures location, or starts background work.
 */
class SosWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.sos_widget).apply {
            val launchIntent =
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("guardianher://sos"),
                )
            setOnClickPendingIntent(R.id.sos_widget_root, launchIntent)
          }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
