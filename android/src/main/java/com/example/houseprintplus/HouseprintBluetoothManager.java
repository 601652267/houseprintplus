package com.example.houseprintplus;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Application;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.gengcon.www.jcprintersdk.JCPrintApi;
import com.gengcon.www.jcprintersdk.callback.Callback;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Handles Bluetooth discovery, pairing and printer connection state.
 *
 * <p>The plugin keeps Bluetooth responsibilities in a dedicated manager so the
 * Flutter plugin entrypoint stays small and focused on channel dispatching.
 */
public class HouseprintBluetoothManager {
    private static final int BLUETOOTH_PERMISSION_REQUEST_CODE = 41041;

    /**
     * Emits structured status updates back to the plugin entrypoint.
     */
    public interface StatusCallback {
        void onStatusChanged(@NonNull Map<String, Object> status);
    }

    /**
     * Snapshot of the connected printer's print related defaults.
     *
     * <p>These values are derived from the demo project so printing can keep the
     * same density / mode defaults for known models.
     */
    public static final class PrinterSettings {
        private final int printMode;
        private final int printDensity;
        private final float printMultiple;

        PrinterSettings(int printMode, int printDensity, float printMultiple) {
            this.printMode = printMode;
            this.printDensity = printDensity;
            this.printMultiple = printMultiple;
        }

        public int getPrintMode() {
            return printMode;
        }

        public int getPrintDensity() {
            return printDensity;
        }

        public float getPrintMultiple() {
            return printMultiple;
        }
    }

    private enum PendingPermissionAction {
        NONE,
        START_DISCOVERY,
        CONNECT
    }

    private final Context applicationContext;
    private final StatusCallback statusCallback;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executorService = Executors.newSingleThreadExecutor();
    private final Set<String> discoveredAddresses = new HashSet<>();
    private final Object stateLock = new Object();
    private final BluetoothAdapter bluetoothAdapter;
    private final Callback sdkCallback = new Callback() {
        @Override
        public void onConnectSuccess(String address, int type) {
            connectedType = type;
            if (type != 0) {
                return;
            }

            BluetoothDevice device = currentConnectedDevice;
            if (device == null && bluetoothAdapter != null) {
                try {
                    device = bluetoothAdapter.getRemoteDevice(address);
                } catch (IllegalArgumentException ignored) {
                    device = null;
                }
            }

            if (device != null && !address.equals(getDeviceAddress(currentConnectedDevice))) {
                updateConnectedPrinter(device);
                emitBluetoothStatus("connected", "Bluetooth printer connected.", buildBluetoothPayload(device));
            }
        }

        @Override
        public void onDisConnect() {
            clearConnection("Printer disconnected.");
        }

        @Override
        public void onElectricityChange(int powerLevel) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("powerLevel", powerLevel);
            emitBluetoothStatus("powerChanged", "Printer power level changed.", payload);
        }

        @Override
        public void onCoverStatus(int coverStatus) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("coverStatus", coverStatus);
            emitBluetoothStatus("coverStatusChanged", "Printer cover status changed.", payload);
        }

        @Override
        public void onPaperStatus(int paperStatus) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("paperStatus", paperStatus);
            emitBluetoothStatus("paperStatusChanged", "Printer paper status changed.", payload);
        }

        @Override
        public void onRfidReadStatus(int rfidReadStatus) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("rfidReadStatus", rfidReadStatus);
            emitBluetoothStatus("rfidStatusChanged", "Printer label RFID status changed.", payload);
        }

        @Override
        public void onRibbonRfidReadStatus(int ribbonRfidReadStatus) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("ribbonRfidReadStatus", ribbonRfidReadStatus);
            emitBluetoothStatus("ribbonRfidStatusChanged", "Printer ribbon RFID status changed.", payload);
        }

        @Override
        public void onRibbonStatus(int ribbonStatus) {
            Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
            payload.put("ribbonStatus", ribbonStatus);
            emitBluetoothStatus("ribbonStatusChanged", "Printer ribbon status changed.", payload);
        }

        @Override
        public void onFirmErrors() {
            emitBluetoothStatus("firmwareError", "Printer firmware reported an error.", buildBluetoothPayload(currentConnectedDevice));
        }
    };
    private final BroadcastReceiver bluetoothReceiver = new BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent == null) {
                return;
            }

            String action = intent.getAction();
            if (BluetoothAdapter.ACTION_DISCOVERY_STARTED.equals(action)) {
                emitBluetoothStatus("scanning", "Bluetooth discovery started.", buildBluetoothPayload(currentConnectedDevice));
                return;
            }

            if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                emitBluetoothStatus("scanFinished", "Bluetooth discovery finished.", buildBluetoothPayload(currentConnectedDevice));
                return;
            }

            if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                handleDeviceFound(device);
                return;
            }

            if (BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(action)) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                int bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR);
                int previousBondState = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.ERROR);
                handleBondStateChanged(device, bondState, previousBondState);
                return;
            }

            if (BluetoothDevice.ACTION_PAIRING_REQUEST.equals(action)) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                emitBluetoothStatus("pairingRequested", "System pairing dialog was shown.", buildBluetoothPayload(device));
                return;
            }

            if (BluetoothDevice.ACTION_ACL_DISCONNECTED.equals(action)) {
                BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                if (device != null && TextUtils.equals(getDeviceAddress(device), getDeviceAddress(currentConnectedDevice))) {
                    clearConnection("Bluetooth printer disconnected.");
                }
            }
        }
    };

    private JCPrintApi printApi;
    private Activity activity;
    private boolean sdkInitialized;
    private boolean receiverRegistered;
    private PendingPermissionAction pendingPermissionAction = PendingPermissionAction.NONE;
    private String pendingNamePrefix = "";
    private String pendingConnectAddress;
    private String bluetoothState = "idle";
    private String bluetoothMessage = "Bluetooth manager is ready.";
    private Map<String, Object> bluetoothPayload = new HashMap<>();
    private BluetoothDevice currentConnectedDevice;
    private PrinterSettings currentPrinterSettings = new PrinterSettings(1, 3, 8.0f);
    private int connectedType = -1;

    public HouseprintBluetoothManager(@NonNull Context applicationContext, @NonNull StatusCallback statusCallback) {
        this.applicationContext = applicationContext.getApplicationContext();
        this.statusCallback = statusCallback;
        this.bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        initSdk();
        registerReceiver();

        if (bluetoothAdapter == null) {
            emitBluetoothStatus("error", "Bluetooth is not supported on this device.", buildBluetoothPayload(null));
        } else if (!sdkInitialized) {
            emitBluetoothStatus("error", "Printer SDK initialization failed.", buildBluetoothPayload(null));
        } else {
            emitBluetoothStatus("idle", "Bluetooth manager is ready.", buildBluetoothPayload(null));
        }
    }

    /**
     * Updates the current host activity used for runtime permission requests.
     */
    public void setActivity(@Nullable Activity activity) {
        this.activity = activity;
    }

    /**
     * Starts Bluetooth discovery and emits every matching device through the status stream.
     */
    public void startDiscovery(@Nullable String namePrefix) {
        ensureBluetoothReady();

        if (!bluetoothAdapter.isEnabled()) {
            emitBluetoothStatus("bluetoothDisabled", "Bluetooth is turned off.", buildBluetoothPayload(currentConnectedDevice));
            throw new IllegalStateException("Bluetooth is turned off.");
        }

        String normalizedPrefix = normalizePrefix(namePrefix);
        if (requestPermissionsIfNeeded(PendingPermissionAction.START_DISCOVERY, normalizedPrefix, null)) {
            return;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && !isLocationServiceEnabled()) {
            emitBluetoothStatus("gpsDisabled", "Location service is required for Bluetooth discovery on this Android version.", buildBluetoothPayload(currentConnectedDevice));
            throw new IllegalStateException("Location service is disabled.");
        }

        executorService.execute(() -> startDiscoveryInternal(normalizedPrefix));
    }

    /**
     * Stops discovery if there is an active scan.
     */
    public void stopDiscovery() {
        if (bluetoothAdapter != null && bluetoothAdapter.isDiscovering()) {
            bluetoothAdapter.cancelDiscovery();
            emitBluetoothStatus("scanStopped", "Bluetooth discovery stopped.", buildBluetoothPayload(currentConnectedDevice));
        }
    }

    /**
     * Connects to a Bluetooth printer by MAC address.
     *
     * <p>If the printer is not paired yet the manager starts pairing first and
     * automatically continues with connection once the bond is complete.
     */
    public void connectPrinter(@NonNull String address) {
        ensureBluetoothReady();

        if (TextUtils.isEmpty(address)) {
            throw new IllegalArgumentException("Bluetooth address cannot be empty.");
        }

        if (!bluetoothAdapter.isEnabled()) {
            emitBluetoothStatus("bluetoothDisabled", "Bluetooth is turned off.", buildBluetoothPayload(currentConnectedDevice));
            throw new IllegalStateException("Bluetooth is turned off.");
        }

        if (requestPermissionsIfNeeded(PendingPermissionAction.CONNECT, null, address)) {
            return;
        }

        pendingConnectAddress = address;
        executorService.execute(() -> connectOrPair(address));
    }

    /**
     * Disconnects the current printer connection.
     */
    public void disconnectPrinter() {
        if (!sdkInitialized) {
            return;
        }
        stopDiscovery();
        printApi.close();
        clearConnection("Printer disconnected by request.");
    }

    /**
     * Returns the shared SDK instance so the print manager can reuse the same connection.
     */
    @NonNull
    public JCPrintApi getPrintApi() {
        return printApi;
    }

    /**
     * Returns the latest printer settings derived from the connected printer.
     */
    @NonNull
    public PrinterSettings getCurrentPrinterSettings() {
        return currentPrinterSettings;
    }

    /**
     * Returns whether a Bluetooth printer is currently connected.
     */
    public boolean isConnected() {
        return sdkInitialized && connectedType == 0 && printApi.isConnection() == 0;
    }

    /**
     * Returns the latest structured Bluetooth state snapshot.
     */
    @NonNull
    public Map<String, Object> getCurrentStatus() {
        synchronized (stateLock) {
            Map<String, Object> status = new HashMap<>();
            status.put("type", "bluetooth");
            status.put("state", bluetoothState);
            status.put("message", bluetoothMessage);
            status.put("payload", new HashMap<>(bluetoothPayload));
            return status;
        }
    }

    /**
     * Handles runtime permission results delegated by the plugin entrypoint.
     */
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != BLUETOOTH_PERMISSION_REQUEST_CODE) {
            return false;
        }

        boolean granted = true;
        for (int grantResult : grantResults) {
            if (grantResult != PackageManager.PERMISSION_GRANTED) {
                granted = false;
                break;
            }
        }

        PendingPermissionAction action = pendingPermissionAction;
        String namePrefix = pendingNamePrefix;
        String address = pendingConnectAddress;
        clearPendingPermissionAction();

        if (!granted) {
            emitBluetoothStatus("permissionDenied", "Bluetooth permission was denied.", buildBluetoothPayload(currentConnectedDevice));
            return true;
        }

        if (action == PendingPermissionAction.START_DISCOVERY) {
            startDiscovery(namePrefix);
        } else if (action == PendingPermissionAction.CONNECT && address != null) {
            connectPrinter(address);
        }

        return true;
    }

    /**
     * Releases receivers and background workers when the plugin is detached.
     */
    public void dispose() {
        stopDiscovery();
        if (receiverRegistered) {
            applicationContext.unregisterReceiver(bluetoothReceiver);
            receiverRegistered = false;
        }
        executorService.shutdownNow();
    }

    private void initSdk() {
        printApi = JCPrintApi.getInstance(sdkCallback);
        if (applicationContext instanceof Application) {
            sdkInitialized = printApi.initSdk((Application) applicationContext);
        } else {
            sdkInitialized = false;
        }
    }

    private void registerReceiver() {
        if (receiverRegistered) {
            return;
        }

        IntentFilter filter = new IntentFilter();
        filter.addAction(BluetoothDevice.ACTION_FOUND);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED);
        filter.addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
        filter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        filter.addAction(BluetoothDevice.ACTION_PAIRING_REQUEST);
        filter.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED);
        applicationContext.registerReceiver(bluetoothReceiver, filter);
        receiverRegistered = true;
    }

    private void ensureBluetoothReady() {
        if (bluetoothAdapter == null) {
            emitBluetoothStatus("error", "Bluetooth is not supported on this device.", buildBluetoothPayload(null));
            throw new IllegalStateException("Bluetooth is not supported on this device.");
        }

        if (!sdkInitialized) {
            emitBluetoothStatus("error", "Printer SDK initialization failed.", buildBluetoothPayload(null));
            throw new IllegalStateException("Printer SDK initialization failed.");
        }
    }

    private void clearPendingPermissionAction() {
        pendingPermissionAction = PendingPermissionAction.NONE;
        pendingNamePrefix = "";
        pendingConnectAddress = null;
    }

    private boolean requestPermissionsIfNeeded(
            @NonNull PendingPermissionAction action,
            @Nullable String namePrefix,
            @Nullable String address
    ) {
        String[] permissions = getRequiredPermissions(action);
        if (permissions.length == 0) {
            return false;
        }

        Set<String> missingPermissions = new HashSet<>();
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(applicationContext, permission) != PackageManager.PERMISSION_GRANTED) {
                missingPermissions.add(permission);
            }
        }

        if (missingPermissions.isEmpty()) {
            return false;
        }

        if (activity == null) {
            throw new IllegalStateException("An attached Activity is required to request Bluetooth permissions.");
        }

        pendingPermissionAction = action;
        pendingNamePrefix = namePrefix == null ? "" : namePrefix;
        pendingConnectAddress = address;
        emitBluetoothStatus("permissionRequesting", "Requesting Bluetooth permissions.", buildBluetoothPayload(currentConnectedDevice));
        ActivityCompat.requestPermissions(activity, missingPermissions.toArray(new String[0]), BLUETOOTH_PERMISSION_REQUEST_CODE);
        return true;
    }

    @SuppressLint("MissingPermission")
    private void startDiscoveryInternal(@NonNull String namePrefix) {
        pendingNamePrefix = namePrefix;
        discoveredAddresses.clear();

        if (bluetoothAdapter.isDiscovering()) {
            bluetoothAdapter.cancelDiscovery();
            try {
                Thread.sleep(300L);
            } catch (InterruptedException interruptedException) {
                Thread.currentThread().interrupt();
            }
        }

        boolean started = bluetoothAdapter.startDiscovery();
        if (!started) {
            emitBluetoothStatus("error", "Unable to start Bluetooth discovery.", buildBluetoothPayload(currentConnectedDevice));
        }
    }

    @SuppressLint("MissingPermission")
    private void connectOrPair(@NonNull String address) {
        BluetoothDevice device;
        try {
            device = bluetoothAdapter.getRemoteDevice(address);
        } catch (IllegalArgumentException illegalArgumentException) {
            emitBluetoothStatus("error", "Invalid Bluetooth address: " + address, buildBluetoothPayload(currentConnectedDevice));
            return;
        }

        if (bluetoothAdapter.isDiscovering()) {
            bluetoothAdapter.cancelDiscovery();
        }

        if (isConnected() && TextUtils.equals(address, getDeviceAddress(currentConnectedDevice))) {
            emitBluetoothStatus("connected", "Bluetooth printer is already connected.", buildBluetoothPayload(currentConnectedDevice));
            return;
        }

        if (device.getBondState() != BluetoothDevice.BOND_BONDED) {
            emitBluetoothStatus("pairing", "Pairing with Bluetooth printer.", buildBluetoothPayload(device));
            boolean bondStarted = device.createBond();
            if (!bondStarted) {
                pendingConnectAddress = null;
                emitBluetoothStatus("error", "Failed to start Bluetooth pairing.", buildBluetoothPayload(device));
            }
            return;
        }

        connectBondedDevice(device);
    }

    @SuppressLint("MissingPermission")
    private void connectBondedDevice(@NonNull BluetoothDevice device) {
        emitBluetoothStatus("connecting", "Connecting to Bluetooth printer.", buildBluetoothPayload(device));
        int connectResult = printApi.connectBluetoothPrinter(device.getAddress());
        if (connectResult == 0) {
            updateConnectedPrinter(device);
            emitBluetoothStatus("connected", "Bluetooth printer connected.", buildBluetoothPayload(device));
            return;
        }

        pendingConnectAddress = null;
        String message = connectResult == -2 ? "Unsupported printer model." : "Failed to connect to Bluetooth printer.";
        Map<String, Object> payload = buildBluetoothPayload(device);
        payload.put("connectResult", connectResult);
        emitBluetoothStatus("error", message, payload);
    }

    @SuppressLint("MissingPermission")
    private void handleDeviceFound(@Nullable BluetoothDevice device) {
        if (device == null) {
            return;
        }

        String deviceName = device.getName();
        String deviceAddress = device.getAddress();
        int deviceType = device.getType();
        boolean supportedType = deviceType == BluetoothDevice.DEVICE_TYPE_CLASSIC
                || deviceType == BluetoothDevice.DEVICE_TYPE_DUAL;

        if (!supportedType || TextUtils.isEmpty(deviceName) || TextUtils.isEmpty(deviceAddress)) {
            return;
        }

        if (!supportsNamePrefix(deviceName, pendingNamePrefix)) {
            return;
        }

        if (!discoveredAddresses.add(deviceAddress)) {
            return;
        }

        Map<String, Object> payload = buildBluetoothPayload(device);
        payload.put("discovered", true);
        emitBluetoothStatus("deviceFound", "Bluetooth printer discovered.", payload);
    }

    private void handleBondStateChanged(@Nullable BluetoothDevice device, int bondState, int previousBondState) {
        if (device == null) {
            return;
        }

        String deviceAddress = getDeviceAddress(device);
        if (!TextUtils.equals(deviceAddress, pendingConnectAddress)) {
            return;
        }

        Map<String, Object> payload = buildBluetoothPayload(device);
        payload.put("previousBondState", previousBondState);

        if (bondState == BluetoothDevice.BOND_BONDING) {
            emitBluetoothStatus("pairing", "Bluetooth pairing in progress.", payload);
            return;
        }

        if (bondState == BluetoothDevice.BOND_BONDED) {
            emitBluetoothStatus("paired", "Bluetooth pairing completed.", payload);
            executorService.execute(() -> connectBondedDevice(device));
            return;
        }

        if (bondState == BluetoothDevice.BOND_NONE && previousBondState == BluetoothDevice.BOND_BONDING) {
            pendingConnectAddress = null;
            emitBluetoothStatus("error", "Bluetooth pairing failed or was cancelled.", payload);
        }
    }

    private boolean isLocationServiceEnabled() {
        LocationManager locationManager = (LocationManager) applicationContext.getSystemService(Context.LOCATION_SERVICE);
        if (locationManager == null) {
            return false;
        }

        boolean gpsEnabled = false;
        boolean networkEnabled = false;
        try {
            gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER);
        } catch (Exception ignored) {
            gpsEnabled = false;
        }

        try {
            networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        } catch (Exception ignored) {
            networkEnabled = false;
        }

        return gpsEnabled || networkEnabled;
    }

    private boolean supportsNamePrefix(@NonNull String deviceName, @Nullable String namePrefix) {
        if (TextUtils.isEmpty(namePrefix)) {
            return true;
        }
        return deviceName.startsWith(namePrefix);
    }

    @NonNull
    private String normalizePrefix(@Nullable String rawPrefix) {
        return rawPrefix == null ? "" : rawPrefix.trim();
    }

    @NonNull
    private String[] getRequiredPermissions(@NonNull PendingPermissionAction action) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (action == PendingPermissionAction.CONNECT) {
                return new String[]{Manifest.permission.BLUETOOTH_CONNECT};
            }
            return new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT};
        }

        if (action == PendingPermissionAction.START_DISCOVERY) {
            return new String[]{Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION};
        }

        return new String[0];
    }

    @SuppressLint("MissingPermission")
    private void updateConnectedPrinter(@NonNull BluetoothDevice device) {
        currentConnectedDevice = device;
        currentPrinterSettings = buildPrinterSettings(device.getName());
        connectedType = 0;
        pendingConnectAddress = null;
    }

    private void clearConnection(@NonNull String message) {
        Map<String, Object> payload = buildBluetoothPayload(currentConnectedDevice);
        currentConnectedDevice = null;
        currentPrinterSettings = new PrinterSettings(1, 3, 8.0f);
        connectedType = -1;
        pendingConnectAddress = null;
        emitBluetoothStatus("disconnected", message, payload);
    }

    private PrinterSettings buildPrinterSettings(@Nullable String deviceName) {
        float multiple = printApi.getMultiple();
        if (multiple <= 0f) {
            multiple = inferPrintMultiple(deviceName);
        }

        if (matches(deviceName, "^(B32|Z401|T8).*")) {
            return new PrinterSettings(2, 8, multiple);
        }

        if (matches(deviceName, "^(M2|M3|EP2M).*")) {
            return new PrinterSettings(2, 3, multiple);
        }

        if (matches(deviceName, "^(B21_Pro).*")) {
            return new PrinterSettings(1, 3, multiple);
        }

        return new PrinterSettings(1, 3, multiple);
    }

    private boolean matches(@Nullable String value, @NonNull String pattern) {
        return value != null && value.matches(pattern);
    }

    private float inferPrintMultiple(@Nullable String deviceName) {
        if (matches(deviceName, "^(B32|Z401|T8|M2|M3|EP2M|B21_Pro).*")) {
            return 11.81f;
        }
        return 8.0f;
    }

    @SuppressLint("MissingPermission")
    @NonNull
    private Map<String, Object> buildBluetoothPayload(@Nullable BluetoothDevice device) {
        Map<String, Object> payload = new HashMap<>();
        BluetoothDevice targetDevice = device != null ? device : currentConnectedDevice;

        payload.put("adapterEnabled", bluetoothAdapter != null && bluetoothAdapter.isEnabled());
        payload.put("connected", isConnected());
        payload.put("connectedType", connectedType);
        payload.put("printMode", currentPrinterSettings.getPrintMode());
        payload.put("printDensity", currentPrinterSettings.getPrintDensity());
        payload.put("printMultiple", (double) currentPrinterSettings.getPrintMultiple());

        if (targetDevice != null) {
            payload.put("deviceName", targetDevice.getName());
            payload.put("deviceAddress", targetDevice.getAddress());
            payload.put("bondState", targetDevice.getBondState());
        }

        if (!TextUtils.isEmpty(pendingConnectAddress)) {
            payload.put("pendingConnectAddress", pendingConnectAddress);
        }

        return payload;
    }

    @Nullable
    private String getDeviceAddress(@Nullable BluetoothDevice device) {
        return device == null ? null : device.getAddress();
    }

    private void emitBluetoothStatus(@NonNull String state, @NonNull String message, @NonNull Map<String, Object> payload) {
        synchronized (stateLock) {
            bluetoothState = state;
            bluetoothMessage = message;
            bluetoothPayload = new HashMap<>(payload);
        }

        Map<String, Object> status = new HashMap<>();
        status.put("type", "bluetooth");
        status.put("state", state);
        status.put("message", message);
        status.put("payload", new HashMap<>(payload));

        mainHandler.post(() -> statusCallback.onStatusChanged(status));
    }
}
