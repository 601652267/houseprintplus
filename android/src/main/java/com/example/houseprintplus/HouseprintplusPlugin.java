package com.example.houseprintplus;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Plugin entrypoint that wires Flutter channels to the Bluetooth and print managers.
 */
public class HouseprintplusPlugin implements
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

  private static final String METHOD_CHANNEL_NAME = "houseprintplus";
  private static final String EVENT_CHANNEL_NAME = "houseprintplus/status";

  private MethodChannel channel;
  private EventChannel eventChannel;
  private EventChannel.EventSink eventSink;
  private HouseprintBluetoothManager bluetoothManager;
  private HouseprintPrintManager printManager;
  private ActivityPluginBinding activityBinding;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), METHOD_CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), EVENT_CHANNEL_NAME);
    eventChannel.setStreamHandler(this);

    bluetoothManager = new HouseprintBluetoothManager(flutterPluginBinding.getApplicationContext(), this::emitStatus);
    printManager = new HouseprintPrintManager(bluetoothManager.getPrintApi(), bluetoothManager, this::emitStatus);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    try {
      switch (call.method) {
        case "getPlatformVersion":
          result.success("Android " + android.os.Build.VERSION.RELEASE);
          return;
        case "startBluetoothDiscovery":
          bluetoothManager.startDiscovery(call.argument("namePrefix"));
          result.success(null);
          return;
        case "stopBluetoothDiscovery":
          bluetoothManager.stopDiscovery();
          result.success(null);
          return;
        case "connectBluetoothPrinter":
          String address = call.argument("address");
          if (address == null || address.trim().isEmpty()) {
            result.error("invalid_argument", "Bluetooth address is required.", null);
            return;
          }
          bluetoothManager.connectPrinter(address);
          result.success(null);
          return;
        case "disconnectBluetoothPrinter":
          bluetoothManager.disconnectPrinter();
          result.success(null);
          return;
        case "getBluetoothState":
          result.success(bluetoothManager.getCurrentStatus());
          return;
        case "getPrintState":
          result.success(printManager.getCurrentStatus());
          return;
        case "printQrLabel":
          String qrContent = call.argument("qrContent");
          String title = call.argument("title");
          String subtitle = call.argument("subtitle");
          if (qrContent == null) {
            result.error("invalid_argument", "qrContent is required.", null);
            return;
          }
          if (title == null) {
            result.error("invalid_argument", "title is required.", null);
            return;
          }
          if (subtitle == null) {
            result.error("invalid_argument", "subtitle is required.", null);
            return;
          }

          double labelWidthMm = getDoubleArgument(call, "labelWidthMm", 50.0d);
          double labelHeightMm = getDoubleArgument(call, "labelHeightMm", 30.0d);
          Double titleFontSizeMm = getNullableDoubleArgument(call, "titleFontSizeMm");
          Double subtitleFontSizeMm = getNullableDoubleArgument(call, "subtitleFontSizeMm");
          printManager.printQrLabel(
              qrContent,
              title,
              subtitle,
              labelWidthMm,
              labelHeightMm,
              titleFontSizeMm,
              subtitleFontSizeMm
          );
          result.success(null);
          return;
        case "printQrTitleCenteredLabel":
          String centeredQrContent = call.argument("qrContent");
          String centeredTitle = call.argument("title");
          if (centeredQrContent == null) {
            result.error("invalid_argument", "qrContent is required.", null);
            return;
          }
          if (centeredTitle == null) {
            result.error("invalid_argument", "title is required.", null);
            return;
          }

          double centeredLabelWidthMm = getDoubleArgument(call, "labelWidthMm", 50.0d);
          double centeredLabelHeightMm = getDoubleArgument(call, "labelHeightMm", 30.0d);
          Double centeredTitleFontSizeMm = getNullableDoubleArgument(call, "titleFontSizeMm");
          printManager.printQrTitleCenteredLabel(
              centeredQrContent,
              centeredTitle,
              centeredLabelWidthMm,
              centeredLabelHeightMm,
              centeredTitleFontSizeMm
          );
          result.success(null);
          return;
        case "cancelPrintJob":
          result.success(printManager.cancelPrintJob());
          return;
        default:
          result.notImplemented();
      }
    } catch (IllegalArgumentException | IllegalStateException exception) {
      result.error("houseprintplus_error", exception.getMessage(), null);
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (activityBinding != null) {
      activityBinding.removeRequestPermissionsResultListener(this);
      activityBinding = null;
    }
    if (bluetoothManager != null) {
      bluetoothManager.dispose();
      bluetoothManager = null;
    }
    if (printManager != null) {
      printManager.dispose();
      printManager = null;
    }
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    if (eventChannel != null) {
      eventChannel.setStreamHandler(null);
      eventChannel = null;
    }
    eventSink = null;
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    eventSink = events;
    if (bluetoothManager != null) {
      emitStatus(bluetoothManager.getCurrentStatus());
    }
    if (printManager != null) {
      emitStatus(printManager.getCurrentStatus());
    }
  }

  @Override
  public void onCancel(Object arguments) {
    eventSink = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;
    binding.addRequestPermissionsResultListener(this);
    if (bluetoothManager != null) {
      bluetoothManager.setActivity(binding.getActivity());
    }
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    detachFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    detachFromActivity();
  }

  @Override
  public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
    return bluetoothManager != null && bluetoothManager.onRequestPermissionsResult(requestCode, permissions, grantResults);
  }

  private void detachFromActivity() {
    if (activityBinding != null) {
      activityBinding.removeRequestPermissionsResultListener(this);
      activityBinding = null;
    }
    if (bluetoothManager != null) {
      bluetoothManager.setActivity(null);
    }
  }

  private double getDoubleArgument(@NonNull MethodCall call, @NonNull String key, double fallbackValue) {
    Number value = call.argument(key);
    return value == null ? fallbackValue : value.doubleValue();
  }

  private Double getNullableDoubleArgument(@NonNull MethodCall call, @NonNull String key) {
    Number value = call.argument(key);
    return value == null ? null : value.doubleValue();
  }

  private void emitStatus(@NonNull Map<String, Object> status) {
    EventChannel.EventSink sink = eventSink;
    if (sink == null) {
      return;
    }

    Map<String, Object> safeStatus = new HashMap<>(status);
    sink.success(safeStatus);
  }
}
