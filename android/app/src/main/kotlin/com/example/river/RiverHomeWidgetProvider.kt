package com.example.river

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class RiverHomeWidgetProvider : HomeWidgetProvider() {

    private enum class WidgetSize {
        SMALL,
        MEDIUM,
        LARGE,
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateSingleWidget(
                context = context,
                appWidgetManager = appWidgetManager,
                appWidgetId = appWidgetId,
                widgetData = widgetData,
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateSingleWidget(
            context = context,
            appWidgetManager = appWidgetManager,
            appWidgetId = appWidgetId,
            widgetData = HomeWidgetPlugin.getData(context),
        )
    }

    private fun updateSingleWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
    ) {
        try {
            val size = resolveWidgetSize(appWidgetManager, appWidgetId)
            val layoutId = when (size) {
                WidgetSize.SMALL -> R.layout.river_home_widget_small
                WidgetSize.MEDIUM -> R.layout.river_home_widget_medium
                WidgetSize.LARGE -> R.layout.river_home_widget_large
            }
            val views = RemoteViews(context.packageName, layoutId)

            val state = widgetData.getString(KEY_STATE, "empty") ?: "empty"
            val feedName = widgetData.getString(KEY_FEED, "latestReplied") ?: "latestReplied"
            val feedLabel = widgetData.getString(KEY_FEED_LABEL, "最新回复") ?: "最新回复"
            val title = widgetData.getString(KEY_TITLE, "暂无可展示帖子") ?: "暂无可展示帖子"
            val excerpt = widgetData.getString(KEY_EXCERPT, "打开聚河畔刷新后重试") ?: "打开聚河畔刷新后重试"
            val meta = widgetData.getString(KEY_META, "河畔小组件") ?: "河畔小组件"
            val replies = readInt(widgetData, KEY_REPLIES, 0)
            val viewsCount = readInt(widgetData, KEY_VIEWS, 0)
            val topicId = readInt(widgetData, KEY_TOPIC_ID, 0)
            val accent = readInt(widgetData, KEY_ACCENT, DEFAULT_ACCENT)

            val effectiveAccent = when (state) {
                "error" -> COLOR_ERROR
                else -> accent
            }

            views.setTextViewText(R.id.river_widget_feed, feedLabel)
            views.setTextViewText(R.id.river_widget_title, title)
            views.setTextViewText(R.id.river_widget_excerpt, excerpt)
            views.setTextViewText(R.id.river_widget_meta, meta)
            views.setTextViewText(R.id.river_widget_replies, "回复 $replies")
            views.setTextViewText(R.id.river_widget_views, "浏览 $viewsCount")

            views.setTextColor(R.id.river_widget_feed, effectiveAccent)
            views.setInt(R.id.river_widget_accent, "setBackgroundColor", effectiveAccent)
            views.setInt(
                R.id.river_widget_feed,
                "setBackgroundResource",
                R.drawable.river_widget_chip_background,
            )

            if (size == WidgetSize.SMALL) {
                views.setViewVisibility(R.id.river_widget_excerpt, View.GONE)
                views.setViewVisibility(R.id.river_widget_views, View.GONE)
            } else {
                views.setViewVisibility(R.id.river_widget_excerpt, View.VISIBLE)
                views.setViewVisibility(R.id.river_widget_views, View.VISIBLE)
                val maxLines = if (size == WidgetSize.LARGE) 4 else 3
                views.setInt(R.id.river_widget_excerpt, "setMaxLines", maxLines)
            }

            if (state == "error") {
                views.setTextViewText(R.id.river_widget_meta, "同步失败 · 点击重试")
            }

            val openTopicUri = if (topicId > 0) {
                Uri.parse("river://widget/topic/$topicId?feed=$feedName")
            } else {
                Uri.parse("river://widget/feed/$feedName")
            }
            val openFeedUri = Uri.parse("river://widget/feed/$feedName")

            val rootPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                openTopicUri,
            )
            val feedPendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                openFeedUri,
            )

            views.setOnClickPendingIntent(R.id.river_widget_root, rootPendingIntent)
            views.setOnClickPendingIntent(R.id.river_widget_feed, feedPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (_: Throwable) {
            val fallback = RemoteViews(context.packageName, R.layout.river_home_widget_small)
            fallback.setTextViewText(R.id.river_widget_feed, "最新回复")
            fallback.setTextViewText(R.id.river_widget_title, "小组件加载失败")
            fallback.setTextViewText(R.id.river_widget_meta, "点击打开应用重试")
            fallback.setTextViewText(R.id.river_widget_excerpt, "请稍后再试")
            fallback.setTextViewText(R.id.river_widget_replies, "回复 0")
            fallback.setTextViewText(R.id.river_widget_views, "浏览 0")
            appWidgetManager.updateAppWidget(appWidgetId, fallback)
        }
    }

    private fun resolveWidgetSize(
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): WidgetSize {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        return when {
            minWidth >= 250 && minHeight >= 190 -> WidgetSize.LARGE
            minWidth >= 180 || minHeight >= 150 -> WidgetSize.MEDIUM
            else -> WidgetSize.SMALL
        }
    }

    private companion object {
        const val KEY_STATE = "river_widget_state"
        const val KEY_FEED = "river_widget_feed"
        const val KEY_FEED_LABEL = "river_widget_feed_label"
        const val KEY_TITLE = "river_widget_title"
        const val KEY_EXCERPT = "river_widget_excerpt"
        const val KEY_META = "river_widget_meta"
        const val KEY_REPLIES = "river_widget_replies"
        const val KEY_VIEWS = "river_widget_views"
        const val KEY_TOPIC_ID = "river_widget_topic_id"
        const val KEY_ACCENT = "river_widget_accent"

        const val DEFAULT_ACCENT = -15448746
        const val COLOR_ERROR = -28099
    }

    private fun readInt(
        widgetData: SharedPreferences,
        key: String,
        defaultValue: Int,
    ): Int {
        val raw = widgetData.all[key] ?: return defaultValue
        return when (raw) {
            is Int -> raw
            is Long -> raw.toInt()
            is Float -> raw.toInt()
            is Double -> raw.toInt()
            is String -> raw.toIntOrNull() ?: defaultValue
            else -> defaultValue
        }
    }
}
