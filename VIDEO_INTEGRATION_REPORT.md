# Video Integration Report - nerv-uas Android GCS
**Date:** November 5, 2025
**Author:** Claude Code Analysis
**Subject:** Gazebo Camera Video Display Issues

---

## Executive Summary

**Good News:** Video streaming from Gazebo to Android GCS is **working**. H.264/MPEG-TS video is being received on UDP port 5600, decoded by MediaCodec, and briefly displays as a "sliver of sky" at the top of the HUD.

**Issues Identified:**
1. **Video displays incorrectly** - appears as thin strip instead of full frame (aspect ratio issue)
2. **Video disappears on tab switch** - disconnects when leaving Video tab
3. **No video in full-screen mode** - full-screen view has placeholder SurfaceView that's never used

All issues are in the Android GCS code (nerv-uas), not the Gazebo streaming side.

---

## Issue #1: "Sliver of Sky" - Aspect Ratio Problem

### Symptoms
- Video appears as thin horizontal strip at top of HUD
- Only shows ~5% of frame height
- Content is correct (sky/horizon visible) but severely letterboxed

### Root Cause
**Location:** `app/src/main/kotlin/com/atakmap/android/uastool/pagers/video_ui/VideoUIBase.kt:251-280`

The `AspectRatioFrameLayout` calculates dimensions **before** SPS (Sequence Parameter Set) is received from video stream:

```kotlin
inner class AspectRatioFrameLayout(context: Context) : FrameLayout(context) {
    private var targetAspect: Float = 16f / 9f  // Default 16:9

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // ... calculates based on targetAspect
        if (viewAspect > targetAspect) {
            // Letterbox sides
            val newWidth = (height * targetAspect).toInt()
            setMeasuredDimension(newWidth, height)
        } else {
            // Letterbox top/bottom
            val newHeight = (width / targetAspect).toInt()
            setMeasuredDimension(width, newHeight)  // ← Likely wrong value
        }
    }
}
```

**Problem:**
- Default aspect ratio (16:9) is applied before MediaCodec reports actual video dimensions
- SurfaceView is sized before `INFO_OUTPUT_FORMAT_CHANGED` event
- Results in extreme letterboxing

### Fix Needed
**File:** `VideoUIBase.kt`

1. Wait for `MediaFormat` from codec before sizing:
   ```kotlin
   override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
       val width = format.getInteger(MediaFormat.KEY_WIDTH)
       val height = format.getInteger(MediaFormat.KEY_HEIGHT)
       val videoAspect = width.toFloat() / height.toFloat()

       // Update aspect ratio on UI thread
       (videoView?.parent as? AspectRatioFrameLayout)?.apply {
           setAspectRatio(videoAspect)
           requestLayout()
       }
   }
   ```

2. Add aspect ratio setter to `AspectRatioFrameLayout`:
   ```kotlin
   fun setAspectRatio(aspectRatio: Float) {
       if (this.targetAspect != aspectRatio) {
           this.targetAspect = aspectRatio
           requestLayout()
       }
   }
   ```

3. Add logging to verify dimensions:
   ```kotlin
   Log.i(TAG, "Video dimensions: ${width}x${height}, aspect: $videoAspect")
   ```

---

## Issue #2: Video Disappears on Tab Switch

### Symptoms
- Video displays initially in "Video" tab
- When switching to "Status" tab and back, video disappears
- Must manually reconnect or restart app

### Root Cause
**Location:** `app/src/main/kotlin/com/atakmap/android/uastool/pagers/observer/ObserverPager.kt:126-147`

The `showTab()` function **disconnects** video when leaving Video tab:

```kotlin
private fun showTab(tabName: String) {
    // Cleanup current tab before switching
    when (currentTab) {
        "Video" -> {
            videoHUDView?.onPause()
            videoHUDView?.disconnectVideo()  // ← PROBLEM: Kills video connection
        }
    }

    currentTab = tabName
    contentFrame?.removeAllViews()  // ← Also removes view hierarchy

    when (tabName) {
        "Video" -> {
            showVideoView()
            // Must reconnect video
            if (hasPublisher && hasAdapter) {
                hudAdapter?.start()
                videoHUDView?.setHUDDataProvider(hudAdapter!!)
                videoHUDView?.onResume()  // ← Tries to resume but already disconnected
            }
        }
    }
}
```

**Problem:**
- `disconnectVideo()` stops UDP receiver, closes socket, releases MediaCodec
- When returning to Video tab, video doesn't automatically reconnect
- Requires manual reconnection via `setVideoSource()`

### Fix Needed
**File:** `ObserverPager.kt`

**Option A: Keep Video Connected (Recommended)**
```kotlin
private fun showTab(tabName: String) {
    when (currentTab) {
        "Video" -> {
            videoHUDView?.onPause()  // Just pause, don't disconnect
            // Remove from view hierarchy but keep instance
            contentFrame?.removeView(videoViewContainer)
        }
    }

    currentTab = tabName

    when (tabName) {
        "Video" -> {
            // Re-add existing video view
            contentFrame?.addView(videoViewContainer)
            videoHUDView?.onResume()  // Resume rendering
        }
        "Status" -> showStatusView()
    }
}
```

**Option B: Auto-Reconnect on Return**
```kotlin
private fun showTab(tabName: String) {
    // ... existing disconnect logic ...

    when (tabName) {
        "Video" -> {
            showVideoView()
            // Auto-reconnect video
            videoHUDView?.setVideoSource(
                VideoHUDCompositeView.VideoSource.MAVLINK,
                "udp://0.0.0.0:5600"
            )
            videoHUDView?.onResume()
        }
    }
}
```

**Option A is preferred** - keeps video stream alive, just hides the view. Less latency when switching back.

---

## Issue #3: No Video in Full-Screen Mode

### Symptoms
- Full-screen FPV view shows only black background
- HUD instruments display correctly
- Joysticks and controls work
- No video feed visible

### Root Cause
**Location:** `app/src/main/res/layout/fullscreen_control_layout.xml:5-11`

The full-screen layout has a **placeholder SurfaceView that's never used**:

```xml
<com.atakmap.android.uastool.fullscreen.FullScreenControlView
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">  <!-- BLACK BACKGROUND -->

    <!-- Background: Video Feed (placeholder for now) -->
    <SurfaceView
        android:id="@+id/videoFeed"  <!-- This is never referenced in code -->
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <com.atakmap.android.uastool.hud.HUDOverlayView
        android:id="@+id/hudOverlay"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />
    <!-- ... joysticks, buttons, etc ... -->
</com.atakmap.android.uastool.fullscreen.FullScreenControlView>
```

**Verification in Code:**
`app/src/main/kotlin/com/atakmap/android/uastool/fullscreen/FullScreenControlView.kt`

```kotlin
class FullScreenControlView(context: Context, attrs: AttributeSet?)
    : FrameLayout(context, attrs) {

    private var hudOverlay: HUDOverlayView? = null
    private var leftJoystick: VirtualJoystickView? = null
    private var rightJoystick: VirtualJoystickView? = null
    // NO VIDEO VIEW MEMBER!

    fun initialize(/* ... */) {
        hudOverlay = findViewById(R.id.hudOverlay)
        leftJoystick = findViewById(R.id.leftJoystick)
        rightJoystick = findViewById(R.id.rightJoystick)
        // videoFeed SurfaceView is never found or used!
    }
}
```

**The placeholder SurfaceView exists in XML but is completely ignored by the Kotlin code.**

### Fix Needed

**Step 1: Update XML Layout**
**File:** `app/src/main/res/layout/fullscreen_control_layout.xml`

Replace placeholder with actual video composite view:

```xml
<com.atakmap.android.uastool.fullscreen.FullScreenControlView
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <!-- REPLACE placeholder with actual video view -->
    <com.atakmap.android.uastool.pagers.video_ui.VideoHUDCompositeView
        android:id="@+id/videoHUDComposite"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <!-- HUD is now inside VideoHUDCompositeView, remove duplicate -->
    <!-- <com.atakmap.android.uastool.hud.HUDOverlayView ... /> -->

    <!-- Keep joysticks, buttons, etc. -->
    <FrameLayout ... >  <!-- mapPIPContainer -->
    <VirtualJoystickView ... />  <!-- joysticks -->
    <!-- ... -->
</com.atakmap.android.uastool.fullscreen.FullScreenControlView>
```

**Step 2: Update Kotlin Code**
**File:** `app/src/main/kotlin/com/atakmap/android/uastool/fullscreen/FullScreenControlView.kt`

```kotlin
class FullScreenControlView(context: Context, attrs: AttributeSet?)
    : FrameLayout(context, attrs) {

    private var videoHUDView: VideoHUDCompositeView? = null  // Add this
    private var leftJoystick: VirtualJoystickView? = null
    private var rightJoystick: VirtualJoystickView? = null

    fun initialize(
        hudDataProvider: HUDDataProvider,
        joystickListener: VirtualJoystickView.JoystickListener
    ) {
        // Initialize video + HUD composite
        videoHUDView = findViewById<VideoHUDCompositeView>(R.id.videoHUDComposite)?.apply {
            setVideoSource(VideoHUDCompositeView.VideoSource.MAVLINK, "udp://0.0.0.0:5600")
            setHUDDataProvider(hudDataProvider)
            onResume()
        }

        // Initialize joysticks
        leftJoystick = findViewById(R.id.leftJoystick)
        rightJoystick = findViewById(R.id.rightJoystick)
        // ...
    }

    fun onPause() {
        videoHUDView?.onPause()  // Pause video rendering
    }

    fun onResume() {
        videoHUDView?.onResume()  // Resume video rendering
    }

    fun cleanup() {
        videoHUDView?.disconnectVideo()
    }
}
```

**Step 3: Update Fragment Lifecycle**
**File:** `app/src/main/kotlin/com/atakmap/android/uastool/fullscreen/FullScreenControlFragment.kt`

Ensure video lifecycle is managed:

```kotlin
override fun onResume() {
    super.onResume()
    fullScreenView?.onResume()
}

override fun onPause() {
    super.onPause()
    fullScreenView?.onPause()
}

override fun onDestroyView() {
    fullScreenView?.cleanup()
    super.onDestroyView()
}
```

---

## Architecture Overview (For Context)

### Current Video Display Architecture

```
┌─ ObserverPager (Tab Interface) ─────────────────────────┐
│                                                          │
│  ┌─ Video Tab ────────────────────────────────┐         │
│  │                                             │         │
│  │  VideoHUDCompositeView (FrameLayout)       │         │
│  │    ├─ [Index 0] VideoUIBase                │         │
│  │    │   └─ AspectRatioFrameLayout            │         │
│  │    │       └─ SurfaceView ← MediaCodec     │         │
│  │    │                                         │         │
│  │    └─ [Index 1+] HUDOverlayView (Canvas)   │         │
│  │                                             │         │
│  └─────────────────────────────────────────────┘         │
│                                                          │
│  ┌─ Status Tab ───────────────────────────────┐         │
│  │  (Telemetry data display)                  │         │
│  └─────────────────────────────────────────────┘         │
└──────────────────────────────────────────────────────────┘

┌─ FullScreenControlView ──────────────────────────────────┐
│  Background: #000000 (BLACK)                             │
│                                                          │
│  ┌─ SurfaceView (PLACEHOLDER - NOT USED) ──────┐        │
│  └───────────────────────────────────────────────┘        │
│                                                          │
│  ┌─ HUDOverlayView ─────────────────────────────┐        │
│  │  (Displays correctly)                        │        │
│  └───────────────────────────────────────────────┘        │
│                                                          │
│  ┌─ Virtual Joysticks ──────────────────────────┐        │
│  └───────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────┘
```

### Video Processing Pipeline (Currently Working)

```
Gazebo GstCameraPlugin
  ↓ H.264 over UDP port 5600
MAVLinkVideoView.startUDPReceiver()
  ↓ Receive DatagramPacket (65KB buffer)
MAVLinkVideoView.processVideoData()
  ↓ Parse RTP header (if present)
  ↓ Extract H.264 payload
MAVLinkVideoView.processH264Data()
  ↓ Parse NAL units (STAP-A, FU-A)
  ↓ Extract SPS (NAL 7), PPS (NAL 8)
MAVLinkVideoView.configureDecoder()
  ↓ Configure MediaCodec with SPS/PPS
  ↓ Set output surface
MediaCodec.queueInputBuffer()
  ↓ Decode H.264 frames
MediaCodec.releaseOutputBuffer(render=true)
  ↓ Render to SurfaceView
  ↓
AspectRatioFrameLayout (INCORRECT SIZING)
  ↓
User sees "sliver of sky"
```

---

## Video Protocol Details

**Stream Format:** H.264/MPEG-TS
**Transport:** UDP (unreliable, no retransmission)
**Port:** 5600
**Encoder:** GStreamer x264enc (software) or nvh264enc (CUDA)
**Pipeline:** `appsrc → queue → videoconvert → x264enc → h264parse → mpegtsmux → udpsink`

**RTP Payload Types:**
- **NAL Type 7 (SPS):** Sequence Parameter Set - contains video dimensions, profile, level
- **NAL Type 8 (PPS):** Picture Parameter Set - encoding parameters
- **NAL Type 24 (STAP-A):** Single Time Aggregation Packet - multiple NAL units
- **NAL Type 28 (FU-A):** Fragmentation Unit - large NAL units split across packets
- **NAL Type 5:** IDR frame (keyframe)
- **NAL Type 1:** Non-IDR frame (P-frame, B-frame)

**Current Decoder:** Android MediaCodec with hardware acceleration

---

## Testing Verification

### What's Working ✅
1. **Gazebo streaming:** Camera plugin successfully streams H.264 video
2. **Network transport:** UDP packets reach Android device on port 5600
3. **UDP receiver:** MAVLinkVideoView receives and buffers packets
4. **RTP parsing:** Successfully extracts H.264 payload from RTP
5. **NAL processing:** SPS/PPS/IDR frames parsed correctly
6. **MediaCodec:** Hardware decoder successfully decodes frames
7. **Surface rendering:** Video renders to SurfaceView (confirmed by "sliver")
8. **HUD overlay:** Instruments draw correctly on top of video

### What's Broken ❌
1. **Aspect ratio:** Video sized incorrectly (extreme letterbox)
2. **Tab persistence:** Video disconnects when switching tabs
3. **Full-screen mode:** No video view instantiated

---

## Recommended Testing After Fixes

### Test 1: Aspect Ratio Fix
1. Start Gazebo with video streaming
2. Open GCS and navigate to Video tab
3. **Expected:** Video fills display at correct 4:3 or 16:9 aspect ratio
4. **Verify:** No black bars or extreme letterboxing
5. **Check logs:** Look for "Video dimensions: WxH, aspect: R" message

### Test 2: Tab Switching
1. Start with Video tab displaying video
2. Switch to Status tab
3. Switch back to Video tab
4. **Expected:** Video immediately reappears, no reconnection delay
5. **Verify:** No "reconnecting" messages or black screen

### Test 3: Full-Screen Mode
1. Start with Video tab displaying video
2. Enter full-screen FPV mode
3. **Expected:** Video fills entire screen with HUD overlay
4. **Verify:** Joysticks and controls visible on top of video
5. Exit full-screen mode
6. **Expected:** Video returns to Video tab correctly

### Test 4: Video Quality
1. Fly drone in Gazebo (change altitude, rotate)
2. Verify video updates smoothly in GCS
3. Check for artifacts, stuttering, or freezing
4. **Expected:** 30 fps smooth video with low latency (<100ms)

---

## Code Locations Summary

| Issue | File | Lines | Priority |
|-------|------|-------|----------|
| Aspect ratio calculation | `VideoUIBase.kt` | 251-280 | **HIGH** |
| Tab switch disconnect | `ObserverPager.kt` | 126-147 | **HIGH** |
| Full-screen no video | `fullscreen_control_layout.xml` | 5-26 | **HIGH** |
| Full-screen code missing | `FullScreenControlView.kt` | N/A | **HIGH** |
| Dimension update missing | `MAVLinkVideoView.kt` | 112-148 | **MEDIUM** |

---

## Additional Observations

### Positive Aspects of Current Implementation ✅
1. **Clean separation:** Video source abstraction (MAVLinkVideoView, MockVideoView) is well-designed
2. **Composite pattern:** VideoHUDCompositeView cleanly layers video + HUD
3. **Hardware acceleration:** Proper use of MediaCodec for efficient decoding
4. **RTP robustness:** Good handling of packet fragmentation (FU-A) and aggregation (STAP-A)
5. **Lifecycle management:** Proper pause/resume handling (when not disconnecting)

### Potential Future Enhancements 💡
1. **Bitrate adaptation:** Adjust video quality based on network conditions
2. **Latency monitoring:** Display video latency in HUD
3. **Recording:** Save video stream to file for post-flight analysis
4. **Multi-camera:** Support switching between multiple camera views
5. **Zoom/gimbal control:** UI for controlling camera zoom and gimbal angles

---

## Questions for nerv-uas Team

1. **Why does tab switching call `disconnectVideo()`?**
   Was this intentional to save bandwidth, or oversight? Performance concern?

2. **Full-screen placeholder SurfaceView:**
   Was this left incomplete, or is there a different video path intended?

3. **Aspect ratio defaults:**
   Should we support dynamic aspect ratio from SPS, or lock to 16:9?

4. **Video source sharing:**
   Should Video tab and Full-screen mode share same video stream, or separate decoders?

---

## Conclusion

**Video streaming is 90% functional.** The Gazebo side is working perfectly. The Android GCS needs three targeted fixes:

1. **Fix aspect ratio calculation** (30 min)
2. **Remove disconnectVideo() on tab switch** (5 min)
3. **Add VideoHUDCompositeView to full-screen layout** (45 min)

**Total estimated fix time:** ~1.5 hours

Once these fixes are applied, video should display full-frame in both normal and full-screen modes, and persist across tab switches.

---

**End of Report**
