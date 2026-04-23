package com.example.houseprintplus;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Handler;
import android.os.Looper;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextUtils;
import android.text.TextPaint;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.gengcon.www.jcprintersdk.JCPrintApi;
import com.gengcon.www.jcprintersdk.callback.PrintCallback;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.MultiFormatWriter;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Handles print specific state and layout generation.
 *
 * <p>The requested layout is rendered as a bitmap:
 * left side QR code, right side title and subtitle stacked vertically.
 */
public class HouseprintPrintManager {
    private static final String LAYOUT_QR_WITH_SIDE_TEXT = "qr_side_text";
    private static final String LAYOUT_QR_WITH_CENTERED_TITLE = "qr_centered_title";

    /**
     * Emits structured print status updates back to the plugin entrypoint.
     */
    public interface StatusCallback {
        void onStatusChanged(@NonNull Map<String, Object> status);
    }

    private final JCPrintApi printApi;
    private final HouseprintBluetoothManager bluetoothManager;
    private final StatusCallback statusCallback;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executorService = Executors.newSingleThreadExecutor();
    private final Object stateLock = new Object();
    private final AtomicBoolean printInProgress = new AtomicBoolean(false);

    private String printState = "idle";
    private String printMessage = "Print manager is ready.";
    private Map<String, Object> printPayload = new HashMap<>();

    public HouseprintPrintManager(
            @NonNull JCPrintApi printApi,
            @NonNull HouseprintBluetoothManager bluetoothManager,
            @NonNull StatusCallback statusCallback
    ) {
        this.printApi = printApi;
        this.bluetoothManager = bluetoothManager;
        this.statusCallback = statusCallback;
        emitPrintStatus("idle", "Print manager is ready.", buildPrintPayload(null));
    }

    /**
     * Returns the latest structured print state snapshot.
     */
    @NonNull
    public Map<String, Object> getCurrentStatus() {
        synchronized (stateLock) {
            Map<String, Object> status = new HashMap<>();
            status.put("type", "print");
            status.put("state", printState);
            status.put("message", printMessage);
            status.put("payload", new HashMap<>(printPayload));
            return status;
        }
    }

    /**
     * Starts printing a QR label with a fixed two-column layout.
     */
    public void printQrLabel(
            @NonNull String qrContent,
            @NonNull String title,
            @NonNull String subtitle,
            double labelWidthMm,
            double labelHeightMm,
            Double titleFontSizeMm,
            Double subtitleFontSizeMm
    ) {
        if (TextUtils.isEmpty(qrContent)) {
            throw new IllegalArgumentException("QR content cannot be empty.");
        }

        if (labelWidthMm <= 0 || labelHeightMm <= 0) {
            throw new IllegalArgumentException("Label size must be greater than zero.");
        }

        if (!bluetoothManager.isConnected() || printApi.isConnection() != 0) {
            emitPrintStatus("error", "Printer is not connected.", buildPrintPayload(null));
            throw new IllegalStateException("Printer is not connected.");
        }

        if (!printInProgress.compareAndSet(false, true)) {
            throw new IllegalStateException("Another print job is already running.");
        }

        HouseprintBluetoothManager.PrinterSettings settings = bluetoothManager.getCurrentPrinterSettings();
        executorService.execute(() -> startQrPrint(
                qrContent,
                title,
                subtitle,
                labelWidthMm,
                labelHeightMm,
                titleFontSizeMm,
                subtitleFontSizeMm,
                LAYOUT_QR_WITH_SIDE_TEXT,
                settings
        ));
    }

    /**
     * Starts printing a vertically centered QR + title layout.
     */
    public void printQrTitleCenteredLabel(
            @NonNull String qrContent,
            @NonNull String title,
            double labelWidthMm,
            double labelHeightMm,
            Double titleFontSizeMm
    ) {
        if (TextUtils.isEmpty(qrContent)) {
            throw new IllegalArgumentException("QR content cannot be empty.");
        }

        if (labelWidthMm <= 0 || labelHeightMm <= 0) {
            throw new IllegalArgumentException("Label size must be greater than zero.");
        }

        if (!bluetoothManager.isConnected() || printApi.isConnection() != 0) {
            emitPrintStatus("error", "Printer is not connected.", buildPrintPayload(null));
            throw new IllegalStateException("Printer is not connected.");
        }

        if (!printInProgress.compareAndSet(false, true)) {
            throw new IllegalStateException("Another print job is already running.");
        }

        HouseprintBluetoothManager.PrinterSettings settings = bluetoothManager.getCurrentPrinterSettings();
        executorService.execute(() -> startCenteredQrTitlePrint(
                qrContent,
                title,
                labelWidthMm,
                labelHeightMm,
                titleFontSizeMm,
                settings
        ));
    }

    /**
     * Requests cancellation of the current print job.
     */
    public boolean cancelPrintJob() {
        boolean cancelled = printApi.cancelJob();
        Map<String, Object> payload = buildPrintPayload(null);
        payload.put("cancelRequested", cancelled);
        emitPrintStatus("cancelRequested", cancelled ? "Print cancellation requested." : "Unable to cancel the current print job.", payload);
        return cancelled;
    }

    /**
     * Stops the print worker when the plugin is detached.
     */
    public void dispose() {
        executorService.shutdownNow();
    }

    private void startQrPrint(
            @NonNull String qrContent,
            @NonNull String title,
            @NonNull String subtitle,
            double labelWidthMm,
            double labelHeightMm,
            Double titleFontSizeMm,
            Double subtitleFontSizeMm,
            @NonNull String layoutType,
            @NonNull HouseprintBluetoothManager.PrinterSettings settings
    ) {
        Bitmap labelBitmap = null;
        try {
            Map<String, Object> basePayload = buildLayoutPayload(
                    settings,
                    labelWidthMm,
                    labelHeightMm,
                    layoutType
            );
            if (titleFontSizeMm != null) {
                basePayload.put("titleFontSizeMm", titleFontSizeMm);
            }
            if (subtitleFontSizeMm != null) {
                basePayload.put("subtitleFontSizeMm", subtitleFontSizeMm);
            }

            emitPrintStatus("preparing", "Preparing print data.", basePayload);
            emitPrintStatus("generatingQr", "Generating QR code.", basePayload);
            emitPrintStatus("renderingLayout", "Rendering print layout.", basePayload);
            labelBitmap = createLabelBitmap(
                    qrContent,
                    title,
                    subtitle,
                    (float) labelWidthMm,
                    (float) labelHeightMm,
                    titleFontSizeMm,
                    subtitleFontSizeMm,
                    settings
            );
            submitBitmapForPrinting(
                    labelBitmap,
                    (float) labelWidthMm,
                    (float) labelHeightMm,
                    layoutType,
                    settings
            );
        } catch (Exception exception) {
            recycleBitmap(labelBitmap);
            printInProgress.set(false);
            Map<String, Object> payload = buildPrintPayload(settings, layoutType);
            payload.put("error", exception.getMessage());
            emitPrintStatus("error", "Failed to prepare the print layout.", payload);
        }
    }

    private void startCenteredQrTitlePrint(
            @NonNull String qrContent,
            @NonNull String title,
            double labelWidthMm,
            double labelHeightMm,
            Double titleFontSizeMm,
            @NonNull HouseprintBluetoothManager.PrinterSettings settings
    ) {
        Bitmap labelBitmap = null;
        try {
            Map<String, Object> basePayload = buildLayoutPayload(
                    settings,
                    labelWidthMm,
                    labelHeightMm,
                    LAYOUT_QR_WITH_CENTERED_TITLE
            );
            if (titleFontSizeMm != null) {
                basePayload.put("titleFontSizeMm", titleFontSizeMm);
            }

            emitPrintStatus("preparing", "Preparing print data.", basePayload);
            emitPrintStatus("generatingQr", "Generating QR code.", basePayload);
            emitPrintStatus("renderingLayout", "Rendering print layout.", basePayload);
            labelBitmap = createCenteredQrTitleBitmap(
                    qrContent,
                    title,
                    (float) labelWidthMm,
                    (float) labelHeightMm,
                    titleFontSizeMm,
                    settings
            );
            submitBitmapForPrinting(
                    labelBitmap,
                    (float) labelWidthMm,
                    (float) labelHeightMm,
                    LAYOUT_QR_WITH_CENTERED_TITLE,
                    settings
            );
        } catch (Exception exception) {
            recycleBitmap(labelBitmap);
            printInProgress.set(false);
            Map<String, Object> payload = buildPrintPayload(settings, LAYOUT_QR_WITH_CENTERED_TITLE);
            payload.put("error", exception.getMessage());
            emitPrintStatus("error", "Failed to prepare the print layout.", payload);
        }
    }

    private void submitBitmapForPrinting(
            @NonNull Bitmap labelBitmap,
            float labelWidthMm,
            float labelHeightMm,
            @NonNull String layoutType,
            @NonNull HouseprintBluetoothManager.PrinterSettings settings
    ) {
        AtomicBoolean dataCommitted = new AtomicBoolean(false);
        AtomicBoolean finished = new AtomicBoolean(false);

        printApi.setTotalPrintQuantity(1);
        emitPrintStatus("starting", "Starting print job.", buildPrintPayload(settings, layoutType));
        printApi.startPrintJob(settings.getPrintDensity(), 1, settings.getPrintMode(), new PrintCallback() {
            @Override
            public void onError(int errorCode) {
                // The SDK also reports the detailed variant below.
            }

            @Override
            public void onError(int errorCode, int printStateCode) {
                if (!finished.compareAndSet(false, true)) {
                    return;
                }

                recycleBitmap(labelBitmap);
                printInProgress.set(false);

                Map<String, Object> payload = buildPrintPayload(settings, layoutType);
                payload.put("errorCode", errorCode);
                payload.put("printStateCode", printStateCode);
                emitPrintStatus("error", "Printing failed.", payload);
            }

            @Override
            public void onBufferFree(int pageIndex, int bufferSize) {
                if (finished.get() || dataCommitted.get()) {
                    return;
                }

                emitPrintStatus("sending", "Sending bitmap data to printer.", buildProgressPayload(settings, pageIndex, 1, layoutType));
                printApi.commitImageData(0, labelBitmap, labelWidthMm, labelHeightMm, 1, 0, 0, 0, 0, "");
                dataCommitted.set(true);
            }

            @Override
            public void onProgress(int pageIndex, int quantityIndex, HashMap<String, Object> extras) {
                emitPrintStatus("progress", "Print job is in progress.", buildProgressPayload(settings, pageIndex, quantityIndex, layoutType));
                if (pageIndex < 1 || quantityIndex < 1 || !finished.compareAndSet(false, true)) {
                    return;
                }

                printApi.endPrintJob();
                recycleBitmap(labelBitmap);
                printInProgress.set(false);
                emitPrintStatus("completed", "Print job completed.", buildProgressPayload(settings, pageIndex, quantityIndex, layoutType));
            }

            @Override
            public void onCancelJob(boolean success) {
                if (!finished.compareAndSet(false, true)) {
                    return;
                }

                recycleBitmap(labelBitmap);
                printInProgress.set(false);

                Map<String, Object> payload = buildPrintPayload(settings, layoutType);
                payload.put("cancelSuccess", success);
                emitPrintStatus("cancelled", success ? "Print job cancelled." : "Print cancellation failed.", payload);
            }
        });
    }

    @NonNull
    private Bitmap createLabelBitmap(
            @NonNull String qrContent,
            @NonNull String title,
            @NonNull String subtitle,
            float labelWidthMm,
            float labelHeightMm,
            Double titleFontSizeMm,
            Double subtitleFontSizeMm,
            @NonNull HouseprintBluetoothManager.PrinterSettings settings
    ) throws WriterException {
        float multiple = settings.getPrintMultiple() > 0 ? settings.getPrintMultiple() : 8.0f;
        int bitmapWidth = Math.max(JCPrintApi.mmToPixel(labelWidthMm, multiple), 1);
        int bitmapHeight = Math.max(JCPrintApi.mmToPixel(labelHeightMm, multiple), 1);
        int padding = Math.max(JCPrintApi.mmToPixel(2.0f, multiple), 12);
        int qrSize = Math.min(bitmapHeight - (padding * 2), (int) (bitmapWidth * 0.34f));
        qrSize = Math.max(qrSize, Math.min(bitmapHeight / 2, bitmapWidth / 4));

        Bitmap labelBitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(labelBitmap);
        canvas.drawColor(Color.WHITE);

        Bitmap qrBitmap = generateQrBitmap(qrContent, qrSize);
        int qrTop = (bitmapHeight - qrSize) / 2;
        canvas.drawBitmap(qrBitmap, padding, qrTop, null);
        qrBitmap.recycle();

        int textStartX = padding + qrSize + padding;
        int textWidth = Math.max(bitmapWidth - textStartX - padding, 1);

        TextPaint titlePaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        titlePaint.setColor(Color.BLACK);
        titlePaint.setFakeBoldText(true);
        titlePaint.setTextSize(resolveTextSize(titleFontSizeMm, bitmapHeight * 0.22f, multiple));

        TextPaint subtitlePaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        subtitlePaint.setColor(Color.DKGRAY);
        subtitlePaint.setTextSize(resolveTextSize(subtitleFontSizeMm, bitmapHeight * 0.16f, multiple));

        int textAreaTop = padding;
        int textAreaHeight = Math.max(bitmapHeight - (padding * 2), 1);
        int lineGap = Math.max(JCPrintApi.mmToPixel(0.6f, multiple), 2);

        StaticLayout titleLayout = createStaticLayout(title, titlePaint, textWidth);
        StaticLayout subtitleLayout = createStaticLayout(subtitle, subtitlePaint, textWidth);
        int titleHeight = Math.max(titleLayout.getHeight(), 0);
        int subtitleHeight = Math.max(subtitleLayout.getHeight(), 0);
        int totalTextBlockHeight = titleHeight + lineGap + subtitleHeight;
        float blockTop = textAreaTop + Math.max((textAreaHeight - totalTextBlockHeight) / 2.0f, 0.0f);

        drawStackedTextLayouts(
                canvas,
                titleLayout,
                subtitleLayout,
                textStartX,
                blockTop,
                textWidth,
                textAreaTop,
                textAreaHeight,
                lineGap
        );
        return labelBitmap;
    }

    @NonNull
    private Bitmap createCenteredQrTitleBitmap(
            @NonNull String qrContent,
            @NonNull String title,
            float labelWidthMm,
            float labelHeightMm,
            Double titleFontSizeMm,
            @NonNull HouseprintBluetoothManager.PrinterSettings settings
    ) throws WriterException {
        float multiple = settings.getPrintMultiple() > 0 ? settings.getPrintMultiple() : 8.0f;
        int bitmapWidth = Math.max(JCPrintApi.mmToPixel(labelWidthMm, multiple), 1);
        int bitmapHeight = Math.max(JCPrintApi.mmToPixel(labelHeightMm, multiple), 1);
        int padding = Math.max(JCPrintApi.mmToPixel(2.0f, multiple), 12);
        int contentWidth = Math.max(bitmapWidth - (padding * 2), 1);
        int contentHeight = Math.max(bitmapHeight - (padding * 2), 1);
        int lineGap = Math.max(JCPrintApi.mmToPixel(0.6f, multiple), 2);

        Bitmap labelBitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(labelBitmap);
        canvas.drawColor(Color.WHITE);

        TextPaint titlePaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        titlePaint.setColor(Color.BLACK);
        titlePaint.setFakeBoldText(true);
        titlePaint.setTextSize(resolveTextSize(titleFontSizeMm, bitmapHeight * 0.15f, multiple));

        StaticLayout titleLayout = createStaticLayout(
                title,
                titlePaint,
                contentWidth,
                Layout.Alignment.ALIGN_CENTER
        );
        int maxQrSize = Math.max(contentHeight - lineGap - titleLayout.getHeight(), 1);
        // Increase the QR code footprint for the centered layout while still
        // leaving enough room for the title underneath.
        int preferredQrSize = Math.min(contentWidth, Math.round(contentHeight * 0.72f));
        int qrSize = Math.max(Math.min(preferredQrSize, maxQrSize), 1);

        Bitmap qrBitmap = generateQrBitmap(qrContent, qrSize);
        int totalBlockHeight = qrSize + lineGap + titleLayout.getHeight();
        float blockTop = padding + Math.max((contentHeight - totalBlockHeight) / 2.0f, 0.0f);
        float qrLeft = (bitmapWidth - qrSize) / 2.0f;
        canvas.drawBitmap(qrBitmap, qrLeft, blockTop, null);
        qrBitmap.recycle();

        drawSingleTextLayout(
                canvas,
                titleLayout,
                padding,
                blockTop + qrSize + lineGap,
                contentWidth,
                padding,
                contentHeight
        );
        return labelBitmap;
    }

    private float resolveTextSize(Double textSizeMm, float fallbackSizePx, float printMultiple) {
        if (textSizeMm == null || textSizeMm <= 0) {
            return fallbackSizePx;
        }
        return Math.max(JCPrintApi.mmToPixel(textSizeMm.floatValue(), printMultiple), 1);
    }

    @NonNull
    private StaticLayout createStaticLayout(
            @NonNull String text,
            @NonNull TextPaint textPaint,
            int textWidth
    ) {
        return createStaticLayout(text, textPaint, textWidth, Layout.Alignment.ALIGN_NORMAL);
    }

    @NonNull
    private StaticLayout createStaticLayout(
            @NonNull String text,
            @NonNull TextPaint textPaint,
            int textWidth,
            @NonNull Layout.Alignment alignment
    ) {
        return new StaticLayout(
                text,
                textPaint,
                Math.max(textWidth, 1),
                alignment,
                1.1f,
                0.0f,
                false
        );
    }

    private void drawStackedTextLayouts(
            @NonNull Canvas canvas,
            @NonNull StaticLayout titleLayout,
            @NonNull StaticLayout subtitleLayout,
            int left,
            float top,
            int width,
            int clipTop,
            int clipHeight,
            int lineGap
    ) {
        int safeWidth = Math.max(width, 1);
        int safeClipHeight = Math.max(clipHeight, 1);
        float subtitleTop = top + titleLayout.getHeight() + lineGap;

        canvas.save();
        canvas.clipRect(left, clipTop, left + safeWidth, clipTop + safeClipHeight);
        canvas.translate(left, top);
        titleLayout.draw(canvas);
        canvas.translate(0.0f, subtitleTop - top);
        subtitleLayout.draw(canvas);
        canvas.restore();
    }

    private void drawSingleTextLayout(
            @NonNull Canvas canvas,
            @NonNull StaticLayout textLayout,
            int left,
            float top,
            int width,
            int clipTop,
            int clipHeight
    ) {
        int safeWidth = Math.max(width, 1);
        int safeClipHeight = Math.max(clipHeight, 1);

        canvas.save();
        canvas.clipRect(left, clipTop, left + safeWidth, clipTop + safeClipHeight);
        canvas.translate(left, top);
        textLayout.draw(canvas);
        canvas.restore();
    }

    @NonNull
    private Bitmap generateQrBitmap(@NonNull String qrContent, int size) throws WriterException {
        Map<EncodeHintType, Object> hints = new HashMap<>();
        hints.put(EncodeHintType.MARGIN, 0);
        hints.put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M);
        hints.put(EncodeHintType.CHARACTER_SET, "UTF-8");

        BitMatrix bitMatrix = new MultiFormatWriter().encode(qrContent, BarcodeFormat.QR_CODE, size, size, hints);
        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) {
                bitmap.setPixel(x, y, bitMatrix.get(x, y) ? Color.BLACK : Color.WHITE);
            }
        }
        return bitmap;
    }

    @NonNull
    private Map<String, Object> buildProgressPayload(
            @NonNull HouseprintBluetoothManager.PrinterSettings settings,
            int pageIndex,
            int quantityIndex,
            @Nullable String layoutType
    ) {
        Map<String, Object> payload = buildPrintPayload(settings, layoutType);
        payload.put("pageIndex", pageIndex);
        payload.put("quantityIndex", quantityIndex);
        return payload;
    }

    @NonNull
    private Map<String, Object> buildPrintPayload(HouseprintBluetoothManager.PrinterSettings settings) {
        return buildPrintPayload(settings, null);
    }

    @NonNull
    private Map<String, Object> buildPrintPayload(
            HouseprintBluetoothManager.PrinterSettings settings,
            @Nullable String layoutType
    ) {
        Map<String, Object> payload = new HashMap<>();
        HouseprintBluetoothManager.PrinterSettings safeSettings = settings != null
                ? settings
                : bluetoothManager.getCurrentPrinterSettings();
        payload.put("connected", bluetoothManager.isConnected());
        payload.put("printMode", safeSettings.getPrintMode());
        payload.put("printDensity", safeSettings.getPrintDensity());
        payload.put("printMultiple", (double) safeSettings.getPrintMultiple());
        if (!TextUtils.isEmpty(layoutType)) {
            payload.put("layoutType", layoutType);
        }
        return payload;
    }

    @NonNull
    private Map<String, Object> buildLayoutPayload(
            @NonNull HouseprintBluetoothManager.PrinterSettings settings,
            double labelWidthMm,
            double labelHeightMm,
            @NonNull String layoutType
    ) {
        Map<String, Object> payload = buildPrintPayload(settings, layoutType);
        payload.put("labelWidthMm", labelWidthMm);
        payload.put("labelHeightMm", labelHeightMm);
        return payload;
    }

    private void recycleBitmap(Bitmap bitmap) {
        if (bitmap != null && !bitmap.isRecycled()) {
            bitmap.recycle();
        }
    }

    private void emitPrintStatus(@NonNull String state, @NonNull String message, @NonNull Map<String, Object> payload) {
        synchronized (stateLock) {
            printState = state;
            printMessage = message;
            printPayload = new HashMap<>(payload);
        }

        Map<String, Object> status = new HashMap<>();
        status.put("type", "print");
        status.put("state", state);
        status.put("message", message);
        status.put("payload", new HashMap<>(payload));

        mainHandler.post(() -> statusCallback.onStatusChanged(status));
    }
}
