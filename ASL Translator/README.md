# ASL Translator App

## Overview
This iOS application uses the device camera to detect hands and display text that follows hand movements, creating an augmented reality experience. This initial version displays custom text near detected hands. Future versions will include ASL translation capability.

## Features
- Real-time hand detection using ARKit and Vision framework
- Custom text display that follows hand movement
- Adjustable text content
- Responsive AR interface

## Requirements
- iOS device with camera (iPhone or iPad)
- iOS 14.0 or later
- Device must support ARKit functionality

## Usage Instructions
1. Launch the app
2. Enter the text you want to display near detected hands
3. Tap "Start Translating" to begin
4. Point your camera at your hand
5. The app will detect your hand and display your custom text nearby
6. Move your hand to see the text follow along
7. Tap the back button to return to the home screen

## Fixing Full-Screen Display Issues

If the app appears with large bezels (letterboxing) or doesn't use the full screen, follow these steps:

### Update Info.plist
1. Open your project in Xcode
2. Find and open `Info.plist`
3. Add or modify these keys:

```
<key>UIViewControllerBasedStatusBarAppearance</key>
<false/>
<key>UIStatusBarHidden</key>
<true/>
<key>UIRequiresFullScreen</key>
<true/>
<key>UILaunchStoryboardName</key>
<string>LaunchScreen</string>
```

### Update Project Settings
1. In Xcode, select your project in the Navigator
2. Select your app target
3. Go to the "General" tab
4. Under "Deployment Info":
   - Verify "Status Bar Style" is set to "Hidden"
   - Ensure "Hide status bar" is checked
   - Make sure all device orientations you want to support are checked

### Other Recommendations
- Ensure your LaunchScreen matches your main app's background color to avoid visual transitions
- For AR-based apps, consider setting "Requires full screen" to true in your target settings

## Development Notes
The app is built using:
- SwiftUI for user interface
- ARKit for augmented reality
- Vision framework for hand tracking
- MVVM architecture pattern

## Future Enhancements
- ASL gesture recognition and translation
- Support for multiple hands simultaneously
- Additional customization options for text appearance
- Gesture recognition for interactive features

## Project Structure
- **ASLTranslatorApp.swift**: Main app entry point
- **ContentView.swift**: Main SwiftUI interface
- **ARViewModel.swift**: Core hand tracking and AR logic
- **ARViewContainer.swift**: SwiftUI wrapper for ARKit
