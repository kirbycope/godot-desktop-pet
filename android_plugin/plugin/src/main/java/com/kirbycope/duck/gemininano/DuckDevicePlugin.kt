package com.kirbycope.duck.gemininano

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * What the phone itself says about how it is doing, for the duck's model metrics: the app's memory,
 * the memory left, and how warm the phone is, since a hot phone slows its own chips down.
 */
class DuckDevicePlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "DuckDevice"

    /**
     * As JSON: pss_mb (this app's memory), avail_mb and total_mb (the phone's), low_memory,
     * battery_c (the battery's temperature), battery_pct, and thermal (0 none to 6 shutdown).
     */
    @UsedByGodot
    fun stats(): String {
        val context: Context = activity ?: return "{}"
        val memory = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val battery: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val stats = JSONObject()
            .put("pss_mb", Debug.getPss() / 1024)
            .put("avail_mb", memory.availMem / 1048576)
            .put("total_mb", memory.totalMem / 1048576)
            .put("low_memory", memory.lowMemory)
        if (battery != null) {
            stats.put("battery_c", battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0)
            val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (level >= 0) stats.put("battery_pct", level * 100 / scale)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stats.put("thermal", (context.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus)
        }
        return stats.toString()
    }

    /** The phone's name and chip, for telling one set of metrics from another. */
    @UsedByGodot
    fun device(): String {
        val device = JSONObject()
            .put("model", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("android", Build.VERSION.RELEASE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            device.put("soc", "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}")
        }
        return device.toString()
    }

    /** Asks the Java side to give back what it can, between one model and the next. */
    @UsedByGodot
    fun trim() {
        System.gc()
        Runtime.getRuntime().gc()
    }
}
