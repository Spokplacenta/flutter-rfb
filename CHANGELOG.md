## 0.0.1

- Initial release

## 0.1.0

- Use dart_rfb 0.2.0
- Support for password authentication

## 0.2.0

- Support for pointer events
- Improved logging

## 0.3.0

- Add CopyRect encoding support

## 0.4.0

- Update `dart_rfb` to version 0.4.1 (hanging fix)
- Introduce `RemoteFrameBufferWidget.onError`
- Introduce `RemoteFrameBufferWidget.connectingWidget`

## 0.5.0

- Update `dart_rfb` to version 0.5.0 (key event support)
- Add key event support

## 0.6.0

- Update `dart_rfb` to version 0.6.0 (clipboard support)
- Add clipboard support

## 0.6.1

- Just a formatting fix

## 0.6.2

- Update `dart_rfb` to version 0.7.0 (refactored read loop)

## 0.7.0

- Use `dart_rfb` 0.9.0 with ZRLE support and widget-side logging
- Fix `Unsupported operation: Infinity or NaN toInt` error in gesture detector
- Add defensive checks for Infinity/NaN values in coordinate calculations
- Fix mouse pointer coordinate mapping to correctly handle different aspect ratios
- Fix coordinate calculation to account for BoxFit.contain scaling and centering offsets
- Fix widget size tracking to update correctly when window is resized
- Use ValueListenableBuilder to react to size changes in real-time
- Improve SizeTrackingWidget to use LayoutBuilder for accurate size updates
- Thanks @Spokplacenta !

## 0.8.0

- Add [RemoteFrameBufferWidget.syncLocalClipboardToRemote] (default `true`) to disable pushing the local clipboard to the remote VNC server
- Add [RemoteFrameBufferWidget.onFirstFrame] callback after the first decoded framebuffer is shown
- Fix perpetual loading spinner when ZRLE leaves the internal buffer at zero but a decoded [Image] exists
- Harden [RemoteFrameBufferWidget._decodeAndUpdateImage] with dimension and buffer length checks
- Migrate keyboard handling from deprecated `RawKeyboard` to `HardwareKeyboard`

## Unreleased

- Requires the `dart_rfb` update request pipelining: the widget no longer sends a `FramebufferUpdateRequest` after each rendered image, the RFB client asks for the next update as soon as it reads an update header
- Compose Raw rectangles row by row with `setRange` (about 20x faster than per pixel)
- CopyRect copies row by row through a row buffer, overlapping areas included
- Publish images at the next vsync, coalesced: at most one `decodeImageFromPixels` at a time, the most recent framebuffer wins, no fixed frame rate cap
- Decode a copy of the framebuffer, with an opaque alpha byte (servers often leave it at 0 in Raw rectangles)
- The image publication always completes, even when a framebuffer is rejected, so the display can no longer freeze
- Pointer input uses a `Listener` instead of a `GestureDetector`: a press is sent at once, outside the gesture arena (also inside an `InteractiveViewer`), and moves with a button pressed are sent, at most one per frame. Only the first pointer is forwarded. The public API is unchanged
- RFB isolate logs at `WARNING` instead of `FINE`
- Add `RemoteFrameBufferWidget.pixelFormat`, the pixel format asked to the server: `RemoteFrameBufferPixelFormat.rgb565` (16 bits, the default), `.bgr233` (8 bits, 64 colours) or `.bgra8888` (32 bits, the previous behaviour). Less data on slow links. `RemoteFrameBufferPixelFormat` is exported by `flutter_rfb`
